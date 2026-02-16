"""
Request parser — validates and normalises incoming SignRequest per Standard §9.

Validates the JSON structure and returns typed dataclasses for downstream
consumption.  Does NOT resolve object groups — that's object_resolver's job.
"""

from __future__ import annotations

import dataclasses as dc
from typing import Any

from signbridge.config import (
    PROTOCOL_VERSION,
    SUPPORTED_DATA_TYPES,
    INLINE_ALLOWED_TYPES,
    REMOTE_ONLY_TYPES,
)
from signbridge.utils.logging_setup import get_logger

logger = get_logger("messaging.request_parser")


# ─── Error raised on validation failure ─────────────────────────────────────

class RequestValidationError(Exception):
    """Raised when a sign request fails structural validation."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


# ─── Typed data structures ──────────────────────────────────────────────────

@dc.dataclass(frozen=True)
class CertSelector:
    cert_id: str
    label: str | None = None


@dc.dataclass(frozen=True)
class ContentInline:
    mode: str  # "inline"
    encoding: str
    content: str


@dc.dataclass(frozen=True)
class ContentRemote:
    mode: str  # "remote"
    download_url: str
    http_method: str = "GET"
    headers: dict[str, str] = dc.field(default_factory=dict)


@dc.dataclass(frozen=True)
class PdfOptions:
    label: str


@dc.dataclass(frozen=True)
class XmlOptions:
    xpath: str
    id_attribute: str | None = None


@dc.dataclass(frozen=True)
class UploadConfig:
    upload_url: str
    http_method: str = "POST"
    headers: dict[str, str] = dc.field(default_factory=dict)
    signed_content_type: str = "string"


@dc.dataclass(frozen=True)
class CallbacksConfig:
    on_success: str
    on_error: str
    progress: str | None = None
    headers: dict[str, str] = dc.field(default_factory=dict)


@dc.dataclass(frozen=True)
class SignObject:
    """A single object extracted from the top-level objects[] array."""
    id: str
    data_type: str
    content: ContentInline | ContentRemote
    upload: UploadConfig
    callbacks: CallbacksConfig
    pdf_options: PdfOptions | None = None
    xml_options: XmlOptions | None = None


@dc.dataclass(frozen=True)
class GroupInlineObject:
    """An object inside an inline objectGroup."""
    id: str
    encoding: str
    value: str


@dc.dataclass(frozen=True)
class GroupRemoteObject:
    """An object inside a remote objectGroup (id only)."""
    id: str


@dc.dataclass(frozen=True)
class ObjectGroup:
    """A single group from objectGroups[] (Standard §7)."""
    data_type: str
    mode: str  # "inline" | "remote"
    download_url: str | None  # with <objectId> placeholder
    download_headers: dict[str, str]
    pdf_options: PdfOptions | None
    xml_options: XmlOptions | None
    callbacks: CallbacksConfig
    upload: UploadConfig
    objects: list[GroupInlineObject] | list[GroupRemoteObject]


@dc.dataclass(frozen=True)
class SignRequest:
    """Fully parsed and validated sign request (Standard §9)."""
    protocol_version: str
    request_id: str
    app_id: str
    cert: CertSelector
    metadata: dict[str, Any]
    correlation_id: str | None = None
    objects: list[SignObject] | None = None
    object_groups: list[ObjectGroup] | None = None


# ─── Parser ─────────────────────────────────────────────────────────────────

def parse_request(raw: dict[str, Any]) -> SignRequest:
    """
    Validate and parse a raw JSON dict into a SignRequest.

    Raises RequestValidationError on any structural problem.
    """
    # ── Protocol version ------------------------------------------------
    pv = raw.get("protocolVersion")
    if pv is None:
        raise RequestValidationError("BAD_REQUEST", "Missing required field: protocolVersion")
    if pv != PROTOCOL_VERSION:
        raise RequestValidationError("UNSUPPORTED_VERSION", f"Unsupported protocolVersion: {pv}")

    # ── Required root fields -------------------------------------------
    request_id = _require_str(raw, "requestId")
    app_id = _require_str(raw, "appId")
    correlation_id = raw.get("correlationId")
    metadata = raw.get("metadata", {})
    if not isinstance(metadata, dict):
        raise RequestValidationError("BAD_REQUEST", "metadata must be an object")

    # ── Certificate selector -------------------------------------------
    cert_raw = raw.get("cert")
    if not isinstance(cert_raw, dict):
        raise RequestValidationError("BAD_REQUEST", "Missing or invalid cert object")
    cert = CertSelector(
        cert_id=_require_str(cert_raw, "certId", "cert.certId"),
        label=cert_raw.get("label"),
    )

    # ── objects XOR objectGroups (Standard §7.5 Rule 1) ----------------
    has_objects = "objects" in raw
    has_groups = "objectGroups" in raw

    if has_objects and has_groups:
        raise RequestValidationError("BAD_REQUEST", "Request must have objects OR objectGroups, not both")
    if not has_objects and not has_groups:
        raise RequestValidationError("BAD_REQUEST", "Request must have objects or objectGroups")

    objects: list[SignObject] | None = None
    object_groups: list[ObjectGroup] | None = None

    if has_objects:
        raw_objs = raw["objects"]
        if not isinstance(raw_objs, list) or len(raw_objs) == 0:
            raise RequestValidationError("BAD_REQUEST", "objects must be a non-empty array")
        objects = [_parse_object(o, i) for i, o in enumerate(raw_objs)]
    else:
        raw_groups = raw["objectGroups"]
        if not isinstance(raw_groups, list) or len(raw_groups) == 0:
            raise RequestValidationError("BAD_REQUEST", "objectGroups must be a non-empty array")
        object_groups = [_parse_group(g, i) for i, g in enumerate(raw_groups)]

    return SignRequest(
        protocol_version=pv,
        request_id=request_id,
        app_id=app_id,
        cert=cert,
        metadata=metadata,
        correlation_id=correlation_id,
        objects=objects,
        object_groups=object_groups,
    )


# ─── Private helpers ────────────────────────────────────────────────────────

def _require_str(d: dict, key: str, label: str | None = None) -> str:
    val = d.get(key)
    name = label or key
    if not isinstance(val, str) or not val:
        raise RequestValidationError("BAD_REQUEST", f"Missing or empty required field: {name}")
    return val


def _parse_content(raw: dict, obj_label: str) -> ContentInline | ContentRemote:
    """Parse a content object (Standard §5)."""
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{obj_label}: content must be an object")

    mode = raw.get("mode")
    if mode == "inline":
        return ContentInline(
            mode="inline",
            encoding=raw.get("encoding", "utf8"),
            content=_require_str(raw, "content", f"{obj_label}.content.content"),
        )
    elif mode == "remote":
        return ContentRemote(
            mode="remote",
            download_url=_require_str(raw, "downloadUrl", f"{obj_label}.content.downloadUrl"),
            http_method=raw.get("httpMethod", "GET"),
            headers=raw.get("headers") or {},
        )
    else:
        raise RequestValidationError("BAD_REQUEST", f"{obj_label}: content.mode must be 'inline' or 'remote'")


def _parse_upload(raw: Any, label: str) -> UploadConfig:
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{label}: upload must be an object")
    return UploadConfig(
        upload_url=_require_str(raw, "uploadUrl", f"{label}.upload.uploadUrl"),
        http_method=raw.get("httpMethod", "POST"),
        headers=raw.get("headers") or {},
        signed_content_type=_require_str(raw, "signedContentType", f"{label}.upload.signedContentType"),
    )


def _parse_callbacks(raw: Any, label: str) -> CallbacksConfig:
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{label}: callbacks must be an object")
    return CallbacksConfig(
        on_success=_require_str(raw, "onSuccess", f"{label}.callbacks.onSuccess"),
        on_error=_require_str(raw, "onError", f"{label}.callbacks.onError"),
        progress=raw.get("progress"),
        headers=raw.get("headers") or {},
    )


def _parse_pdf_options(raw: Any, label: str) -> PdfOptions:
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{label}: pdfOptions must be an object")
    return PdfOptions(label=_require_str(raw, "label", f"{label}.pdfOptions.label"))


def _parse_xml_options(raw: Any, label: str) -> XmlOptions:
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{label}: xmlOptions must be an object")
    return XmlOptions(
        xpath=_require_str(raw, "xpath", f"{label}.xmlOptions.xpath"),
        id_attribute=raw.get("idAttribute"),
    )


def _parse_object(raw: Any, idx: int) -> SignObject:
    """Parse a single top-level object (Standard §6)."""
    label = f"objects[{idx}]"
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{label} must be an object")

    obj_id = _require_str(raw, "id", f"{label}.id")
    data_type = _require_str(raw, "dataType", f"{label}.dataType")

    if data_type not in SUPPORTED_DATA_TYPES:
        raise RequestValidationError("UNSUPPORTED_TYPE", f"{label}: unsupported dataType '{data_type}'")

    content = _parse_content(raw.get("content", {}), label)

    # Enforce remote-only rule for pdf/binary (Standard §4.2)
    if data_type in REMOTE_ONLY_TYPES and isinstance(content, ContentInline):
        raise RequestValidationError(
            "BAD_REQUEST",
            f"{label}: dataType '{data_type}' requires mode 'remote', got 'inline'",
        )

    upload = _parse_upload(raw.get("upload"), label)
    callbacks = _parse_callbacks(raw.get("callbacks"), label)

    pdf_options = None
    if data_type == "pdf":
        pdf_raw = raw.get("pdfOptions")
        if pdf_raw is None:
            raise RequestValidationError("BAD_REQUEST", f"{label}: pdfOptions required when dataType is 'pdf'")
        pdf_options = _parse_pdf_options(pdf_raw, label)

    xml_options = None
    if data_type == "xml":
        xml_raw = raw.get("xmlOptions")
        if xml_raw is not None:
            xml_options = _parse_xml_options(xml_raw, label)

    return SignObject(
        id=obj_id,
        data_type=data_type,
        content=content,
        upload=upload,
        callbacks=callbacks,
        pdf_options=pdf_options,
        xml_options=xml_options,
    )


def _parse_group(raw: Any, idx: int) -> ObjectGroup:
    """Parse a single objectGroup (Standard §7)."""
    label = f"objectGroups[{idx}]"
    if not isinstance(raw, dict):
        raise RequestValidationError("BAD_REQUEST", f"{label} must be an object")

    data_type = _require_str(raw, "dataType", f"{label}.dataType")
    if data_type not in SUPPORTED_DATA_TYPES:
        raise RequestValidationError("UNSUPPORTED_TYPE", f"{label}: unsupported dataType '{data_type}'")

    mode = _require_str(raw, "mode", f"{label}.mode")
    if mode not in ("inline", "remote"):
        raise RequestValidationError("BAD_REQUEST", f"{label}: mode must be 'inline' or 'remote'")

    # Enforce remote-only for pdf/binary
    if data_type in REMOTE_ONLY_TYPES and mode == "inline":
        raise RequestValidationError(
            "BAD_REQUEST",
            f"{label}: dataType '{data_type}' requires mode 'remote'",
        )

    download_url: str | None = None
    download_headers: dict[str, str] = {}

    if mode == "remote":
        download_url = _require_str(raw, "downloadUrl", f"{label}.downloadUrl")
        if "<objectId>" not in download_url:
            raise RequestValidationError(
                "BAD_REQUEST",
                f"{label}: downloadUrl must contain <objectId> placeholder",
            )
        download_headers = raw.get("downloadHeaders") or {}

    callbacks = _parse_callbacks(raw.get("callbacks"), label)
    upload = _parse_upload(raw.get("upload"), label)

    pdf_options = None
    if data_type == "pdf":
        pdf_raw = raw.get("pdfOptions")
        if pdf_raw is None:
            raise RequestValidationError("BAD_REQUEST", f"{label}: pdfOptions required when dataType is 'pdf'")
        pdf_options = _parse_pdf_options(pdf_raw, label)

    xml_options = None
    if data_type == "xml":
        xml_raw = raw.get("xmlOptions")
        if xml_raw is not None:
            xml_options = _parse_xml_options(xml_raw, label)

    # Parse inner objects
    raw_objects = raw.get("objects")
    if not isinstance(raw_objects, list) or len(raw_objects) == 0:
        raise RequestValidationError("BAD_REQUEST", f"{label}: objects must be a non-empty array")

    objects: list[GroupInlineObject] | list[GroupRemoteObject]
    if mode == "inline":
        inline_objs: list[GroupInlineObject] = []
        for j, ro in enumerate(raw_objects):
            olabel = f"{label}.objects[{j}]"
            if not isinstance(ro, dict):
                raise RequestValidationError("BAD_REQUEST", f"{olabel} must be an object")
            oid = _require_str(ro, "id", f"{olabel}.id")
            c = ro.get("content")
            if not isinstance(c, dict):
                raise RequestValidationError("BAD_REQUEST", f"{olabel}: content is required for inline mode")
            inline_objs.append(GroupInlineObject(
                id=oid,
                encoding=c.get("encoding", "utf8"),
                value=_require_str(c, "value", f"{olabel}.content.value"),
            ))
        objects = inline_objs
    else:
        remote_objs: list[GroupRemoteObject] = []
        for j, ro in enumerate(raw_objects):
            olabel = f"{label}.objects[{j}]"
            if not isinstance(ro, dict):
                raise RequestValidationError("BAD_REQUEST", f"{olabel} must be an object")
            oid = _require_str(ro, "id", f"{olabel}.id")
            remote_objs.append(GroupRemoteObject(id=oid))
        objects = remote_objs

    return ObjectGroup(
        data_type=data_type,
        mode=mode,
        download_url=download_url,
        download_headers=download_headers,
        pdf_options=pdf_options,
        xml_options=xml_options,
        callbacks=callbacks,
        upload=upload,
        objects=objects,
    )
