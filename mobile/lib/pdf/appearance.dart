// SignBridge — Signature appearance stream builder
//
// Creates the visual representation of the digital signature that appears
// in the PDF. This is a Form XObject (/Type /XObject /Subtype /Form)
// containing PDF content stream operators for text rendering.
//
// The appearance shows:
//   - "Digitally signed by <CN>"
//   - "Date: <signing time>"
//   - "Signed by SignBridge"
//
// References: PDF Reference 1.7, Section 8.10 (Form XObjects)

import 'dart:convert';

/// Result of building a signature appearance.
class AppearanceStream {
  /// The raw content stream bytes (PDF operators).
  final List<int> streamBytes;

  /// Width of the appearance bounding box.
  final double width;

  /// Height of the appearance bounding box.
  final double height;

  AppearanceStream({
    required this.streamBytes,
    required this.width,
    required this.height,
  });
}

/// Build a visible signature appearance stream.
///
/// [signerName] — from certificate CN.
/// [signingTime] — formatted timestamp.
/// [rect] — [x1, y1, x2, y2] bounding box in PDF points.
AppearanceStream buildAppearance({
  required String signerName,
  required String signingTime,
  required List<double> rect,
}) {
  final width = (rect[2] - rect[0]).abs();
  final height = (rect[3] - rect[1]).abs();

  // Font size — scale based on available height
  final fontSize = (height / 5.0).clamp(6.0, 12.0);
  final lineHeight = fontSize * 1.3;

  // Build text content
  final lines = [
    'Digitally signed by',
    _escapePdfString(signerName),
    'Date: $signingTime',
    'Signed by SignBridge',
  ];

  // Generate PDF content stream
  final stream = StringBuffer();

  // Light gray background
  stream.writeln('0.95 0.95 0.95 rg');
  stream.writeln('0 0 ${_fmt(width)} ${_fmt(height)} re f');

  // Dark border
  stream.writeln('0.3 0.3 0.3 RG');
  stream.writeln('0.5 w');
  stream.writeln('0 0 ${_fmt(width)} ${_fmt(height)} re S');

  // Text
  stream.writeln('BT');
  stream.writeln('/F1 ${_fmt(fontSize)} Tf');
  stream.writeln('0 0 0 rg'); // black text

  // Position text from top-left with margin
  final margin = 4.0;
  var y = height - margin - fontSize;

  for (final line in lines) {
    if (y < margin) break; // don't overflow
    stream.writeln('${_fmt(margin)} ${_fmt(y)} Td');
    stream.writeln('(${_escapePdfText(line)}) Tj');
    // Reset position for next line (Td is relative but we use absolute)
    stream.writeln('${_fmt(-margin)} ${_fmt(-(y))} Td');
    y -= lineHeight;
  }

  stream.writeln('ET');

  final streamBytes = latin1.encode(stream.toString());

  return AppearanceStream(
    streamBytes: streamBytes,
    width: width,
    height: height,
  );
}

/// Build the Form XObject dictionary + stream as a complete PDF object body.
///
/// Returns the string content between "N 0 obj" and "endobj".
/// [appearanceObjNum] is the object number for cross-references.
String buildAppearanceXObject(AppearanceStream appearance) {
  final streamData = appearance.streamBytes;
  final length = streamData.length;

  final buf = StringBuffer();
  buf.writeln('<<');
  buf.writeln('  /Type /XObject');
  buf.writeln('  /Subtype /Form');
  buf.writeln(
    '  /BBox [0 0 ${_fmt(appearance.width)} ${_fmt(appearance.height)}]',
  );
  buf.writeln('  /Matrix [1 0 0 1 0 0]');
  buf.writeln(
    '  /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>',
  );
  buf.writeln('  /Length $length');
  buf.writeln('>>');
  buf.writeln('stream');
  buf.write(latin1.decode(streamData));
  buf.writeln();
  buf.write('endstream');

  return buf.toString();
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Format a double for PDF (remove trailing zeros, max 2 decimal places).
String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

/// Escape a string for use in a PDF text string (parentheses).
String _escapePdfText(String s) {
  return s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');
}

/// Escape a string for embedding in PDF — truncate if too long.
String _escapePdfString(String s) {
  // Limit to reasonable length to fit in appearance box
  final truncated = s.length > 60 ? '${s.substring(0, 57)}...' : s;
  return _escapePdfText(truncated);
}
