"""
Content downloader — fetches raw bytes from downloadUrl endpoints.

Standard §5.4: The downloadUrl endpoint MUST return raw bytes directly
(not wrapped in JSON) with the appropriate Content-Type header.
"""

from __future__ import annotations

import requests

from signbridge.config import HTTP_TIMEOUT_DOWNLOAD
from signbridge.utils.logging_setup import get_logger

logger = get_logger("network.downloader")


class DownloadError(Exception):
    """Raised when a content download fails."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def download_content(
    url: str,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    timeout: int = HTTP_TIMEOUT_DOWNLOAD,
) -> bytes:
    """
    Download raw content from a URL.

    Parameters
    ----------
    url : str
        The download URL (must be HTTPS in production).
    method : str
        HTTP method (default GET).
    headers : dict | None
        Authentication / custom headers.
    timeout : int
        Request timeout in seconds.

    Returns
    -------
    bytes
        The raw response body.

    Raises
    ------
    DownloadError
        On any failure (network, HTTP status, timeout).
    """
    logger.info("Downloading content: %s %s", method, _redact_url(url))

    try:
        resp = requests.request(
            method=method.upper(),
            url=url,
            headers=headers or {},
            timeout=timeout,
            stream=False,
        )

        if resp.status_code < 200 or resp.status_code >= 300:
            raise DownloadError(
                "DOWNLOAD_FAILED",
                f"HTTP {resp.status_code} from downloadUrl: {resp.text[:200]}",
            )

        content_length = len(resp.content)
        content_type = resp.headers.get("Content-Type", "unknown")
        logger.info(
            "Download complete: %d bytes, Content-Type=%s",
            content_length,
            content_type,
        )
        return resp.content

    except DownloadError:
        raise
    except requests.Timeout:
        raise DownloadError("TIMEOUT", f"Download timed out after {timeout}s: {_redact_url(url)}")
    except requests.ConnectionError as exc:
        raise DownloadError("DOWNLOAD_FAILED", f"Connection error: {exc}")
    except Exception as exc:
        raise DownloadError("DOWNLOAD_FAILED", f"Download failed: {exc}")


def _redact_url(url: str) -> str:
    """Redact query parameters for safe logging (may contain tokens)."""
    if "?" in url:
        return url.split("?")[0] + "?..."
    return url
