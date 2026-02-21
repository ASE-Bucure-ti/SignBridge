"""
SignBridge PyQt6 GUI — main application window.

Responsibilities:
  • Display available HSM tokens / certificates
  • Accept user PIN
  • Show processing progress and activity log
  • Delegate all protocol logic to the processing engine
  • Communicate with the extension via native messaging (stdin/stdout)
"""

from __future__ import annotations

import sys
import threading
from typing import Any, Optional

from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject
from PyQt6.QtWidgets import (
    QApplication,
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QLabel,
    QComboBox,
    QLineEdit,
    QPushButton,
    QProgressBar,
    QTextEdit,
    QGroupBox,
    QMessageBox,
    QSplitter,
)
from PyQt6.QtGui import QFont, QTextCursor, QIcon

from signbridge.config import APP_NAME, APP_VERSION, resource_path
from signbridge.crypto.pkcs11_manager import PKCS11Manager
from signbridge.crypto.certificate import find_certificates, find_certificate_by_id, find_private_key, CertificateInfo

try:
    import pkcs11.exceptions as pkcs11_exc
except ImportError:
    pkcs11_exc = None  # type: ignore[assignment]
from signbridge.messaging.native_io import read_message, write_message
from signbridge.messaging.request_parser import parse_request, RequestValidationError
from signbridge.messaging.response_builder import build_request_error
from signbridge.processing.engine import process_request
from signbridge.processing.object_resolver import resolve_objects
from signbridge.network.callbacks import send_error as send_error_callback
from signbridge.utils.logging_setup import get_logger

logger = get_logger("gui.app")


# ─── Thread-safe signal bridge ──────────────────────────────────────────────

class _Signals(QObject):
    """Qt signals for cross-thread communication."""
    message_received = pyqtSignal(dict)
    progress_update = pyqtSignal(str, int, str)  # object_id, percent, message
    signing_complete = pyqtSignal(dict)            # response dict
    signing_error = pyqtSignal(str)                # error message
    log_message = pyqtSignal(str)
    tokens_refreshed = pyqtSignal(list)            # list of signing-capable slots


# ─── Main window ────────────────────────────────────────────────────────────

class SignBridgeWindow(QMainWindow):
    """Main application window."""

    def __init__(self) -> None:
        super().__init__()
        self._signals = _Signals()
        self._pkcs11 = PKCS11Manager()

        # State
        self._current_request: dict[str, Any] | None = None
        self._slots: list = []
        self._cancel_requested = False
        self._response_sent = False
        self._signing_in_progress = False
        self._token_refresh_in_progress = False

        self._init_ui()
        self._connect_signals()
        self._init_pkcs11()
        self._start_stdin_listener()
        self._setup_token_refresh()

    # ── UI construction ─────────────────────────────────────────────────

    def _init_ui(self) -> None:
        self.setWindowTitle(f"{APP_NAME} v{APP_VERSION}")
        self.setMinimumSize(700, 520)
        self.resize(760, 600)

        # Window icon
        icon_path = resource_path("logo.png")
        if icon_path.exists():
            self.setWindowIcon(QIcon(str(icon_path)))

        central = QWidget()
        self.setCentralWidget(central)
        root_layout = QVBoxLayout(central)
        root_layout.setContentsMargins(16, 16, 16, 16)
        root_layout.setSpacing(12)

        # ── Header ──────────────────────────────────────────────────────
        header = QLabel(f"{APP_NAME}")
        header.setFont(QFont("Segoe UI", 16, QFont.Weight.Bold))
        header.setAlignment(Qt.AlignmentFlag.AlignCenter)
        root_layout.addWidget(header)

        subtitle = QLabel("Generic Web HSM Signing Protocol — Native Host")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet("color: #666; font-size: 11px;")
        root_layout.addWidget(subtitle)

        # ── Token + PIN group ───────────────────────────────────────────
        token_group = QGroupBox("HSM Token")
        token_layout = QVBoxLayout(token_group)

        # Token selector
        token_row = QHBoxLayout()
        token_row.addWidget(QLabel("Token:"))
        self._token_combo = QComboBox()
        self._token_combo.setMinimumWidth(350)
        self._token_combo.setSizeAdjustPolicy(
            QComboBox.SizeAdjustPolicy.AdjustToContents
        )
        token_row.addWidget(self._token_combo, stretch=1)

        self._refresh_btn = QPushButton("⟳ Refresh")
        self._refresh_btn.setFixedWidth(90)
        self._refresh_btn.clicked.connect(self._refresh_tokens)
        token_row.addWidget(self._refresh_btn)
        token_layout.addLayout(token_row)

        # PIN input
        pin_row = QHBoxLayout()
        pin_row.addWidget(QLabel("PIN:"))
        self._pin_input = QLineEdit()
        self._pin_input.setEchoMode(QLineEdit.EchoMode.Password)
        self._pin_input.setPlaceholderText("Enter token PIN")
        self._pin_input.setMaximumWidth(250)
        pin_row.addWidget(self._pin_input)
        pin_row.addStretch()
        token_layout.addLayout(pin_row)

        root_layout.addWidget(token_group)

        # ── Status / progress ───────────────────────────────────────────
        status_group = QGroupBox("Status")
        status_layout = QVBoxLayout(status_group)

        self._status_label = QLabel("Waiting for signing request from browser…")
        self._status_label.setWordWrap(True)
        self._status_label.setStyleSheet("font-size: 12px; padding: 4px;")
        status_layout.addWidget(self._status_label)

        self._progress_bar = QProgressBar()
        self._progress_bar.setVisible(False)
        self._progress_bar.setTextVisible(True)
        status_layout.addWidget(self._progress_bar)

        self._progress_label = QLabel("")
        self._progress_label.setStyleSheet("color: #555; font-size: 11px;")
        status_layout.addWidget(self._progress_label)

        root_layout.addWidget(status_group)

        # ── Action buttons ──────────────────────────────────────────────
        btn_row = QHBoxLayout()

        self._sign_btn = QPushButton("✍  Sign")
        self._sign_btn.setEnabled(False)
        self._sign_btn.setFixedHeight(38)
        self._sign_btn.setStyleSheet(
            "QPushButton { background-color: #2563eb; color: white; font-weight: bold; "
            "border-radius: 6px; font-size: 13px; } "
            "QPushButton:disabled { background-color: #94a3b8; } "
            "QPushButton:hover:!disabled { background-color: #1d4ed8; }"
        )
        self._sign_btn.clicked.connect(self._on_sign_clicked)
        btn_row.addWidget(self._sign_btn, stretch=1)

        self._cancel_btn = QPushButton("Cancel")
        self._cancel_btn.setEnabled(False)
        self._cancel_btn.setFixedHeight(38)
        self._cancel_btn.clicked.connect(self._on_cancel_clicked)
        btn_row.addWidget(self._cancel_btn)

        root_layout.addLayout(btn_row)

        # ── Activity log ────────────────────────────────────────────────
        log_group = QGroupBox("Activity Log")
        log_layout = QVBoxLayout(log_group)

        self._log_text = QTextEdit()
        self._log_text.setReadOnly(True)
        self._log_text.setFont(QFont("Consolas", 9))
        self._log_text.setStyleSheet("background-color: #1e1e2e; color: #cdd6f4;")
        log_layout.addWidget(self._log_text)

        root_layout.addWidget(log_group, stretch=1)

    # ── Signal wiring ───────────────────────────────────────────────────

    def _connect_signals(self) -> None:
        self._signals.message_received.connect(self._handle_message)
        self._signals.progress_update.connect(self._on_progress)
        self._signals.signing_complete.connect(self._on_signing_complete)
        self._signals.signing_error.connect(self._on_signing_error)
        self._signals.log_message.connect(self._append_log)
        self._signals.tokens_refreshed.connect(self._on_tokens_refreshed)

    # ── PKCS#11 init ────────────────────────────────────────────────────

    def _init_pkcs11(self) -> None:
        try:
            self._pkcs11.load()
            self._log("PKCS#11 library loaded")
            self._refresh_tokens()
        except FileNotFoundError as exc:
            self._log(f"[WARN] {exc}")
            self._status_label.setText("⚠ PKCS#11 library not found — HSM middleware may not be installed")
            self._status_label.setStyleSheet("color: #dc2626; font-size: 12px; padding: 4px;")
        except Exception as exc:
            self._log(f"[ERROR] PKCS#11 init failed: {exc}")

    def _setup_token_refresh(self) -> None:
        """Refresh token list every 5 seconds (enumeration runs off-thread)."""
        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self._refresh_tokens)
        self._refresh_timer.start(5000)

    def _refresh_tokens(self) -> None:
        """Kick off a background token enumeration (non-blocking)."""
        if not self._pkcs11.is_loaded:
            return
        if self._token_refresh_in_progress:
            return  # previous refresh still running — skip this tick
        self._token_refresh_in_progress = True
        t = threading.Thread(
            target=self._token_refresh_worker, daemon=True, name="token-refresh"
        )
        t.start()

    def _token_refresh_worker(self) -> None:
        """Background thread: enumerate PKCS#11 slots (slow I/O)."""
        try:
            all_slots = self._pkcs11.get_token_slots()
            signing_slots = [s for s in all_slots if self._is_signing_slot(s)]
            self._signals.tokens_refreshed.emit(signing_slots)
        except Exception as exc:
            logger.debug("Token refresh error: %s", exc)
        finally:
            self._token_refresh_in_progress = False

    def _on_tokens_refreshed(self, signing_slots: list) -> None:
        """Main-thread handler: update the combo box with freshly enumerated slots."""
        self._slots = signing_slots

        # Remember the currently selected token by a stable key
        # (slot objects change identity across enumerations).
        prev_key = self._selected_token_key()

        self._token_combo.blockSignals(True)
        self._token_combo.clear()

        restored = False
        for idx, slot in enumerate(self._slots):
            token = slot.get_token()
            label = token.label.strip()
            slot_key = (slot.slot_id, label)
            display = f"{label} (slot {slot.slot_id})"
            self._token_combo.addItem(display, slot)

            if not restored and prev_key is not None and slot_key == prev_key:
                self._token_combo.setCurrentIndex(idx)
                restored = True

        self._token_combo.blockSignals(False)
        self._update_ui_state()

    def _selected_token_key(self) -> tuple[int, str] | None:
        """Return a stable (slot_id, label) key for the currently selected token."""
        slot = self._token_combo.currentData()
        if slot is None:
            return None
        try:
            return (slot.slot_id, slot.get_token().label.strip())
        except Exception:
            return None

    @staticmethod
    def _is_signing_slot(slot: Any) -> bool:
        """
        Heuristic filter: return True if the token in *slot* is likely
        a signing-capable token (non-repudiation / advanced signature).

        Known patterns:
          • RO eID "ADVANCED SIGNATURE PIN" → True
          • RO eID "PKI Application (User PIN)" → False (auth-only)
          • SafeNet eToken → True (generic device, all are signing)
          • Everything else → True (default include)
        """
        try:
            label = slot.get_token().label.strip().upper()
        except Exception:
            return False  # can't even read the token → skip

        # Explicit signing indicator keywords
        if any(kw in label for kw in ("SIGNATURE", "SEMNARE", "SIGNING", "SIGN")):
            return True

        # Known auth-only pattern (RO eID authentication slot)
        if "PKI APPLICATION" in label and "SIGNATURE" not in label:
            return False

        # Default: include (SafeNet eToken, generic HSMs, etc.)
        return True

    # ── Stdin listener (background thread) ──────────────────────────────

    def _start_stdin_listener(self) -> None:
        """Start a background thread that listens for native messages on stdin."""
        t = threading.Thread(target=self._stdin_loop, daemon=True, name="stdin-listener")
        t.start()
        self._log("Listening for extension messages…")

    def _stdin_loop(self) -> None:
        """Background thread: read messages from stdin and emit Qt signal."""
        while True:
            msg = read_message()
            if msg is None:
                # stdin closed → extension disconnected
                self._signals.log_message.emit("[INFO] Extension disconnected (stdin closed)")
                break
            self._signals.message_received.emit(msg)

    # ── Message handling (main thread) ──────────────────────────────────

    def _handle_message(self, msg: dict[str, Any]) -> None:
        """Handle a message received from the extension (runs on Qt main thread)."""
        self._log(f"[RECV] Message received: requestId={msg.get('requestId', '?')}")
        self._flash_window()

        # Try to parse
        try:
            request = parse_request(msg)
        except RequestValidationError as exc:
            self._log(f"[ERROR] Validation failed: {exc.code} — {exc.message}")
            error_resp = build_request_error(
                request_id=msg.get("requestId"),
                code=exc.code,
                message=exc.message,
                metadata=msg.get("metadata"),
            )
            write_message(error_resp)
            return

        self._current_request = msg
        self._response_sent = False
        self._status_label.setText(
            f"Signing request received: {request.app_id} — "
            f"{self._count_objects(request)} object(s)"
        )
        self._status_label.setStyleSheet("color: #2563eb; font-size: 12px; padding: 4px;")
        self._update_ui_state()

    def _count_objects(self, request: Any) -> int:
        if request.objects:
            return len(request.objects)
        if request.object_groups:
            return sum(len(g.objects) for g in request.object_groups)
        return 0

    # ── Sign action ─────────────────────────────────────────────────────

    def _on_sign_clicked(self) -> None:
        pin = self._pin_input.text().strip()
        if not pin:
            QMessageBox.warning(self, "PIN Required", "Please enter your HSM token PIN.")
            return

        slot = self._token_combo.currentData()
        if slot is None:
            QMessageBox.warning(self, "No Token", "No HSM token selected.")
            return

        if self._current_request is None:
            QMessageBox.warning(self, "No Request", "No signing request pending.")
            return

        self._sign_btn.setEnabled(False)
        self._signing_in_progress = True
        self._cancel_btn.setEnabled(True)
        self._cancel_requested = False
        self._progress_bar.setVisible(True)
        self._progress_bar.setValue(0)
        self._status_label.setText("Signing in progress…")
        self._status_label.setStyleSheet("color: #2563eb; font-size: 12px; padding: 4px;")

        # Run signing in background thread
        t = threading.Thread(
            target=self._sign_worker,
            args=(self._current_request, pin, slot),
            daemon=True,
            name="sign-worker",
        )
        t.start()

    def _sign_worker(self, raw_request: dict, pin: str, slot: Any) -> None:
        """Background thread: perform the signing workflow."""
        session = None
        try:
            # Parse request
            request = parse_request(raw_request)

            # Open HSM session
            self._signals.log_message.emit("[SIGN] Opening HSM session…")
            session = self._pkcs11.open_session(slot, pin)

            # Find certificate
            self._signals.log_message.emit(f"[SIGN] Looking for certificate: {request.cert.cert_id}")
            cert_info = find_certificate_by_id(session, request.cert.cert_id)
            if cert_info is None:
                msg = f"Certificate not found on token: {request.cert.cert_id}"
                error_resp = build_request_error(
                    request_id=raw_request.get("requestId"),
                    code="CERT_NOT_FOUND",
                    message=msg,
                    metadata=raw_request.get("metadata"),
                )
                self._send_error_callbacks_for_all(raw_request, "CERT_NOT_FOUND", msg)
                self._signals.signing_complete.emit(error_resp)
                return
            self._signals.log_message.emit(f"[SIGN] Certificate found: {cert_info.subject_cn}")

            # Find private key
            priv_key = find_private_key(session, cert_info)
            if priv_key is None:
                msg = "No private key found for the selected certificate"
                error_resp = build_request_error(
                    request_id=raw_request.get("requestId"),
                    code="CERT_NOT_FOUND",
                    message=msg,
                    metadata=raw_request.get("metadata"),
                )
                self._send_error_callbacks_for_all(raw_request, "CERT_NOT_FOUND", msg)
                self._signals.signing_complete.emit(error_resp)
                return
            self._signals.log_message.emit("[SIGN] Private key found")

            # Process all objects
            def progress_fn(obj_id: str, pct: int, msg: str) -> None:
                self._signals.progress_update.emit(obj_id, pct, msg)

            def cancel_check() -> bool:
                return self._cancel_requested

            response = process_request(
                request=request,
                session=session,
                private_key=priv_key,
                cert_info=cert_info,
                progress_fn=progress_fn,
                cancel_check=cancel_check,
            )

            self._signals.signing_complete.emit(response)

        except RequestValidationError as exc:
            error_resp = build_request_error(
                request_id=raw_request.get("requestId"),
                code=exc.code,
                message=exc.message,
                metadata=raw_request.get("metadata"),
            )
            self._signals.signing_complete.emit(error_resp)
        except Exception as exc:
            # Map specific PKCS#11 exceptions to proper Standard error codes
            code = "INTERNAL_ERROR"
            msg = str(exc)
            if pkcs11_exc is not None:
                exc_type = type(exc).__name__
                if isinstance(exc, (pkcs11_exc.PinIncorrect,)):
                    code = "SIGN_FAILED"
                    msg = "Incorrect token PIN"
                elif isinstance(exc, (pkcs11_exc.PinLocked,)):
                    code = "SIGN_FAILED"
                    msg = "Token PIN is locked — contact your administrator"
                elif isinstance(exc, (pkcs11_exc.PinExpired,)):
                    code = "SIGN_FAILED"
                    msg = "Token PIN has expired — please change it"
                elif isinstance(exc, (pkcs11_exc.TokenNotPresent,)):
                    code = "CERT_NOT_FOUND"
                    msg = "HSM token was removed during operation"
                elif isinstance(exc, (pkcs11_exc.DeviceRemoved,)):
                    code = "CERT_NOT_FOUND"
                    msg = "HSM device was removed"
                elif isinstance(exc, (pkcs11_exc.DeviceError,)):
                    code = "SIGN_FAILED"
                    msg = f"HSM device error: {exc}"
                elif isinstance(exc, (pkcs11_exc.PKCS11Error,)):
                    code = "SIGN_FAILED"
                    msg = f"PKCS#11 error: {exc}"

            self._signals.log_message.emit(f"[ERROR] {code}: {msg}")
            error_resp = build_request_error(
                request_id=raw_request.get("requestId"),
                code=code,
                message=msg,
                metadata=raw_request.get("metadata"),
            )
            self._send_error_callbacks_for_all(raw_request, code, msg)
            self._signals.signing_complete.emit(error_resp)
        finally:
            if session is not None:
                try:
                    session.close()
                    self._signals.log_message.emit("[SIGN] HSM session closed")
                except Exception:
                    pass

    # ── Progress / completion handlers (main thread) ────────────────────

    def _on_progress(self, object_id: str, percent: int, message: str) -> None:
        self._progress_bar.setValue(percent)
        self._progress_label.setText(message)
        if object_id:
            self._log(f"  [{percent}%] {message}")

    def _on_signing_complete(self, response: dict) -> None:
        self._response_sent = True
        self._log(f"[DONE] Signing complete: status={response.get('status')}")

        # Log individual errors
        for err in response.get("errors", []):
            obj_id = err.get("id", "request")
            code = err.get("code", "UNKNOWN")
            msg = err.get("message", "")
            self._log(f"[ERROR] [{obj_id}] {code}: {msg}")

        # v1.0.3: No stdout response — results are delivered via callbacks
        self._log("[DONE] Results delivered via callbacks (fire-and-forget)")

        status = response.get("status", "error")
        results_count = len(response.get("results", []))
        errors_count = len(response.get("errors", []))

        if status == "ok":
            self._status_label.setText(f"✓ Signing completed — {results_count} object(s) signed successfully")
            self._status_label.setStyleSheet("color: #16a34a; font-size: 12px; padding: 4px;")
        elif status == "partial":
            self._status_label.setText(
                f"⚠ Partial completion — {results_count} ok, {errors_count} error(s)"
            )
            self._status_label.setStyleSheet("color: #ca8a04; font-size: 12px; padding: 4px;")
        else:
            self._status_label.setText(f"✗ Signing failed — {errors_count} error(s)")
            self._status_label.setStyleSheet("color: #dc2626; font-size: 12px; padding: 4px;")

        self._progress_bar.setValue(100)
        self._cancel_btn.setEnabled(False)
        self._signing_in_progress = False
        self._current_request = None
        self._update_ui_state()

        # Auto-close after delay
        delay = 2000 if status == "ok" else 4000
        QTimer.singleShot(delay, self.close)

    def _on_signing_error(self, error_msg: str) -> None:
        self._log(f"[ERROR] {error_msg}")
        self._status_label.setText(f"✗ Error: {error_msg}")
        self._status_label.setStyleSheet("color: #dc2626; font-size: 12px; padding: 4px;")
        self._progress_bar.setVisible(False)
        self._cancel_btn.setEnabled(False)
        self._signing_in_progress = False
        self._current_request = None
        self._update_ui_state()
        QTimer.singleShot(4000, self.close)

    def _on_cancel_clicked(self) -> None:
        self._cancel_requested = True
        self._cancel_btn.setEnabled(False)
        self._log("[USER] Cancellation requested")
        self._status_label.setText("Cancelling…")

    # ── UI helpers ──────────────────────────────────────────────────────

    def _update_ui_state(self) -> None:
        has_token = self._token_combo.count() > 0
        has_request = self._current_request is not None
        self._sign_btn.setEnabled(has_token and has_request and not self._signing_in_progress)

    def _log(self, text: str) -> None:
        """Append a line to the activity log (must be called from main thread)."""
        from datetime import datetime
        ts = datetime.now().strftime("%H:%M:%S")
        self._log_text.append(f"[{ts}] {text}")
        self._log_text.moveCursor(QTextCursor.MoveOperation.End)

    def _append_log(self, text: str) -> None:
        """Thread-safe log via signal."""
        self._log(text)

    # ── v1.0.3: Callback delivery for request-level errors ─────────────

    def _send_error_callbacks_for_all(
        self, raw_request: dict, code: str, message: str
    ) -> None:
        """Send error callbacks for ALL objects in the request.

        Used for request-level errors (CERT_NOT_FOUND, SIGN_FAILED, etc.)
        and user cancellation.  In v1.0.3 the extension returns only an ACK,
        so callbacks are the sole channel through which the caller learns
        about failures.

        Best-effort: individual callback failures are logged but do not
        propagate.  If the request cannot be parsed (malformed JSON), no
        callbacks are sent.
        """
        try:
            request = parse_request(raw_request)
            resolved = resolve_objects(request)
            for obj in resolved:
                try:
                    send_error_callback(
                        url=obj.callback_on_error,
                        object_id=obj.id,
                        request_id=request.request_id,
                        error_code=code,
                        error_message=message,
                        metadata=request.metadata,
                        headers=obj.callback_headers,
                    )
                    logger.info(
                        "Error callback sent for %s: %s", obj.id, code
                    )
                except Exception as exc:
                    logger.warning(
                        "Error callback failed for %s: %s", obj.id, exc
                    )
        except Exception as exc:
            logger.warning("Could not send error callbacks: %s", exc)

    def closeEvent(self, event) -> None:
        """Handle window close with a pending request (v1.0.3).

        Sends CANCELLED_BY_USER error callbacks for all objects so the
        caller's backend is notified even though the host is shutting down.
        """
        if self._current_request is not None and not self._response_sent:
            self._log("[USER] Window closed with pending request — sending CANCELLED_BY_USER callbacks")
            self._cancel_requested = True
            self._response_sent = True
            self._send_error_callbacks_for_all(
                self._current_request,
                "CANCELLED_BY_USER",
                "User closed the signing application",
            )
        super().closeEvent(event)

    def _flash_window(self) -> None:
        """Flash the window and bring it to front."""
        self.activateWindow()
        self.raise_()
        self.setWindowState(
            self.windowState() & ~Qt.WindowState.WindowMinimized
            | Qt.WindowState.WindowActive
        )

        original_title = self.windowTitle()
        flash_count = 0

        def flash() -> None:
            nonlocal flash_count
            if flash_count < 6:
                if flash_count % 2 == 0:
                    self.setWindowTitle("★ SIGNING REQUEST RECEIVED ★")
                else:
                    self.setWindowTitle(original_title)
                flash_count += 1
                QTimer.singleShot(400, flash)
            else:
                self.setWindowTitle(original_title)

        flash()


# ─── Application entry point ───────────────────────────────────────────────

def run_gui() -> None:
    """Create the QApplication and show the main window."""
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(APP_VERSION)

    # Application-wide icon (taskbar, system tray, etc.)
    icon_path = resource_path("logo.png")
    if icon_path.exists():
        app.setWindowIcon(QIcon(str(icon_path)))

    window = SignBridgeWindow()
    window.show()

    sys.exit(app.exec())
