"""
Processing engine — the main orchestration loop.

For each resolved object:  download → sign → upload → callback.
Accumulates results/errors and builds the final response.

This module is GUI-agnostic. The GUI subscribes to progress via a
callback function.
"""

from __future__ import annotations

from typing import Any, Callable, Optional

import pkcs11

from signbridge.messaging.request_parser import SignRequest
from signbridge.messaging.response_builder import (
    ResponseBuilder,
    ObjectResult,
    ObjectError,
)
from signbridge.processing.object_resolver import ResolvedObject, resolve_objects
from signbridge.network.downloader import download_content, DownloadError
from signbridge.network.uploader import upload_signed_content, UploadResult, UploadError
from signbridge.network.callbacks import (
    send_progress,
    send_success,
    send_error as send_error_callback,
    CallbackError,
)
from signbridge.crypto.signer import sign_content, SigningError
from signbridge.crypto.certificate import CertificateInfo
from signbridge.utils.logging_setup import get_logger

logger = get_logger("processing.engine")

# Type alias for GUI progress callback
# Called as: progress_fn(object_id, percent, message)
ProgressCallback = Callable[[str, int, str], None]


def process_request(
    request: SignRequest,
    session: pkcs11.Session,
    private_key: pkcs11.PrivateKey,
    cert_info: CertificateInfo,
    progress_fn: ProgressCallback | None = None,
    cancel_check: Callable[[], bool] | None = None,
) -> dict[str, Any]:
    """
    Process a complete signing request.

    Parameters
    ----------
    request : SignRequest
        Parsed and validated request.
    session : pkcs11.Session
        Open, authenticated PKCS#11 session.
    private_key : pkcs11.PrivateKey
        The signing key.
    cert_info : CertificateInfo
        Certificate metadata.
    progress_fn : callable | None
        Optional GUI callback: (object_id, percent, message).
    cancel_check : callable | None
        Optional callable returning True if the user cancelled.

    Returns
    -------
    dict
        Standard §10 response dict, ready to be sent via native messaging.
    """
    builder = ResponseBuilder(request.request_id, request.metadata)
    resolved = resolve_objects(request)
    total = len(resolved)

    logger.info("Processing %d object(s) for request %s", total, request.request_id)

    for idx, obj in enumerate(resolved):
        # ── Check cancellation ──────────────────────────────────────────
        if cancel_check and cancel_check():
            logger.info("User cancelled at object %d/%d", idx + 1, total)
            builder.add_error(ObjectError(
                obj_id=obj.id,
                code="CANCELLED_BY_USER",
                message="User cancelled the operation",
            ))
            _try_error_callback(obj, request, "CANCELLED_BY_USER", "User cancelled")
            break

        overall_pct = int((idx / total) * 100) if total > 0 else 0

        try:
            _process_single_object(
                obj=obj,
                request=request,
                session=session,
                private_key=private_key,
                cert_info=cert_info,
                builder=builder,
                progress_fn=progress_fn,
                object_index=idx,
                total_objects=total,
            )
        except Exception as exc:
            # Catch-all: should not reach here, but safety net
            logger.error("Unexpected error processing %s: %s", obj.id, exc, exc_info=True)
            builder.add_error(ObjectError(obj.id, "INTERNAL_ERROR", str(exc)))
            _try_error_callback(obj, request, "INTERNAL_ERROR", str(exc))

    # Final progress
    if progress_fn:
        progress_fn("", 100, f"Complete: {len(builder.results)} ok, {len(builder.errors)} errors")

    return builder.build()


def _process_single_object(
    obj: ResolvedObject,
    request: SignRequest,
    session: pkcs11.Session,
    private_key: pkcs11.PrivateKey,
    cert_info: CertificateInfo,
    builder: ResponseBuilder,
    progress_fn: ProgressCallback | None,
    object_index: int,
    total_objects: int,
) -> None:
    """Process a single resolved object: download → sign → upload → callback."""

    obj_label = f"[{object_index + 1}/{total_objects}] {obj.id}"

    # ── Step 1: Progress — starting ─────────────────────────────────────
    if progress_fn:
        pct = int((object_index / total_objects) * 100)
        progress_fn(obj.id, pct, f"Processing {obj.id}...")

    _try_progress_callback(obj, request, "signing", 0, f"Starting {obj.id}")

    # ── Step 2: Get content ─────────────────────────────────────────────
    logger.info("%s: acquiring content", obj_label)

    try:
        if obj.inline_content is not None:
            content_bytes = obj.inline_content.encode("utf-8")
            logger.debug("%s: inline content, %d bytes", obj_label, len(content_bytes))
        elif obj.download_url is not None:
            content_bytes = download_content(
                url=obj.download_url,
                method=obj.download_method,
                headers=obj.download_headers,
            )
            logger.debug("%s: downloaded %d bytes", obj_label, len(content_bytes))
        else:
            raise ValueError("Object has neither inline content nor download URL")
    except DownloadError as exc:
        logger.error("%s: download failed — %s", obj_label, exc.message)
        builder.add_error(ObjectError(obj.id, exc.code, exc.message))
        _try_error_callback(obj, request, exc.code, exc.message)
        return

    # ── Step 3: Sign ────────────────────────────────────────────────────
    logger.info("%s: signing (%s)", obj_label, obj.data_type)
    _try_progress_callback(obj, request, "signing", 50, f"Signing {obj.id}...")

    if progress_fn:
        pct = int(((object_index + 0.5) / total_objects) * 100)
        progress_fn(obj.id, pct, f"Signing {obj.id}...")

    try:
        signed_bytes = sign_content(
            data=content_bytes,
            data_type=obj.data_type,
            private_key=private_key,
            cert_info=cert_info,
            session=session,
            pdf_label=obj.pdf_label,
            xml_xpath=obj.xml_xpath,
            xml_id_attribute=obj.xml_id_attribute,
        )
    except SigningError as exc:
        logger.error("%s: signing failed — %s", obj_label, exc.message)
        builder.add_error(ObjectError(obj.id, exc.code, exc.message))
        _try_error_callback(obj, request, exc.code, exc.message)
        return

    # ── Step 4: Upload ──────────────────────────────────────────────────
    logger.info("%s: uploading signed content (%d bytes)", obj_label, len(signed_bytes))
    _try_progress_callback(obj, request, "uploading", 75, f"Uploading {obj.id}...")

    try:
        upload_result = upload_signed_content(
            url=obj.upload_url,
            data=signed_bytes,
            signed_content_type=obj.signed_content_type,
            method=obj.upload_method,
            headers=obj.upload_headers,
        )
    except UploadError as exc:
        logger.error("%s: upload failed — %s", obj_label, exc.message)
        builder.add_error(ObjectError(obj.id, exc.code, exc.message))
        _try_error_callback(obj, request, exc.code, exc.message)
        return

    # ── Step 5: Success callback ────────────────────────────────────────
    logger.info("%s: calling success callback", obj_label)
    timestamp = send_success(
        url=obj.callback_on_success,
        object_id=obj.id,
        request_id=request.request_id,
        upload_status_code=upload_result.status_code,
        upload_response_body=upload_result.response_body,
        metadata=request.metadata,
        headers=obj.callback_headers,
    )

    # ── Step 6: Record result ───────────────────────────────────────────
    builder.add_result(ObjectResult(
        obj_id=obj.id,
        upload_status_code=upload_result.status_code,
        upload_response_body=upload_result.response_body,
        callback_endpoint="onSuccess",
        callback_timestamp=timestamp,
    ))

    logger.info("%s: completed successfully", obj_label)


# ─── Safe callback helpers (never raise) ────────────────────────────────────

def _try_progress_callback(
    obj: ResolvedObject,
    request: SignRequest,
    status: str,
    percent: int,
    message: str,
) -> bool:
    """Send a progress callback, catching errors. Returns False on failure."""
    if not obj.callback_progress:
        return True
    try:
        send_progress(
            url=obj.callback_progress,
            object_id=obj.id,
            request_id=request.request_id,
            status=status,
            percent_complete=percent,
            message=message,
            metadata=request.metadata,
            headers=obj.callback_headers,
        )
        return True
    except CallbackError as exc:
        logger.warning("Progress callback failed for %s: %s", obj.id, exc.message)
        return False


def _try_error_callback(
    obj: ResolvedObject,
    request: SignRequest,
    error_code: str,
    error_message: str,
) -> None:
    """Send an error callback, swallowing any failure."""
    try:
        send_error_callback(
            url=obj.callback_on_error,
            object_id=obj.id,
            request_id=request.request_id,
            error_code=error_code,
            error_message=error_message,
            metadata=request.metadata,
            headers=obj.callback_headers,
        )
    except Exception as exc:
        logger.warning("Error callback failed for %s: %s", obj.id, exc)
