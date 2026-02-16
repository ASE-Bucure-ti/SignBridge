"""
Object resolver — flattens both `objects[]` and `objectGroups[]` into
a uniform list of ResolvedObject instances.

This is the single normalisation point: everything downstream works with
ResolvedObjects regardless of whether the request used objects or objectGroups.
"""

from __future__ import annotations

import dataclasses as dc
from typing import Any

from signbridge.messaging.request_parser import (
    SignRequest,
    SignObject,
    ObjectGroup,
    ContentInline,
    ContentRemote,
    GroupInlineObject,
    GroupRemoteObject,
    UploadConfig,
    CallbacksConfig,
    PdfOptions,
    XmlOptions,
)
from signbridge.utils.logging_setup import get_logger

logger = get_logger("processing.object_resolver")


@dc.dataclass
class ResolvedObject:
    """
    A fully-resolved signable item with all URLs/content/options computed.

    Regardless of whether the original request used `objects` or `objectGroups`,
    every object is normalised into this structure.
    """
    id: str
    data_type: str

    # Content — exactly one of these is set:
    inline_content: str | None = None      # UTF-8 text (for inline mode)
    download_url: str | None = None        # Final URL (for remote mode)
    download_method: str = "GET"
    download_headers: dict[str, str] = dc.field(default_factory=dict)

    # Upload
    upload_url: str = ""                   # Final URL (with <objectId> substituted)
    upload_method: str = "POST"
    upload_headers: dict[str, str] = dc.field(default_factory=dict)
    signed_content_type: str = "string"

    # Callbacks
    callback_on_success: str = ""
    callback_on_error: str = ""
    callback_progress: str | None = None
    callback_headers: dict[str, str] = dc.field(default_factory=dict)

    # Type-specific options
    pdf_label: str | None = None
    xml_xpath: str | None = None
    xml_id_attribute: str | None = None


def resolve_objects(request: SignRequest) -> list[ResolvedObject]:
    """
    Resolve all objects from a parsed SignRequest into a flat list.

    Handles both `request.objects` (Standard §6) and
    `request.object_groups` (Standard §7).
    """
    if request.objects is not None:
        return _resolve_from_objects(request.objects)
    elif request.object_groups is not None:
        return _resolve_from_groups(request.object_groups)
    else:
        # Should never happen — parser already validates this
        return []


def _resolve_from_objects(objects: list[SignObject]) -> list[ResolvedObject]:
    """Resolve from the top-level objects[] array."""
    resolved: list[ResolvedObject] = []

    for obj in objects:
        ro = ResolvedObject(
            id=obj.id,
            data_type=obj.data_type,
            # Upload
            upload_url=_sub_id(obj.upload.upload_url, obj.id),
            upload_method=obj.upload.http_method,
            upload_headers=obj.upload.headers,
            signed_content_type=obj.upload.signed_content_type,
            # Callbacks
            callback_on_success=obj.callbacks.on_success,
            callback_on_error=obj.callbacks.on_error,
            callback_progress=obj.callbacks.progress,
            callback_headers=obj.callbacks.headers,
            # PDF/XML options
            pdf_label=obj.pdf_options.label if obj.pdf_options else None,
            xml_xpath=obj.xml_options.xpath if obj.xml_options else None,
            xml_id_attribute=obj.xml_options.id_attribute if obj.xml_options else None,
        )

        # Content
        if isinstance(obj.content, ContentInline):
            ro.inline_content = obj.content.content
        elif isinstance(obj.content, ContentRemote):
            ro.download_url = obj.content.download_url
            ro.download_method = obj.content.http_method
            ro.download_headers = obj.content.headers

        resolved.append(ro)

    logger.info("Resolved %d object(s) from objects[]", len(resolved))
    return resolved


def _resolve_from_groups(groups: list[ObjectGroup]) -> list[ResolvedObject]:
    """Resolve from objectGroups[] with <objectId> template substitution."""
    resolved: list[ResolvedObject] = []

    for group in groups:
        for obj in group.objects:
            obj_id = obj.id

            ro = ResolvedObject(
                id=obj_id,
                data_type=group.data_type,
                # Upload (substitute <objectId>)
                upload_url=_sub_id(group.upload.upload_url, obj_id),
                upload_method=group.upload.http_method,
                upload_headers=group.upload.headers,
                signed_content_type=group.upload.signed_content_type,
                # Callbacks
                callback_on_success=group.callbacks.on_success,
                callback_on_error=group.callbacks.on_error,
                callback_progress=group.callbacks.progress,
                callback_headers=group.callbacks.headers,
                # PDF/XML options
                pdf_label=group.pdf_options.label if group.pdf_options else None,
                xml_xpath=group.xml_options.xpath if group.xml_options else None,
                xml_id_attribute=group.xml_options.id_attribute if group.xml_options else None,
            )

            if group.mode == "inline" and isinstance(obj, GroupInlineObject):
                ro.inline_content = obj.value
            elif group.mode == "remote":
                assert group.download_url is not None
                ro.download_url = _sub_id(group.download_url, obj_id)
                ro.download_method = "GET"
                ro.download_headers = group.download_headers

            resolved.append(ro)

    logger.info("Resolved %d object(s) from %d objectGroup(s)", len(resolved), len(groups))
    return resolved


def _sub_id(template: str, object_id: str) -> str:
    """Substitute <objectId> placeholder in a URL template."""
    return template.replace("<objectId>", object_id)
