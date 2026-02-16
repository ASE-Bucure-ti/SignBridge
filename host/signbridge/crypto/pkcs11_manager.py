"""
PKCS#11 library + token/session manager.

Handles loading the vendor PKCS#11 shared library, enumerating available
tokens, and opening authenticated sessions.
"""

from __future__ import annotations

from typing import Optional

import pkcs11
from pkcs11 import lib as pkcs11_lib_mod  # noqa: F401 – needed for type hints

from signbridge.config import get_pkcs11_library_path
from signbridge.utils.logging_setup import get_logger

logger = get_logger("crypto.pkcs11_manager")


class PKCS11Manager:
    """
    High-level wrapper around the python-pkcs11 library.

    Lifecycle:
        mgr = PKCS11Manager()
        mgr.load()                    # loads the .dll/.so/.dylib
        slots = mgr.get_token_slots() # enumerate tokens
        session = mgr.open_session(slot, pin)
        ...
        session.close()
    """

    def __init__(self) -> None:
        self._lib: Optional[pkcs11.lib] = None  # type: ignore[type-arg]
        self._lib_path: Optional[str] = None

    # ── Loading ─────────────────────────────────────────────────────────

    def load(self, lib_path: str | None = None) -> None:
        """
        Load the PKCS#11 shared library.

        Parameters
        ----------
        lib_path : str | None
            Explicit path. If None, auto-detects for the current platform.
        """
        if lib_path is None:
            detected = get_pkcs11_library_path()
            if detected is None:
                raise FileNotFoundError(
                    "PKCS#11 library not found. "
                    "Place the vendor library in host/libs/ or install the HSM middleware."
                )
            lib_path = str(detected)

        logger.info("Loading PKCS#11 library: %s", lib_path)
        self._lib = pkcs11.lib(lib_path)
        self._lib_path = lib_path
        logger.info("PKCS#11 library loaded successfully")

    @property
    def is_loaded(self) -> bool:
        return self._lib is not None

    # ── Token enumeration ───────────────────────────────────────────────

    def get_token_slots(self) -> list[pkcs11.Slot]:
        """Return all slots that have a token present."""
        self._ensure_loaded()
        assert self._lib is not None
        slots = self._lib.get_slots(token_present=True)
        logger.info("Found %d slot(s) with tokens", len(slots))
        for slot in slots:
            token = slot.get_token()
            logger.debug(
                "  Slot %s: label=%r, manufacturer=%r, model=%r",
                slot.slot_id,
                token.label,
                token.manufacturer_id,
                token.model,
            )
        return list(slots)

    def get_all_slots(self) -> list[pkcs11.Slot]:
        """Return all slots, including empty ones."""
        self._ensure_loaded()
        assert self._lib is not None
        return list(self._lib.get_slots())

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
        if self._lib is None:
            raise RuntimeError("PKCS#11 library not loaded. Call load() first.")
