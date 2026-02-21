"""
Certificate discovery and selection.

Finds certificates on PKCS#11 tokens by serial number or thumbprint
(the `certId` field from Standard §9.3).  Supports both RSA and ECC keys.
"""

from __future__ import annotations

import hashlib
from typing import Optional

import pkcs11
from pkcs11 import Attribute, ObjectClass, CertificateType, KeyType
from cryptography import x509
from cryptography.hazmat.primitives.serialization import Encoding
from cryptography.x509.oid import ExtensionOID

from signbridge.utils.logging_setup import get_logger

logger = get_logger("crypto.certificate")


# ── Key-usage helpers ───────────────────────────────────────────────────

def _has_non_repudiation(cert: x509.Certificate) -> bool:
    """Return True if the certificate has the *nonRepudiation* (contentCommitment) bit set."""
    try:
        ku = cert.extensions.get_extension_for_oid(ExtensionOID.KEY_USAGE).value
        return bool(ku.content_commitment)  # content_commitment == nonRepudiation
    except (x509.ExtensionNotFound, Exception):
        return False


def _has_digital_signature(cert: x509.Certificate) -> bool:
    """Return True if the certificate has the *digitalSignature* key-usage bit."""
    try:
        ku = cert.extensions.get_extension_for_oid(ExtensionOID.KEY_USAGE).value
        return bool(ku.digital_signature)
    except (x509.ExtensionNotFound, Exception):
        return False


class CertificateInfo:
    """Lightweight wrapper around a PKCS#11 certificate with parsed X.509 metadata."""

    __slots__ = (
        "pkcs11_cert",
        "x509_cert",
        "serial_hex",
        "thumbprint_hex",
        "subject_cn",
        "issuer_cn",
        "is_signing_cert",
        "is_auth_cert",
    )

    def __init__(self, pkcs11_cert: pkcs11.Certificate) -> None:
        self.pkcs11_cert = pkcs11_cert

        # Parse the DER-encoded X.509 certificate
        der_bytes = pkcs11_cert[Attribute.VALUE]
        self.x509_cert = x509.load_der_x509_certificate(der_bytes)

        # Serial number as uppercase hex (used for certId matching)
        self.serial_hex = format(self.x509_cert.serial_number, "X")

        # SHA-1 thumbprint (alternative certId format)
        self.thumbprint_hex = hashlib.sha1(
            self.x509_cert.public_bytes(Encoding.DER)
        ).hexdigest().upper()

        # Subject and issuer common names
        self.subject_cn = self._extract_cn(self.x509_cert.subject)
        self.issuer_cn = self._extract_cn(self.x509_cert.issuer)

        # Key-usage flags
        self.is_signing_cert = _has_non_repudiation(self.x509_cert)
        self.is_auth_cert = (
            _has_digital_signature(self.x509_cert)
            and not self.is_signing_cert
        )

    @staticmethod
    def _extract_cn(name: x509.Name) -> str:
        """Extract the Common Name (CN) from an X.509 Name, or fall back to the full string."""
        try:
            cn_attrs = name.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)
            if cn_attrs:
                return str(cn_attrs[0].value)
        except Exception:
            pass
        return str(name)

    def __repr__(self) -> str:
        kind = "SIGN" if self.is_signing_cert else ("AUTH" if self.is_auth_cert else "OTHER")
        return f"CertificateInfo(cn={self.subject_cn!r}, serial={self.serial_hex}, {kind})"


def find_certificates(
    session: pkcs11.Session,
    *,
    signing_only: bool = False,
) -> list[CertificateInfo]:
    """
    Enumerate X.509 certificates on the token.

    Parameters
    ----------
    signing_only : bool
        When True, only return certificates that have the *nonRepudiation*
        key-usage bit (i.e. signing-suitable certificates).
    """
    raw_certs = list(session.get_objects({
        Attribute.CLASS: ObjectClass.CERTIFICATE,
        Attribute.CERTIFICATE_TYPE: CertificateType.X_509,
    }))
    logger.info("Found %d X.509 certificate(s) on token", len(raw_certs))

    results: list[CertificateInfo] = []
    for rc in raw_certs:
        try:
            ci = CertificateInfo(rc)
            if signing_only and not ci.is_signing_cert:
                logger.debug(
                    "  Skipping non-signing certificate: CN=%s",
                    ci.subject_cn,
                )
                continue
            results.append(ci)
            logger.debug(
                "  Certificate: CN=%s, serial=%s, thumbprint=%s, signing=%s",
                ci.subject_cn,
                ci.serial_hex,
                ci.thumbprint_hex,
                ci.is_signing_cert,
            )
        except Exception as exc:
            logger.warning("Failed to parse certificate: %s", exc)
    return results


def find_certificate_by_id(
    session: pkcs11.Session,
    cert_id: str,
) -> Optional[CertificateInfo]:
    """
    Find a certificate matching the given certId.

    Matching logic:
      1. Exact match on serial number (hex, case-insensitive)
      2. Exact match on SHA-1 thumbprint (hex, case-insensitive)
      3. Substring match on serial (for partial serial numbers)

    Returns None if no match found.
    """
    certs = find_certificates(session)
    needle = cert_id.strip().upper()

    # 1. Exact serial match
    for ci in certs:
        if ci.serial_hex == needle:
            logger.info("Certificate matched by serial: %s", ci)
            return ci

    # 2. Exact thumbprint match
    for ci in certs:
        if ci.thumbprint_hex == needle:
            logger.info("Certificate matched by thumbprint: %s", ci)
            return ci

    # 3. Substring serial match (legacy compatibility)
    for ci in certs:
        if needle in ci.serial_hex:
            logger.info("Certificate matched by partial serial: %s", ci)
            return ci

    logger.warning("No certificate matching certId=%r among %d certificates", cert_id, len(certs))
    return None


def find_private_key(
    session: pkcs11.Session,
    cert_info: CertificateInfo,
) -> Optional[pkcs11.PrivateKey]:
    """
    Find the private key (RSA **or** ECC) corresponding to the given certificate.

    Matches by PKCS#11 ID attribute.  Falls back to returning the first
    private key on the token regardless of key type.
    """
    try:
        cert_id_attr = cert_info.pkcs11_cert[Attribute.ID]
    except Exception:
        cert_id_attr = None

    # Strategy 1: match by ID attribute (key type agnostic)
    if cert_id_attr is not None:
        keys = list(session.get_objects({
            Attribute.CLASS: ObjectClass.PRIVATE_KEY,
            Attribute.ID: cert_id_attr,
        }))
        if keys:
            key = keys[0]
            try:
                kt = key[Attribute.KEY_TYPE]
                logger.info("Private key found by ID attribute match (type=%s)", kt)
            except Exception:
                logger.info("Private key found by ID attribute match")
            return key

    # Strategy 2: first private key of any type
    keys = list(session.get_objects({
        Attribute.CLASS: ObjectClass.PRIVATE_KEY,
    }))
    if keys:
        key = keys[0]
        try:
            kt = key[Attribute.KEY_TYPE]
            logger.info("Private key found — first key on token (type=%s)", kt)
        except Exception:
            logger.info("Private key found — first key on token")
        return key

    logger.warning("No private key found on token")
    return None
