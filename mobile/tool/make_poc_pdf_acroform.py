"""Build a one-page PDF with a pre-created empty signature AcroForm field.

Field name (/T): Signature1 — the label used by the E2E deep-link test.
"""

from pathlib import Path

# Page content
content = (
    b"BT /F1 18 Tf 72 760 Td (SignBridge E2E) Tj "
    b"0 -28 Td /F1 12 Tf (Pre-created AcroForm field: Signature1) Tj ET"
)

# Objects:
# 1 Catalog (+ AcroForm)
# 2 Pages
# 3 Page (+ Annots)
# 4 Contents
# 5 Font
# 6 Signature widget (empty /FT /Sig, no /V yet)
# 7 AcroForm

bodies = []

# Will fill after we know object numbers — build in order:
# 1 catalog, 2 pages, 3 page, 4 contents, 5 font, 6 widget, 7 acroform

# Widget rect: bottom area, ~220x56 pt
rect = b"[72 72 292 128]"

bodies = [
    # 1 Catalog
    b"<< /Type /Catalog /Pages 2 0 R /AcroForm 7 0 R >>",
    # 2 Pages
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    # 3 Page
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
    b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> "
    b"/Annots [6 0 R] >>",
    # 4 Contents
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
    # 5 Font
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    # 6 Empty signature field widget
    b"<< /Type /Annot /Subtype /Widget /FT /Sig /T (Signature1) "
    b"/F 4 /Rect " + rect + b" /P 3 0 R >>",
    # 7 AcroForm
    b"<< /SigFlags 3 /Fields [6 0 R] >>",
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

dest = (
    Path(__file__).resolve().parents[1]
    / "assets"
    / "poc"
    / "signbridge-poc-acroform.pdf"
)
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_bytes(out)
print(f"wrote {dest} ({len(out)} bytes)")
