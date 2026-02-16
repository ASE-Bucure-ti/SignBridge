"""
SignBridge native host — entry point.

Usage:
  python -m signbridge          # normal launch (GUI)
  python -m signbridge --version
"""

import sys

from signbridge.utils.logging_setup import setup_logging
from signbridge.config import APP_NAME, APP_VERSION


def main() -> None:
    logger = setup_logging()
    logger.info("Starting %s v%s", APP_NAME, APP_VERSION)
    logger.info("Python %s on %s", sys.version, sys.platform)

    # Simple CLI args
    if "--version" in sys.argv:
        print(f"{APP_NAME} v{APP_VERSION}")
        sys.exit(0)

    # Launch GUI
    try:
        from signbridge.gui.app import run_gui
        run_gui()
    except Exception as exc:
        logger.critical("Application crashed: %s", exc, exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
