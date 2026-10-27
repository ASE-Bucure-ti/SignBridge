"""Sanity-check that the PoC PDF exposes Signature1 as /FT /Sig."""
from pathlib import Path

pdf = Path(__file__).resolve().parents[1] / "assets" / "poc" / "signbridge-poc-acroform.pdf"
data = pdf.read_bytes()
text = data.decode("latin-1")
assert "/FT /Sig" in text or "/FT/Sig" in text
assert "/T (Signature1)" in text
assert "/AcroForm" in text
print(f"OK {pdf.name}: Signature1 AcroForm field present ({len(data)} bytes)")
