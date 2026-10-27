"""Local HTTP server + deep-link launcher for SignBridge Mobile E2E.

Serves the AcroForm PoC PDF, accepts the signed upload, receives callbacks,
builds a v1.0.3 payload, and fires signbridge:// via adb.

Usage:
  python mobile/tool/e2e_deep_link_server.py
  python mobile/tool/e2e_deep_link_server.py --host 10.39.42.1 --cert-id "LIVIU-IOAN ZEEK (Semnare)"
"""

from __future__ import annotations

import argparse
import base64
import json
import socket
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PDF_PATH = ROOT / "assets" / "poc" / "signbridge-poc-acroform.pdf"
OUT_DIR = ROOT / "assets" / "poc"
SIGNED_OUT = OUT_DIR / "signbridge-e2e-signed.pdf"


def guess_lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


class Handler(BaseHTTPRequestHandler):
    server_version = "SignBridgeE2E/1.0"

    def log_message(self, fmt: str, *args) -> None:
        print(f"[http] {self.address_string()} {fmt % args}")

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.startswith("/doc.pdf"):
            data = PDF_PATH.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/pdf")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path.startswith("/health"):
            self._json(200, {"ok": True})
            return
        self._json(404, {"error": "not found"})

    def do_PUT(self) -> None:
        self._handle_upload()

    def do_POST(self) -> None:
        body = self._read_body()
        if self.path.startswith("/upload"):
            self._save_signed(body)
            self._json(200, {"status": "stored", "bytes": len(body)})
            return
        if self.path.startswith("/callback/"):
            kind = self.path.rstrip("/").split("/")[-1]
            try:
                parsed = json.loads(body.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                parsed = {"raw": body.decode("utf-8", errors="replace")}
            print(f"[callback:{kind}] {json.dumps(parsed, ensure_ascii=False)[:800]}")
            self._json(200, {"received": True})
            return
        self._json(404, {"error": "not found"})

    def _read_body(self) -> bytes:
        length_hdr = self.headers.get("Content-Length")
        if length_hdr is not None and length_hdr != "":
            length = int(length_hdr)
            return self.rfile.read(length) if length else b""

        # Dio Stream uploads often use Transfer-Encoding: chunked
        encoding = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in encoding:
            return self._read_chunked()

        # Last resort: nothing declared
        return b""

    def _read_chunked(self) -> bytes:
        chunks: list[bytes] = []
        while True:
            line = self.rfile.readline()
            if not line:
                break
            size_str = line.strip().split(b";", 1)[0]
            try:
                size = int(size_str, 16)
            except ValueError:
                break
            if size == 0:
                # Trailer + final CRLF
                while True:
                    trailer = self.rfile.readline()
                    if trailer in (b"\r\n", b"\n", b""):
                        break
                break
            chunks.append(self.rfile.read(size))
            self.rfile.read(2)  # CRLF after chunk
        return b"".join(chunks)

    def _handle_upload(self) -> None:
        body = self._read_body()
        te = self.headers.get("Transfer-Encoding")
        cl = self.headers.get("Content-Length")
        print(f"[upload] Content-Length={cl!r} Transfer-Encoding={te!r}")
        if not self.path.startswith("/upload"):
            self._json(404, {"error": "not found"})
            return
        self._save_signed(body)
        self._json(200, {"status": "stored", "bytes": len(body)})

    def _save_signed(self, body: bytes) -> None:
        SIGNED_OUT.write_bytes(body)
        print(f"[upload] saved {SIGNED_OUT} ({len(body)} bytes)")
        if body[:8] == b"%PDF-1.4" or body[:5] == b"%PDF-":
            print("[upload] PDF header OK")
        else:
            print("[upload] WARNING: response does not start with %PDF")


def build_payload(base: str, cert_id: str) -> dict:
    request_id = str(uuid.uuid4())
    return {
        "protocolVersion": "1.0",
        "requestId": request_id,
        "appId": "signbridge-mobile-e2e",
        "cert": {"certId": cert_id},
        "metadata": {"source": "mobile-e2e"},
        "objects": [
            {
                "id": "e2e-doc-1",
                "dataType": "pdf",
                "content": {
                    "mode": "remote",
                    "downloadUrl": f"{base}/doc.pdf",
                    "httpMethod": "GET",
                },
                "pdfOptions": {"label": "Signature1"},
                "upload": {
                    "uploadUrl": f"{base}/upload",
                    "httpMethod": "PUT",
                    "signedContentType": "pdf",
                },
                "callbacks": {
                    "onSuccess": f"{base}/callback/success",
                    "onError": f"{base}/callback/error",
                    "progress": f"{base}/callback/progress",
                },
            }
        ],
    }


def encode_deep_link(payload: dict) -> str:
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    b64 = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    return f"signbridge://sign?payload={b64}"


def fire_adb(deep_link: str) -> None:
    cmd = [
        "adb",
        "shell",
        "am",
        "start",
        "-a",
        "android.intent.action.VIEW",
        "-d",
        deep_link,
    ]
    print("[adb]", " ".join(cmd[:7]), deep_link[:80] + "...")
    subprocess.run(cmd, check=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=guess_lan_ip())
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--cert-id",
        default="LIVIU-IOAN ZEEK (Semnare)",
        help="cert.certId from the protocol payload",
    )
    parser.add_argument(
        "--no-adb",
        action="store_true",
        help="Only print the deep link; do not invoke adb",
    )
    args = parser.parse_args()

    if not PDF_PATH.is_file():
        print(f"Missing PDF: {PDF_PATH}", file=sys.stderr)
        return 1

    base = f"http://{args.host}:{args.port}"
    payload = build_payload(base, args.cert_id)
    deep_link = encode_deep_link(payload)

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()

    print(f"Serving on {base}")
    print(f"PDF: {PDF_PATH}")
    print(f"Signed output: {SIGNED_OUT}")
    print(f"requestId: {payload['requestId']}")
    print(f"certId: {args.cert_id}")
    print()
    print("Deep link:")
    print(deep_link)
    print()

    if not args.no_adb:
        fire_adb(deep_link)
        print("Deep link fired. Complete CAN/PIN/NFC on the phone.")
    else:
        print("Skipped adb. Open the deep link on the device manually.")

    print("Ctrl+C to stop the server.")
    try:
        # Do not thread.join() forever: on Windows that often swallows Ctrl+C.
        while thread.is_alive():
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nStopping...")
        httpd.shutdown()
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
