"""
Response builder — constructs Standard §10 compliant SignResponse JSON.
"""

from __future__ import annotations

import time
from typing import Any

from signbridge.config import PROTOCOL_VERSION
from signbridge.utils.logging_setup import get_logger

logger = get_logger("messaging.response_builder")


# ─── Per-object result / error accumulators ─────────────────────────────────

class ObjectResult:
    """Successful result for a single object (Standard §10.4)."""

    __slots__ = ("id", "upload_status_code", "upload_response_body", "callback_endpoint", "callback_timestamp")

    def __init__(
        self,
        obj_id: str,
        upload_status_code: int,
        upload_response_body: str,
        callback_endpoint: str,
        callback_timestamp: str,
    ) -> None:
        self.id = obj_id
        self.upload_status_code = upload_status_code
        self.upload_response_body = upload_response_body
        self.callback_endpoint = callback_endpoint
        self.callback_timestamp = callback_timestamp

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "status": "ok",
            "uploadResult": {
                "statusCode": self.upload_status_code,
                "responseBody": self.upload_response_body,
            },
            "callbackResult": {
                "status": "sent",
                "endpoint": self.callback_endpoint,
                "timestamp": self.callback_timestamp,
            },
        }


class ObjectError:
    """Error for a single object (Standard §10.5)."""

    __slots__ = ("id", "code", "message")

    def __init__(self, obj_id: str | None, code: str, message: str) -> None:
        self.id = obj_id
        self.code = code
        self.message = message

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "code": self.code,
            "message": self.message,
        }
        if self.id is not None:
            d["id"] = self.id
        return d


# ─── Response builder ───────────────────────────────────────────────────────

class ResponseBuilder:
    """
    Accumulates per-object results and errors, then serialises
    a Standard §10 compliant response dict.
    """

    def __init__(self, request_id: str, metadata: dict[str, Any]) -> None:
        self.request_id = request_id
        self.metadata = metadata
        self.results: list[ObjectResult] = []
        self.errors: list[ObjectError] = []
        self._start_ms = time.monotonic()

    # ── Accumulation ────────────────────────────────────────────────────

    def add_result(self, result: ObjectResult) -> None:
        self.results.append(result)

    def add_error(self, error: ObjectError) -> None:
        self.errors.append(error)

    # ── Finalisation ────────────────────────────────────────────────────

    def build(self) -> dict[str, Any]:
        """Build the final response dict (Standard §10.1)."""
        elapsed_ms = int((time.monotonic() - self._start_ms) * 1000)

        # Determine overall status (Standard §10.3)
        if len(self.errors) == 0:
            status = "ok"
        elif len(self.results) == 0:
            status = "error"
        else:
            status = "partial"

        resp: dict[str, Any] = {
            "protocolVersion": PROTOCOL_VERSION,
            "requestId": self.request_id,
            "status": status,
            "results": [r.to_dict() for r in self.results],
            "metadata": self.metadata,
            "metrics": {"totalMs": elapsed_ms},
        }

        if self.errors:
            resp["errors"] = [e.to_dict() for e in self.errors]

        logger.info(
            "Response built: status=%s, results=%d, errors=%d, elapsed=%dms",
            status,
            len(self.results),
            len(self.errors),
            elapsed_ms,
        )
        return resp


def build_request_error(
    request_id: str | None,
    code: str,
    message: str,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Build a request-level error response (Standard §13.3).

    Used when the entire request is invalid (e.g., bad schema, unsupported version).
    """
    resp: dict[str, Any] = {
        "protocolVersion": PROTOCOL_VERSION,
        "requestId": request_id or "unknown",
        "status": "error",
        "results": [],
        "errors": [{"code": code, "message": message}],
        "metadata": metadata or {},
    }
    logger.warning("Request-level error: code=%s, message=%s", code, message)
    return resp
