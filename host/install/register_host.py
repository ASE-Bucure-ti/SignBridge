#!/usr/bin/env python3
"""
SignBridge — Cross-platform browser native messaging host registration.

Detects installed browsers and registers the native messaging host manifest
so Chrome/Edge/Firefox can launch SignBridge via connectNative('com.ase.signer').

Usage:
  python register_host.py                   # auto-detect browsers
  python register_host.py --exe /path/to/SignBridge  # explicit exe path
  python register_host.py --unregister      # remove all registrations

Works on Windows, macOS, and Linux.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import sys
from pathlib import Path

HOST_NAME = "com.ase.signer"
CHROME_EXTENSION_ID = "hjfiglgfjnfceahiccedeimkgabclkpc"
FIREFOX_EXTENSION_ID = "signbridge@ase.ro"

SYSTEM = platform.system()

# ─── Chrome-family manifest ─────────────────────────────────────────────────

def _chrome_manifest(exe_path: str) -> dict:
    return {
        "name": HOST_NAME,
        "description": "SignBridge — Generic Web HSM Signing Native Host",
        "path": exe_path,
        "type": "stdio",
        "allowed_origins": [
            f"chrome-extension://{CHROME_EXTENSION_ID}/",
        ],
    }


def _firefox_manifest(exe_path: str) -> dict:
    return {
        "name": HOST_NAME,
        "description": "SignBridge — Generic Web HSM Signing Native Host",
        "path": exe_path,
        "type": "stdio",
        "allowed_extensions": [
            FIREFOX_EXTENSION_ID,
        ],
    }


# ─── Registration locations by browser and platform ─────────────────────────

def _get_browser_targets() -> list[dict]:
    """
    Return a list of browser targets with their manifest paths and registry keys.

    Each target is a dict with:
      - name: human-readable browser name
      - family: "chrome" or "firefox" (determines manifest format)
      - manifest_dir: directory where the manifest JSON goes (macOS/Linux)
      - registry_key: Windows registry key (Windows only)
    """
    targets = []

    if SYSTEM == "Windows":
        targets = [
            {
                "name": "Chrome",
                "family": "chrome",
                "registry_key": rf"Software\Google\Chrome\NativeMessagingHosts\{HOST_NAME}",
            },
            {
                "name": "Edge",
                "family": "chrome",
                "registry_key": rf"Software\Microsoft\Edge\NativeMessagingHosts\{HOST_NAME}",
            },
            {
                "name": "Brave",
                "family": "chrome",
                "registry_key": rf"Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\{HOST_NAME}",
            },
            {
                "name": "Firefox",
                "family": "firefox",
                "registry_key": rf"Software\Mozilla\NativeMessagingHosts\{HOST_NAME}",
            },
        ]

    elif SYSTEM == "Darwin":
        home = Path.home()
        targets = [
            {
                "name": "Chrome",
                "family": "chrome",
                "manifest_dir": home / "Library" / "Application Support" / "Google" / "Chrome" / "NativeMessagingHosts",
            },
            {
                "name": "Edge",
                "family": "chrome",
                "manifest_dir": home / "Library" / "Application Support" / "Microsoft Edge" / "NativeMessagingHosts",
            },
            {
                "name": "Brave",
                "family": "chrome",
                "manifest_dir": home / "Library" / "Application Support" / "BraveSoftware" / "Brave-Browser" / "NativeMessagingHosts",
            },
            {
                "name": "Firefox",
                "family": "firefox",
                "manifest_dir": home / "Library" / "Application Support" / "Mozilla" / "NativeMessagingHosts",
            },
        ]

    elif SYSTEM == "Linux":
        home = Path.home()
        targets = [
            {
                "name": "Chrome",
                "family": "chrome",
                "manifest_dir": home / ".config" / "google-chrome" / "NativeMessagingHosts",
            },
            {
                "name": "Chromium",
                "family": "chrome",
                "manifest_dir": home / ".config" / "chromium" / "NativeMessagingHosts",
            },
            {
                "name": "Edge",
                "family": "chrome",
                "manifest_dir": home / ".config" / "microsoft-edge" / "NativeMessagingHosts",
            },
            {
                "name": "Brave",
                "family": "chrome",
                "manifest_dir": home / ".config" / "BraveSoftware" / "Brave-Browser" / "NativeMessagingHosts",
            },
            {
                "name": "Firefox",
                "family": "firefox",
                "manifest_dir": home / ".mozilla" / "native-messaging-hosts",
            },
        ]

    return targets


# ─── Windows registry helpers ───────────────────────────────────────────────

def _windows_set_registry(key_path: str, manifest_path: str) -> bool:
    """Write the manifest path to the Windows registry (HKCU)."""
    try:
        import winreg
        key = winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path)
        winreg.SetValueEx(key, "", 0, winreg.REG_SZ, manifest_path)
        winreg.CloseKey(key)
        return True
    except Exception as exc:
        print(f"  ✗ Registry write failed: {exc}")
        return False


def _windows_delete_registry(key_path: str) -> bool:
    """Delete a registry key (HKCU)."""
    try:
        import winreg
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, key_path)
        return True
    except FileNotFoundError:
        return True  # Already gone
    except Exception as exc:
        print(f"  ✗ Registry delete failed: {exc}")
        return False


# ─── Registration ───────────────────────────────────────────────────────────

def register(exe_path: str) -> None:
    """Register the native messaging host for all detected browsers."""
    exe_path = str(Path(exe_path).resolve())

    if not Path(exe_path).exists():
        print(f"WARNING: Executable not found at {exe_path}")
        print("  Registration will proceed, but the browser won't be able to launch it.")
        print()

    targets = _get_browser_targets()
    manifest_dir = _get_manifest_storage_dir()

    print(f"Host name:  {HOST_NAME}")
    print(f"Executable: {exe_path}")
    print(f"Platform:   {SYSTEM}")
    print()

    for target in targets:
        name = target["name"]
        family = target["family"]

        manifest = _chrome_manifest(exe_path) if family == "chrome" else _firefox_manifest(exe_path)
        manifest_json = json.dumps(manifest, indent=2)

        if SYSTEM == "Windows":
            # Write manifest file to a shared location
            manifest_file = manifest_dir / f"{HOST_NAME}.{name.lower()}.json"
            manifest_dir.mkdir(parents=True, exist_ok=True)
            manifest_file.write_text(manifest_json, encoding="utf-8")

            # Write registry entry pointing to the manifest
            reg_key = target["registry_key"]
            if _windows_set_registry(reg_key, str(manifest_file)):
                print(f"  ✓ {name}: registered (registry + {manifest_file.name})")
            else:
                print(f"  ✗ {name}: registration failed")

        else:
            # macOS / Linux: write manifest directly to the browser's expected directory
            target_dir = target["manifest_dir"]
            manifest_file = target_dir / f"{HOST_NAME}.json"

            try:
                target_dir.mkdir(parents=True, exist_ok=True)
                manifest_file.write_text(manifest_json, encoding="utf-8")
                manifest_file.chmod(0o644)
                print(f"  ✓ {name}: {manifest_file}")
            except Exception as exc:
                print(f"  ✗ {name}: {exc}")


def unregister() -> None:
    """Remove all native messaging host registrations."""
    targets = _get_browser_targets()
    manifest_dir = _get_manifest_storage_dir()

    print(f"Unregistering {HOST_NAME}...")
    print()

    for target in targets:
        name = target["name"]

        if SYSTEM == "Windows":
            reg_key = target["registry_key"]
            _windows_delete_registry(reg_key)
            manifest_file = manifest_dir / f"{HOST_NAME}.{name.lower()}.json"
            if manifest_file.exists():
                manifest_file.unlink()
            print(f"  ✓ {name}: unregistered")
        else:
            target_dir = target["manifest_dir"]
            manifest_file = target_dir / f"{HOST_NAME}.json"
            if manifest_file.exists():
                manifest_file.unlink()
                print(f"  ✓ {name}: removed {manifest_file}")
            else:
                print(f"  - {name}: not registered")


def _get_manifest_storage_dir() -> Path:
    """On Windows, return a shared directory for manifest files."""
    if SYSTEM == "Windows":
        app_data = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        return app_data / "SignBridge"
    return Path()  # Not used on non-Windows


# ─── Default executable path detection ──────────────────────────────────────

def _find_default_exe() -> str | None:
    """Try to find the built SignBridge executable."""
    script_dir = Path(__file__).resolve().parent.parent  # host/

    # Built executable
    if SYSTEM == "Windows":
        candidates = [
            script_dir / "dist" / "SignBridge" / "SignBridge.exe",
        ]
    else:
        candidates = [
            script_dir / "dist" / "SignBridge" / "SignBridge",
        ]

    for c in candidates:
        if c.exists():
            return str(c)

    # Development mode: use python -m signbridge
    return None


# ─── CLI ────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Register SignBridge as a native messaging host for browsers."
    )
    parser.add_argument(
        "--exe",
        help="Path to the SignBridge executable. Auto-detected if omitted.",
    )
    parser.add_argument(
        "--unregister",
        action="store_true",
        help="Remove all registrations.",
    )

    args = parser.parse_args()

    if args.unregister:
        unregister()
        return

    exe_path = args.exe
    if exe_path is None:
        exe_path = _find_default_exe()
        if exe_path is None:
            print("ERROR: Could not find SignBridge executable.")
            print("Build first with build_windows.bat / build_linux.sh / build_macos.sh")
            print("Or specify explicitly: python register_host.py --exe /path/to/SignBridge")
            sys.exit(1)

    register(exe_path)
    print()
    print("Registration complete! Restart any open browsers for changes to take effect.")


if __name__ == "__main__":
    main()
