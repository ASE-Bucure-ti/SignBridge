"""
Certificate discovery and selection.

Finds certificates on PKCS#11 tokens by serial number or thumbprint
(the `certId` field from Standard §9.3).
"""

from __future__ import annotations

import hashlib
from typing import Optional

import pkcs11
from pkcs11 import Attribute, ObjectClass, CertificateType
from cryptography import x509
from cryptography.hazmat.primitives.serialization import Encoding

from signbridge.utils.logging_setup import get_logger

logger = get_logger("crypto.certificate")


class CertificateInfo:
    """Lightweight wrapper around a PKCS#11 certificate with parsed X.509 metadata."""

    __slots__ = ("pkcs11_cert", "x509_cert", "serial_hex", "thumbprint_hex", "subject_cn", "issuer_cn")

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
        return f"CertificateInfo(cn={self.subject_cn!r}, serial={self.serial_hex})"


def find_certificates(session: pkcs11.Session) -> list[CertificateInfo]:
    """
    Enumerate all X.509 certificates on the token.

    Returns a list of CertificateInfo wrappers.
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
            results.append(ci)
            logger.debug(
                "  Certificate: CN=%s, serial=%s, thumbprint=%s",
                ci.subject_cn,
                ci.serial_hex,
                ci.thumbprint_hex,
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
    Find the RSA private key corresponding to the given certificate.

    Matches by PKCS#11 ID attribute.
    """
    try:
        cert_id_attr = cert_info.pkcs11_cert[Attribute.ID]
    except Exception:
        cert_id_attr = None

    # Strategy 1: match by ID attribute
    if cert_id_attr is not None:
        keys = list(session.get_objects({
            Attribute.CLASS: ObjectClass.PRIVATE_KEY,
            Attribute.ID: cert_id_attr,
        }))
        if keys:
            logger.info("Private key found by ID attribute match")
            return keys[0]

    # Strategy 2: just get the first RSA private key
    from pkcs11 import KeyType
    keys = list(session.get_objects({
        Attribute.CLASS: ObjectClass.PRIVATE_KEY,
        Attribute.KEY_TYPE: KeyType.RSA,
    }))
    if keys:
        logger.info("Private key found (first RSA key on token)")
        return keys[0]

    logger.warning("No private key found on token")
    return None
