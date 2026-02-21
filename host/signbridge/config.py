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

# ── PKCS#11 vendor libraries per platform ──────────────────────────────────
# Each entry maps a platform to a list of (name, library_filename) tuples.
# SignBridge will attempt to load ALL available libraries and merge their slots.
PKCS11_LIBS = {
    "Windows": [
        ("SafeNet eToken", "eTPKCS11.dll"),
        ("IDEMIA RO eID",  "idplug-pkcs11.dll"),
    ],
    "Linux": [
        ("SafeNet eToken", "libeTPkcs11.so"),
        ("IDEMIA RO eID",  "libidplug-pkcs11.so"),
    ],
    "Darwin": [
        ("SafeNet eToken", "libeToken.dylib"),
        ("IDEMIA RO eID",  "libidplug-pkcs11.dylib"),
    ],
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


# ── System-known paths for each library ─────────────────────────────────────
_SYSTEM_PATHS: dict[str, dict[str, list[str]]] = {
    "Windows": {
        "eTPKCS11.dll": [
            r"C:\Windows\System32\eTPKCS11.dll",
            r"C:\Program Files\SafeNet\Authentication\SAC\x64\eTPKCS11.dll",
            r"C:\Program Files (x86)\SafeNet\Authentication\SAC\x32\eTPKCS11.dll",
        ],
        "idplug-pkcs11.dll": [
            r"C:\Program Files\IDEMIA\IDPlugClassic\DLLs\idplug-pkcs11.dll",
            r"C:\Program Files (x86)\IDEMIA\IDPlugClassic\DLLs\idplug-pkcs11.dll",
        ],
    },
    "Linux": {
        "libeTPkcs11.so": [
            "/usr/lib/libeTPkcs11.so",
            "/usr/local/lib/libeTPkcs11.so",
            "/usr/lib/x86_64-linux-gnu/libeTPkcs11.so",
        ],
        "libidplug-pkcs11.so": [
            "/usr/lib/idplugclassic/libidplug-pkcs11.so",
            "/usr/lib/libidplug-pkcs11.so",
            "/usr/local/lib/libidplug-pkcs11.so",
        ],
    },
    "Darwin": {
        "libeToken.dylib": [
            "/usr/local/lib/libeToken.dylib",
            "/Library/Frameworks/eToken.framework/Versions/Current/libeToken.dylib",
            "/Library/Frameworks/eToken.framework/Versions/A/libeToken.dylib",
        ],
        "libidplug-pkcs11.dylib": [
            "/Library/Application Support/com.idemia.idplug/lib/libidplug-pkcs11.dylib",
            "/usr/local/lib/libidplug-pkcs11.dylib",
        ],
    },
}


def _find_library(lib_filename: str) -> Optional[Path]:
    """Locate a single PKCS#11 library file across known paths."""
    system = platform.system()

    # 1. System-known paths
    candidates = _SYSTEM_PATHS.get(system, {}).get(lib_filename, [])
    for candidate in candidates:
        p = Path(candidate)
        if p.exists():
            return p

    # 2. PyInstaller bundle
    if is_frozen():
        bundled = Path(sys._MEIPASS) / lib_filename  # type: ignore[attr-defined]
        if bundled.exists():
            return bundled

    # 3. libs/ directory (development)
    libs_dir = Path(__file__).resolve().parent.parent / "libs"
    dev_path = libs_dir / lib_filename
    if dev_path.exists():
        return dev_path

    return None


def get_pkcs11_library_paths() -> list[tuple[str, Path]]:
    """
    Locate ALL available PKCS#11 vendor libraries for the current platform.

    Returns a list of ``(vendor_name, path)`` tuples for every library that
    was found.  SignBridge will attempt to load each and merge their slots.
    """
    system = platform.system()
    libs = PKCS11_LIBS.get(system, [])
    found: list[tuple[str, Path]] = []
    for vendor_name, lib_filename in libs:
        path = _find_library(lib_filename)
        if path is not None:
            found.append((vendor_name, path))
    return found


def get_pkcs11_library_path() -> Optional[Path]:
    """
    Locate the first available PKCS#11 vendor library (legacy helper).
    """
    paths = get_pkcs11_library_paths()
    if paths:
        return paths[0][1]
    return None
