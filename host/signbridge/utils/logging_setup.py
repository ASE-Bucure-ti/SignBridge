"""
Logging configuration for SignBridge.

Writes to both a rotating file log and stderr (never stdout, which is
reserved for native messaging).
"""

import logging
import sys
from logging.handlers import RotatingFileHandler

from signbridge.config import LOG_DIR, LOG_FILE, LOG_MAX_BYTES, LOG_BACKUP_COUNT, APP_NAME

_initialised = False


def setup_logging(level: int = logging.DEBUG) -> logging.Logger:
    """
    Initialise application-wide logging.

    Returns the root 'signbridge' logger.
    """
    global _initialised
    if _initialised:
        return logging.getLogger(APP_NAME)

    LOG_DIR.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger(APP_NAME)
    logger.setLevel(level)

    fmt = logging.Formatter(
        "[%(asctime)s] %(levelname)-8s %(name)s.%(funcName)s:%(lineno)d — %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # ── Rotating file handler ───────────────────────────────────────────
    fh = RotatingFileHandler(
        str(LOG_FILE),
        maxBytes=LOG_MAX_BYTES,
        backupCount=LOG_BACKUP_COUNT,
        encoding="utf-8",
    )
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    # ── Stderr handler (never stdout — that's native messaging) ─────────
    sh = logging.StreamHandler(sys.stderr)
    sh.setLevel(logging.WARNING)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    _initialised = True
    return logger


def get_logger(name: str) -> logging.Logger:
    """Return a child logger under the signbridge namespace."""
    return logging.getLogger(f"{APP_NAME}.{name}")
