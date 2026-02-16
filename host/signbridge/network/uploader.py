"""
Signed content uploader — POSTs raw bytes to uploadUrl endpoints.

Standard §8.3: The native host sends a raw bytes POST to the constructed URL.
Content-Type is determined by signedContentType.
"""

from __future__ import annotations

from typing import Any

import requests

from signbridge.config import HTTP_TIMEOUT_UPLOAD, SIGNED_CONTENT_TYPE_MAP
from signbridge.utils.logging_setup import get_logger

logger = get_logger("network.uploader")


class UploadError(Exception):
    """Raised when an upload fails."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class UploadResult:
    """Captures the HTTP response from the upload endpoint (Standard §8.5)."""

    __slots__ = ("status_code", "response_body")

    def __init__(self, status_code: int, response_body: str) -> None:
        self.status_code = status_code
        self.response_body = response_body


def upload_signed_content(
    url: str,
    data: bytes,
    signed_content_type: str,
    method: str = "POST",
    headers: dict[str, str] | None = None,
    timeout: int = HTTP_TIMEOUT_UPLOAD,
) -> UploadResult:
    """
    Upload signed content as raw bytes to the upload endpoint.

    Parameters
    ----------
    url : str
        The upload URL (with <objectId> already substituted).
    data : bytes
        The raw signed content.
    signed_content_type : str
        One of: string, pdf, xml, binary → determines Content-Type header.
    method : str
        HTTP method (default POST).
    headers : dict | None
        Authentication / custom headers.
    timeout : int
        Request timeout in seconds.

    Returns
    -------
    UploadResult
        Contains HTTP status code and response body from the endpoint.

    Raises
    ------
    UploadError
        On any failure.
    """
    content_type = SIGNED_CONTENT_TYPE_MAP.get(signed_content_type, "application/octet-stream")

    # Merge caller headers with Content-Type
    req_headers = dict(headers or {})
    req_headers["Content-Type"] = content_type

    logger.info(
        "Uploading signed content: %s %s (%d bytes, %s)",
        method,
        _redact_url(url),
        len(data),
        content_type,
    )

    try:
        resp = requests.request(
            method=method.upper(),
            url=url,
            headers=req_headers,
            data=data,
            timeout=timeout,
        )

        result = UploadResult(
            status_code=resp.status_code,
            response_body=resp.text[:4096],  # cap response body size
        )

        if resp.status_code < 200 or resp.status_code >= 300:
            raise UploadError(
                "UPLOAD_FAILED",
                f"Upload returned HTTP {resp.status_code}: {resp.text[:200]}",
            )

        logger.info("Upload complete: HTTP %d", resp.status_code)
        return result

    except UploadError:
        raise
    except requests.Timeout:
        raise UploadError("TIMEOUT", f"Upload timed out after {timeout}s: {_redact_url(url)}")
    except requests.ConnectionError as exc:
        raise UploadError("UPLOAD_FAILED", f"Connection error: {exc}")
    except Exception as exc:
        raise UploadError("UPLOAD_FAILED", f"Upload failed: {exc}")


def substitute_object_id(url_template: str, object_id: str) -> str:
    """
    Replace the <objectId> placeholder in a URL template.

    Standard §7.2.2 / §8.1: The native host replaces <objectId> with
    each object's id value.
    """
    return url_template.replace("<objectId>", object_id)


def _redact_url(url: str) -> str:
    if "?" in url:
        return url.split("?")[0] + "?..."
    return url
