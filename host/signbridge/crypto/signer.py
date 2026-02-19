"""
Signing operations — dispatches to the correct signer based on dataType.

Supported:
  • text / json   → SHA-256 hash → PKCS#11 RSA signature → base64 string
  • pdf           → pyHanko visible/invisible signature via PKCS#11
  • binary        → raw PKCS#11 RSA signature over content bytes
  • xml           → enveloped XMLDSig (W3C) via signxml + PKCS#11
"""

from __future__ import annotations

import base64
import hashlib
import io
from typing import TYPE_CHECKING

import pkcs11
from pkcs11 import Mechanism

from signbridge.utils.logging_setup import get_logger

if TYPE_CHECKING:
    from signbridge.crypto.certificate import CertificateInfo

logger = get_logger("crypto.signer")


class SigningError(Exception):
    """Raised when a signing operation fails."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


# ─── Public API ─────────────────────────────────────────────────────────────

def sign_text(
    data: str | bytes,
    private_key: pkcs11.PrivateKey,
) -> bytes:
    """
    Sign a text/json string.

    Returns the raw signature bytes (caller should base64-encode for upload).
    Process: UTF-8 encode → SHA-256 → PKCS#11 RSA sign.
    """
    if isinstance(data, str):
        data = data.encode("utf-8")

    digest = hashlib.sha256(data).digest()
    logger.debug("Text SHA-256 digest: %s (%d bytes input)", digest.hex()[:16] + "...", len(data))

    try:
        signature = private_key.sign(
            digest,
            mechanism=Mechanism.SHA256_RSA_PKCS,
        )
        logger.info("Text signed successfully (%d byte signature)", len(signature))
        return bytes(signature)
    except Exception as exc:
        raise SigningError("SIGN_FAILED", f"PKCS#11 text signing failed: {exc}") from exc


def sign_pdf(
    pdf_bytes: bytes,
    private_key: pkcs11.PrivateKey,
    cert_info: "CertificateInfo",
    session: pkcs11.Session,
    label: str = "Digital Signature",
) -> bytes:
    """
    Sign a PDF document using pyHanko with PKCS#11.

    Returns the signed PDF bytes.
    """
    try:
        from pyhanko.sign import signers
        from pyhanko.sign.fields import SigFieldSpec, append_signature_field
        from pyhanko.sign.pkcs11 import PKCS11Signer
        from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
        from pkcs11 import Attribute as P11Attribute
        from asn1crypto import x509 as asn1_x509
        from cryptography.hazmat.primitives.serialization import Encoding
    except ImportError as exc:
        raise SigningError("INTERNAL_ERROR", f"pyHanko not installed: {exc}") from exc

    try:
        # Build a PKCS#11 signer reusing the already-authenticated session.
        # The cert and private key were already verified in _sign_worker.
        # Link them via CKA_ID (the standard PKCS#11 mechanism to associate
        # a certificate with its private key), NOT by label which can differ.
        try:
            cert_id_bytes = bytes(cert_info.pkcs11_cert[P11Attribute.ID])
        except Exception:
            cert_id_bytes = None

        # Provide the certificate directly so pyHanko doesn't re-discover it.
        cert_der = cert_info.x509_cert.public_bytes(Encoding.DER)
        asn1_cert = asn1_x509.Certificate.load(cert_der)

        signer = PKCS11Signer(
            pkcs11_session=session,
            signing_cert=asn1_cert,
            key_id=cert_id_bytes,
        )

        pdf_reader = IncrementalPdfFileWriter(io.BytesIO(pdf_bytes))

        # Use the pdfOptions.label as the AcroForm signature field name.
        # If the field already exists (e.g., pre-created placeholder), reuse it;
        # otherwise create a new one.
        sig_field = label

        try:
            append_signature_field(pdf_reader, SigFieldSpec(
                sig_field_name=sig_field,
            ))
            logger.debug("Created new signature field %r", sig_field)
        except Exception:
            logger.debug("Signature field %r already exists, reusing it", sig_field)

        result = signers.sign_pdf(
            pdf_reader,
            signers.PdfSignatureMetadata(
                field_name=sig_field,
                reason=f"Signed by SignBridge",
                location="SignBridge",
            ),
            signer=signer,
        )

        signed_bytes = result.getbuffer()
        logger.info("PDF signed successfully (%d bytes → %d bytes)", len(pdf_bytes), len(signed_bytes))
        return bytes(signed_bytes)

    except SigningError:
        raise
    except Exception as exc:
        raise SigningError("SIGN_FAILED", f"PDF signing failed: {exc}") from exc


def sign_binary(
    data: bytes,
    private_key: pkcs11.PrivateKey,
) -> bytes:
    """
    Sign raw binary data.

    Returns the raw signature bytes.
    Process: SHA-256 → PKCS#11 RSA sign.
    """
    digest = hashlib.sha256(data).digest()
    logger.debug("Binary SHA-256 digest: %s (%d bytes input)", digest.hex()[:16] + "...", len(data))

    try:
        signature = private_key.sign(
            digest,
            mechanism=Mechanism.SHA256_RSA_PKCS,
        )
        logger.info("Binary signed successfully (%d byte signature)", len(signature))
        return bytes(signature)
    except Exception as exc:
        raise SigningError("SIGN_FAILED", f"PKCS#11 binary signing failed: {exc}") from exc


def sign_xml(
    data: bytes,
    private_key: pkcs11.PrivateKey,
    cert_info: "CertificateInfo",
    xpath: str | None = None,
    id_attribute: str | None = None,
) -> bytes:
    """
    Sign an XML document using enveloped XMLDSig (W3C) with PKCS#11.

    Produces a standard XML Signature with RSA-SHA256, C14N 1.1, and the
    signing certificate embedded in ``<ds:KeyInfo>``.

    Parameters
    ----------
    data : bytes
        Raw XML document bytes.
    private_key : pkcs11.PrivateKey
        PKCS#11 private key handle.
    cert_info : CertificateInfo
        Certificate info (used for ``<ds:X509Data>`` in the signature).
    xpath : str | None
        XPath expression that locates where the ``<ds:Signature>`` element
        should be placed.  Two modes:

        * If it matches an element whose local name is ``Signature`` —
          that element is treated as an existing placeholder and replaced.
        * If it matches any other element — the signature is inserted as
          a child of that element.
        * If it matches nothing (or is *None*) — the signature is appended
          to the document root (default ``signxml`` behaviour).
    id_attribute : str | None
        Which attribute name to treat as the XML ID for reference-URI
        resolution (e.g. ``"Id"``).  When *None*, ``signxml`` searches
        for ``Id`` then ``ID``.

    Returns
    -------
    bytes
        The complete XML document with the embedded ``<ds:Signature>``.
    """
    try:
        from lxml import etree
        from signxml import XMLSigner
        from signxml.algorithms import (
            CanonicalizationMethod,
            DigestAlgorithm,
            SignatureConstructionMethod,
            SignatureMethod,
        )
    except ImportError as exc:
        raise SigningError("INTERNAL_ERROR", f"signxml not installed: {exc}") from exc

    try:
        # ── PKCS#11 key proxy ─────────────────────────────────────────
        # signxml calls  key.sign(data, padding=…, algorithm=…)  using
        # pure duck-typing (no isinstance check).  We delegate to the
        # hardware token via SHA256_RSA_PKCS which hashes + signs on-chip.
        class _PKCS11KeyProxy:
            """Minimal proxy so signxml can call .sign() on a PKCS#11 key."""

            def sign(self, data: bytes, **_kw: object) -> bytes:
                return bytes(
                    private_key.sign(data, mechanism=Mechanism.SHA256_RSA_PKCS)
                )

            @property
            def key_size(self) -> int:
                return cert_info.x509_cert.public_key().key_size

        proxy_key = _PKCS11KeyProxy()

        # ── Parse XML ─────────────────────────────────────────────────
        root = etree.fromstring(data)

        # ── Signature placement via xpath ─────────────────────────────
        if xpath:
            ns_dsig = "http://www.w3.org/2000/09/xmldsig#"
            targets = root.xpath(xpath)

            if targets and isinstance(targets[0], etree._Element):
                target = targets[0]
                local_name = etree.QName(target).localname

                if local_name == "Signature":
                    # Matched element IS a Signature (placeholder) — reuse it.
                    target.tag = f"{{{ns_dsig}}}Signature"
                    target.set("Id", "placeholder")
                    for child in list(target):
                        target.remove(child)
                    target.text = None
                    logger.debug("Reusing existing Signature element at xpath=%r", xpath)
                else:
                    # Matched element is the parent — insert placeholder as child.
                    placeholder = etree.SubElement(
                        target, f"{{{ns_dsig}}}Signature"
                    )
                    placeholder.set("Id", "placeholder")
                    logger.debug("Signature placeholder inserted inside xpath=%r", xpath)
            else:
                logger.warning(
                    "XPath %r matched nothing; signature will be appended to root", xpath
                )

        # ── Build signer ──────────────────────────────────────────────
        signer = XMLSigner(
            method=SignatureConstructionMethod.enveloped,
            signature_algorithm=SignatureMethod.RSA_SHA256,
            digest_algorithm=DigestAlgorithm.SHA256,
            c14n_algorithm=CanonicalizationMethod.CANONICAL_XML_1_1,
        )

        # ── Sign ──────────────────────────────────────────────────────
        signed_root = signer.sign(
            root,
            key=proxy_key,
            cert=[cert_info.x509_cert],
            id_attribute=id_attribute,
        )

        # ── Serialize ─────────────────────────────────────────────────
        signed_xml = etree.tostring(
            signed_root, xml_declaration=True, encoding="UTF-8"
        )

        logger.info(
            "XML signed successfully (%d bytes → %d bytes)",
            len(data),
            len(signed_xml),
        )
        return signed_xml

    except SigningError:
        raise
    except Exception as exc:
        raise SigningError("SIGN_FAILED", f"XML signing failed: {exc}") from exc


# ─── Dispatcher ─────────────────────────────────────────────────────────────

def sign_content(
    data: bytes,
    data_type: str,
    private_key: pkcs11.PrivateKey,
    cert_info: "CertificateInfo",
    session: pkcs11.Session,
    pdf_label: str | None = None,
    xml_xpath: str | None = None,
    xml_id_attribute: str | None = None,
) -> bytes:
    """
    Sign content based on dataType.

    Parameters
    ----------
    data : bytes
        The raw content to sign.
    data_type : str
        One of: text, json, pdf, binary, xml.
    private_key : pkcs11.PrivateKey
        The PKCS#11 private key handle.
    cert_info : CertificateInfo
        Certificate metadata (used for PDF signature info).
    session : pkcs11.Session
        Active PKCS#11 session (used for PDF signing).
    pdf_label : str | None
        Label for PDF visible signature.
    xml_xpath, xml_id_attribute : str | None
        XML signature parameters (xpath for placement, id_attribute for
        reference-URI resolution).  See :func:`sign_xml`.

    Returns
    -------
    bytes
        The signed output (signature string for text/json, signed PDF for pdf, etc.).
    """
    if data_type in ("text", "json"):
        sig_bytes = sign_text(data, private_key)
        # For text/json, the "signed content" uploaded is the base64 signature
        return base64.b64encode(sig_bytes)

    elif data_type == "pdf":
        return sign_pdf(
            data,
            private_key,
            cert_info,
            session,
            label=pdf_label or "Digital Signature",
        )

    elif data_type == "binary":
        sig_bytes = sign_binary(data, private_key)
        return sig_bytes

    elif data_type == "xml":
        return sign_xml(data, private_key, cert_info, xml_xpath, xml_id_attribute)

    else:
        raise SigningError("UNSUPPORTED_TYPE", f"Unsupported dataType: {data_type}")
