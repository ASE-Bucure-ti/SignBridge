"""Build the one-page PDF used by the on-device signing PoC."""

from pathlib import Path

content = b"BT /F1 24 Tf 72 760 Td (SignBridge PoC) Tj 0 -36 Td (Synthetic PDF) Tj ET"
bodies = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
    b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]

out = bytearray(b"%PDF-1.4\n")
offsets = [0]
for index, body in enumerate(bodies, 1):
    offsets.append(len(out))
    out += f"{index} 0 obj\n".encode() + body + b"\nendobj\n"

xref_at = len(out)
out += f"xref\n0 {len(bodies) + 1}\n".encode()
out += b"0000000000 65535 f \n"
for offset in offsets[1:]:
    out += f"{offset:010d} 00000 n \n".encode()
out += (
    f"trailer\n<< /Size {len(bodies) + 1} /Root 1 0 R >>\n"
    f"startxref\n{xref_at}\n%%EOF\n"
).encode()

dest = Path(__file__).resolve().parents[1] / "assets" / "poc" / "signbridge-poc.pdf"
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_bytes(out)
print(f"wrote {dest} ({len(out)} bytes, xref at {xref_at})")
