"""
PKCS#11 library + token/session manager.

Handles loading one **or more** vendor PKCS#11 shared libraries, enumerating
available tokens across all of them, and opening authenticated sessions.
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional

import pkcs11
from pkcs11 import lib as pkcs11_lib_mod  # noqa: F401 – needed for type hints

from signbridge.config import get_pkcs11_library_paths
from signbridge.utils.logging_setup import get_logger

logger = get_logger("crypto.pkcs11_manager")


class PKCS11Manager:
    """
    High-level wrapper around the python-pkcs11 library.

    Supports loading **multiple** PKCS#11 vendor libraries simultaneously
    (e.g. SafeNet eToken + IDEMIA RO eID) and aggregating their slots.

    Lifecycle:
        mgr = PKCS11Manager()
        mgr.load()                    # auto-detects & loads all available libs
        slots = mgr.get_token_slots() # enumerate tokens from ALL libs
        session = mgr.open_session(slot, pin)
        ...
        session.close()
    """

    def __init__(self) -> None:
        # list of (vendor_name, pkcs11_lib, lib_path_str) for each loaded lib
        self._libs: list[tuple[str, pkcs11.lib, str]] = []  # type: ignore[type-arg]

        # Legacy single-lib fields (kept for backward-compat helpers)
        self._lib: Optional[pkcs11.lib] = None  # type: ignore[type-arg]
        self._lib_path: Optional[str] = None

    # ── Loading ─────────────────────────────────────────────────────────

    def load(self, lib_path: str | None = None) -> None:
        """
        Load PKCS#11 shared library/libraries.

        Parameters
        ----------
        lib_path : str | None
            Explicit single-library path.  When None (default), all vendor
            libraries found on the system are loaded.
        """
        if lib_path is not None:
            self._load_single("Custom", lib_path)
            return

        detected = get_pkcs11_library_paths()
        if not detected:
            raise FileNotFoundError(
                "No PKCS#11 library found. "
                "Place a vendor library in host/libs/ or install the HSM middleware."
            )

        for vendor_name, path in detected:
            try:
                self._load_single(vendor_name, str(path))
            except Exception as exc:
                # One library failing shouldn't prevent the others from loading.
                logger.warning(
                    "Could not load PKCS#11 library %s (%s): %s",
                    vendor_name,
                    path,
                    exc,
                )

        if not self._libs:
            raise FileNotFoundError(
                "PKCS#11 libraries were detected but none could be loaded."
            )

    def _load_single(self, vendor_name: str, lib_path: str) -> None:
        """Load one PKCS#11 library and register it."""
        logger.info("Loading PKCS#11 library [%s]: %s", vendor_name, lib_path)
        loaded = pkcs11.lib(lib_path)
        self._libs.append((vendor_name, loaded, lib_path))

        # Keep ._lib pointing to the first successfully loaded library
        # so that legacy code using `is_loaded` / `_ensure_loaded` still works.
        if self._lib is None:
            self._lib = loaded
            self._lib_path = lib_path

        logger.info("PKCS#11 library [%s] loaded successfully", vendor_name)

    @property
    def is_loaded(self) -> bool:
        return len(self._libs) > 0

    # ── Token enumeration ───────────────────────────────────────────────

    def get_token_slots(self) -> list[pkcs11.Slot]:
        """
        Return all slots (with token present) from **every** loaded library.

        Slots from different vendor libraries are merged into a single list.
        Non-accessible slots (e.g. QSCD with restricted PIN) are skipped
        with a warning rather than raising an error.
        """
        self._ensure_loaded()
        all_slots: list[pkcs11.Slot] = []

        for vendor_name, lib, lib_path in self._libs:
            try:
                slots = lib.get_slots(token_present=True)
                logger.info(
                    "[%s] Found %d slot(s) with tokens",
                    vendor_name,
                    len(slots),
                )
                for slot in slots:
                    try:
                        token = slot.get_token()
                        logger.debug(
                            "  [%s] Slot %s: label=%r, manufacturer=%r, model=%r",
                            vendor_name,
                            slot.slot_id,
                            token.label,
                            token.manufacturer_id,
                            token.model,
                        )
                        all_slots.append(slot)
                    except Exception as exc:
                        logger.warning(
                            "  [%s] Slot %s: skipped (cannot read token: %s)",
                            vendor_name,
                            slot.slot_id,
                            exc,
                        )
            except Exception as exc:
                logger.warning(
                    "[%s] Failed to enumerate slots: %s",
                    vendor_name,
                    exc,
                )

        logger.info("Total token slots across all libraries: %d", len(all_slots))
        return all_slots

    def get_all_slots(self) -> list[pkcs11.Slot]:
        """Return all slots (including empty) from every loaded library."""
        self._ensure_loaded()
        all_slots: list[pkcs11.Slot] = []
        for _, lib, _ in self._libs:
            all_slots.extend(lib.get_slots())
        return all_slots

    # ── Session management ──────────────────────────────────────────────

    def open_session(self, slot: pkcs11.Slot, pin: str) -> pkcs11.Session:
        """
        Open an authenticated (user) session on the given slot.

        Parameters
        ----------
        slot : pkcs11.Slot
            A slot obtained from get_token_slots().
        pin : str
            The token user PIN.
        """
        self._ensure_loaded()
        token = slot.get_token()
        logger.info("Opening session on token: %s", token.label.strip())
        session = token.open(user_pin=pin)
        logger.info("Session opened successfully")
        return session

    # ── Internal ────────────────────────────────────────────────────────

    def _ensure_loaded(self) -> None:
        if not self._libs:
            raise RuntimeError(
                "No PKCS#11 library loaded. Call load() first."
            )
