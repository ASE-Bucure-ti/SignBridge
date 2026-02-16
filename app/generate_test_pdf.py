#!/usr/bin/env python3
"""
Generate a test PDF with an AcroForm signature field placeholder.

Uses fpdf2 to create a valid one-page PDF, then uses pyHanko to add
a pre-existing empty signature field named "Signature1".

Prerequisites (install once):
  pip install fpdf2 pyHanko

Output: server/fixtures/test-document.pdf
"""

import io
from pathlib import Path

from fpdf import FPDF
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko.sign.fields import SigFieldSpec, append_signature_field


def main():
    # ── Step 1: Create a basic valid PDF with fpdf2 ──────────────────────
    pdf = FPDF()
    pdf.set_auto_page_break(auto=False)
    pdf.add_page()

    # Title
    pdf.set_font("Helvetica", "B", 18)
    pdf.cell(0, 15, "SignBridge Test Document", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.ln(10)

    # Body text
    pdf.set_font("Helvetica", "", 12)
    pdf.multi_cell(0, 8, (
        "This is a mock PDF document used by the SignBridge test client. "
        "It contains an AcroForm signature field placeholder named 'Signature1'. "
        "When the native host processes a signing request with "
        'pdfOptions.label = "Signature1", it will locate this field and apply '
        "the PKCS#11 digital signature here."
    ), new_x="LMARGIN", new_y="NEXT")
    pdf.ln(10)

    # Metadata box
    pdf.set_font("Helvetica", "I", 10)
    pdf.cell(0, 8, "Document ID: test-document", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, "Generated for: SignBridge Protocol v1.0.3 testing", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 8, "Signature field: Signature1 (AcroForm placeholder)", new_x="LMARGIN", new_y="NEXT")

    # Signature placeholder area (visual hint)
    pdf.ln(20)
    rect_y = pdf.get_y()  # capture Y in fpdf coords (top-left origin)
    rect_h = 50
    pdf.set_draw_color(180, 180, 180)
    pdf.set_fill_color(245, 245, 245)
    pdf.rect(30, rect_y, 150, rect_h, style="DF")
    pdf.set_xy(35, rect_y + 5)
    pdf.set_font("Helvetica", "", 10)
    pdf.set_text_color(150, 150, 150)
    pdf.cell(0, 8, "[Digital Signature - Signature1]")
    pdf.set_xy(35, pdf.get_y() + 12)
    pdf.cell(0, 8, "This area will be filled by the signing process.")

    base_pdf_bytes = pdf.output()

    # ── Step 2: Add AcroForm signature field via pyHanko ─────────────────
    # fpdf2 uses top-left origin (Y increases downward).
    # PDF spec uses bottom-left origin (Y increases upward).
    # Page height for A4 default = 841.89pt, for Letter = 792pt.
    # fpdf2 default is A4 (210x297mm = 595.28x841.89pt).
    page_h = pdf.h  # page height in points (fpdf2 units = mm by default → convert)
    # fpdf2 default unit is mm; page_h is in mm. Convert to pt: 1mm = 2.835pt
    page_h_pt = page_h * 2.835
    # Convert fpdf2 rect coords (mm, top-left origin) to PDF coords (pt, bottom-left origin)
    x1 = 30 * 2.835
    y1 = page_h_pt - (rect_y + rect_h) * 2.835  # bottom of rect in PDF coords
    x2 = (30 + 150) * 2.835
    y2 = page_h_pt - rect_y * 2.835              # top of rect in PDF coords

    input_buf = io.BytesIO(base_pdf_bytes)
    writer = IncrementalPdfFileWriter(input_buf)
    append_signature_field(writer, SigFieldSpec(
        sig_field_name="Signature1",
        box=(x1, y1, x2, y2),
    ))

    output_buf = io.BytesIO()
    writer.write(output_buf)
    final_bytes = output_buf.getvalue()

    # ── Step 3: Save ─────────────────────────────────────────────────────
    out_path = Path(__file__).resolve().parent / "server" / "fixtures" / "test-document.pdf"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(final_bytes)
    print(f"Generated test PDF with AcroForm field 'Signature1'")
    print(f"  Size: {len(final_bytes)} bytes")
    print(f"  Path: {out_path}")


if __name__ == "__main__":
    main()
