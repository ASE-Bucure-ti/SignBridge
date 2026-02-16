"""
Native Messaging I/O — reads/writes Chrome Native Messaging protocol.

Wire format: 4-byte little-endian length prefix followed by UTF-8 JSON.
IMPORTANT: stdout is reserved exclusively for native messaging.
           All debug output MUST go to stderr or file logs.
"""

import json
import struct
import sys
from typing import Any

from signbridge.utils.logging_setup import get_logger

logger = get_logger("messaging.native_io")

# Chrome enforces a 1 MB limit on native messaging payloads.
MAX_MESSAGE_SIZE = 1024 * 1024


def read_message() -> dict[str, Any] | None:
    """
    Read a single native-messaging frame from stdin.

    Returns the decoded JSON dict, or None on EOF / error.
    """
    try:
        # Read the 4-byte length prefix
        raw_length = sys.stdin.buffer.read(4)
        if len(raw_length) < 4:
            logger.info("stdin closed (read %d bytes of length prefix)", len(raw_length))
            return None

        msg_length = struct.unpack("<I", raw_length)[0]

        if msg_length == 0:
            logger.warning("Received zero-length message")
            return None

        if msg_length > MAX_MESSAGE_SIZE:
            logger.error("Message too large: %d bytes (max %d)", msg_length, MAX_MESSAGE_SIZE)
            return None

        # Read exactly msg_length bytes
        raw_body = sys.stdin.buffer.read(msg_length)
        if len(raw_body) < msg_length:
            logger.error(
                "Truncated message: expected %d bytes, got %d",
                msg_length,
                len(raw_body),
            )
            return None

        message = json.loads(raw_body.decode("utf-8"))
        logger.debug("← Received message (%d bytes): requestId=%s", msg_length, message.get("requestId", "?"))
        return message

    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON in native message: %s", exc)
        return None
    except Exception as exc:
        logger.error("Failed to read native message: %s", exc, exc_info=True)
        return None


def write_message(message: dict[str, Any]) -> bool:
    """
    Write a single native-messaging frame to stdout.

    Returns True on success, False on error.
    """
    try:
        encoded = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

        if len(encoded) > MAX_MESSAGE_SIZE:
            logger.error(
                "Outgoing message too large: %d bytes (max %d)",
                len(encoded),
                MAX_MESSAGE_SIZE,
            )
            return False

        sys.stdout.buffer.write(struct.pack("<I", len(encoded)))
        sys.stdout.buffer.write(encoded)
        sys.stdout.buffer.flush()

        logger.debug("→ Sent message (%d bytes): status=%s", len(encoded), message.get("status", "?"))
        return True

    except Exception as exc:
        logger.error("Failed to write native message: %s", exc, exc_info=True)
        return False
