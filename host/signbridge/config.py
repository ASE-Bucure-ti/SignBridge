"""
SignBridge configuration — paths, constants, and platform detection.
"""

import os
import sys
import platform
from pathlib import Path
from typing import Optional

# ─── App identity ───────────────────────────────────────────────────────────
APP_NAME = "SignBridge"
APP_VERSION = "1.0.0"
HOST_NAME = "com.ase.signer"
PROTOCOL_VERSION = "1.0"

# ─── Supported data types (Standard §4) ────────────────────────────────────
SUPPORTED_DATA_TYPES = {"text", "xml", "json", "pdf", "binary"}
INLINE_ALLOWED_TYPES = {"text", "xml", "json"}
REMOTE_ONLY_TYPES = {"pdf", "binary"}

# ─── Maximum payload size for inline content (1 MB, Standard §4.1) ─────────
MAX_INLINE_SIZE_BYTES = 1 * 1024 * 1024

# ─── PKCS#11 vendor library filenames per platform ─────────────────────────
PKCS11_LIB_MAP = {
    "Windows": "eTPKCS11.dll",
    "Linux": "libeTPkcs11.so",
    "Darwin": "libeToken.dylib",
}

# ─── Content-Type mapping (Standard §8.3) ──────────────────────────────────
SIGNED_CONTENT_TYPE_MAP = {
    "string": "text/plain",
    "pdf": "application/pdf",
    "xml": "application/xml",
    "binary": "application/octet-stream",
}

# ─── Network defaults ──────────────────────────────────────────────────────
HTTP_TIMEOUT_DOWNLOAD = 60   # seconds
HTTP_TIMEOUT_UPLOAD = 120    # seconds
HTTP_TIMEOUT_CALLBACK = 30   # seconds

# ─── Logging ────────────────────────────────────────────────────────────────
LOG_DIR = Path.home() / ".signbridge" / "logs"
LOG_FILE = LOG_DIR / "signbridge.log"
LOG_MAX_BYTES = 5 * 1024 * 1024  # 5 MB
LOG_BACKUP_COUNT = 3


def is_frozen() -> bool:
    """Return True if running inside a PyInstaller bundle."""
    return getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS")


def resource_path(relative_path: str) -> Path:
    """
    Get the absolute path to a bundled resource.
    Works both in development and when frozen by PyInstaller.
    """
    if is_frozen():
        base = Path(sys._MEIPASS)  # type: ignore[attr-defined]
    else:
        # In dev, resources are relative to the host/ directory
        base = Path(__file__).resolve().parent.parent
    return base / relative_path


def get_pkcs11_library_path() -> Optional[Path]:
    """
    Locate the PKCS#11 vendor library for the current platform.

    Search order:
      1. Bundled inside PyInstaller package (_MEIPASS)
      2. libs/ directory next to the signbridge package
      3. Common system paths
    """
    system = platform.system()
    lib_name = PKCS11_LIB_MAP.get(system)
    if lib_name is None:
        return None

    # 1. PyInstaller bundle
    if is_frozen():
        bundled = Path(sys._MEIPASS) / lib_name  # type: ignore[attr-defined]
        if bundled.exists():
            return bundled

    # 2. libs/ directory (development layout)
    libs_dir = Path(__file__).resolve().parent.parent / "libs"
    dev_path = libs_dir / lib_name
    if dev_path.exists():
        return dev_path

    # 3. Platform-specific system paths
    system_candidates: list[str] = []
    if system == "Windows":
        system_candidates = [
            r"C:\Windows\System32\eTPKCS11.dll",
            r"C:\Program Files\SafeNet\Authentication\SAC\x64\eTPKCS11.dll",
            r"C:\Program Files (x86)\SafeNet\Authentication\SAC\x32\eTPKCS11.dll",
        ]
    elif system == "Linux":
        system_candidates = [
            "/usr/lib/libeTPkcs11.so",
            "/usr/local/lib/libeTPkcs11.so",
            "/usr/lib/x86_64-linux-gnu/libeTPkcs11.so",
        ]
    elif system == "Darwin":
        system_candidates = [
            "/usr/local/lib/libeToken.dylib",
            "/Library/Frameworks/eToken.framework/Versions/Current/libeToken.dylib",
        ]

    for candidate in system_candidates:
        p = Path(candidate)
        if p.exists():
            return p

    return None
