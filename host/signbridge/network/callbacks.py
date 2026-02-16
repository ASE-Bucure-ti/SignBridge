"""
Callback dispatcher — POSTs JSON payloads to callback endpoints.

Standard §8.4–8.6: The native host POSTs status updates to
onSuccess, onError, and progress endpoints.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import requests

from signbridge.config import HTTP_TIMEOUT_CALLBACK
from signbridge.utils.logging_setup import get_logger

logger = get_logger("network.callbacks")


class CallbackError(Exception):
    """Raised when a callback POST fails."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _now_iso() -> str:
    """Current UTC timestamp in ISO 8601 format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def send_progress(
    url: str,
    object_id: str,
    request_id: str,
    status: str,
    percent_complete: int,
    message: str,
    metadata: dict[str, Any],
    headers: dict[str, str] | None = None,
) -> None:
    """
    POST a progress callback (Standard §8.5 — Progress).

    Raises CallbackError if the endpoint returns non-2xx.
    Per Standard §8.6: if progress returns non-2xx, the native host
    cancels signing for that object.
    """
    payload = {
        "objectId": object_id,
        "requestId": request_id,
        "status": status,
        "percentComplete": percent_complete,
        "message": message,
        "metadata": metadata,
    }

    logger.debug("→ Progress callback: %s %d%% — %s", object_id, percent_complete, message)

    try:
        resp = requests.post(
            url,
            json=payload,
            headers={"Content-Type": "application/json", **(headers or {})},
            timeout=HTTP_TIMEOUT_CALLBACK,
        )
        if resp.status_code < 200 or resp.status_code >= 300:
            raise CallbackError(
                "PROGRESS_ENDPOINT_FAILED",
                f"Progress endpoint returned HTTP {resp.status_code}: {resp.text[:200]}",
            )
    except CallbackError:
        raise
    except Exception as exc:
        raise CallbackError("PROGRESS_ENDPOINT_FAILED", f"Progress callback failed: {exc}")


def send_success(
    url: str,
    object_id: str,
    request_id: str,
    upload_status_code: int,
    upload_response_body: str,
    metadata: dict[str, Any],
    headers: dict[str, str] | None = None,
) -> str:
    """
    POST a success callback (Standard §8.5 — Success).

    Returns the ISO timestamp of the callback.
    """
    timestamp = _now_iso()
    payload = {
        "objectId": object_id,
        "requestId": request_id,
        "status": "completed",
        "uploadResult": {
            "statusCode": upload_status_code,
            "responseBody": upload_response_body,
        },
        "timestamp": timestamp,
        "metadata": metadata,
    }

    logger.info("→ Success callback: %s", object_id)

    try:
        resp = requests.post(
            url,
            json=payload,
            headers={"Content-Type": "application/json", **(headers or {})},
            timeout=HTTP_TIMEOUT_CALLBACK,
        )
        if resp.status_code < 200 or resp.status_code >= 300:
            logger.warning(
                "Success callback returned HTTP %d (non-fatal): %s",
                resp.status_code,
                resp.text[:200],
            )
    except Exception as exc:
        logger.warning("Success callback failed (non-fatal): %s", exc)

    return timestamp


def send_error(
    url: str,
    object_id: str,
    request_id: str,
    error_code: str,
    error_message: str,
    metadata: dict[str, Any],
    headers: dict[str, str] | None = None,
) -> str:
    """
    POST an error callback (Standard §8.5 — Error).

    Returns the ISO timestamp of the callback.
    """
    timestamp = _now_iso()
    payload = {
        "objectId": object_id,
        "requestId": request_id,
        "status": "failed",
        "error": {
            "code": error_code,
            "message": error_message,
        },
        "timestamp": timestamp,
        "metadata": metadata,
    }

    logger.info("→ Error callback: %s — %s: %s", object_id, error_code, error_message)

    try:
        resp = requests.post(
            url,
            json=payload,
            headers={"Content-Type": "application/json", **(headers or {})},
            timeout=HTTP_TIMEOUT_CALLBACK,
        )
        if resp.status_code < 200 or resp.status_code >= 300:
            logger.warning(
                "Error callback returned HTTP %d (non-fatal): %s",
                resp.status_code,
                resp.text[:200],
            )
    except Exception as exc:
        logger.warning("Error callback failed (non-fatal): %s", exc)

    return timestamp
