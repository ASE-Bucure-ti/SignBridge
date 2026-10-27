// SignBridge — Signature appearance stream builder
//
// Visible signature Form XObject:
//   [logo]  Digitally signed by <CN>
//           <date and time>
//
// The widget /Rect is sized from the CN length. The logo is RGB + soft-mask
// alpha so it sits on a transparent background inside the stamp.
//
// References: PDF Reference 1.7, Section 8.10 (Form XObjects)

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Logo pixels for a PDF Image XObject with optional soft-mask alpha.
class AppearanceLogo {
  final Uint8List rgbBytes;
  final Uint8List? alphaBytes;
  final int pixelWidth;
  final int pixelHeight;

  AppearanceLogo({
    required this.rgbBytes,
    required this.pixelWidth,
    required this.pixelHeight,
    this.alphaBytes,
  });

  bool get hasAlpha => alphaBytes != null;
}

/// Computed layout for the visible stamp (PDF points).
class AppearanceLayout {
  final double width;
  final double height;
  final double margin;
  final double logoSide;
  final double fontSize;
  final double lineHeight;
  final String line1;
  final String line2;

  const AppearanceLayout({
    required this.width,
    required this.height,
    required this.margin,
    required this.logoSide,
    required this.fontSize,
    required this.lineHeight,
    required this.line1,
    required this.line2,
  });
}

/// Result of building a signature appearance form stream.
class AppearanceStream {
  final List<int> streamBytes;
  final double width;
  final double height;

  AppearanceStream({
    required this.streamBytes,
    required this.width,
    required this.height,
  });
}

/// Approximate Helvetica string width in PDF points.
double estimateHelveticaWidth(String text, double fontSize) {
  // WinAnsi Helvetica averages ~0.5em; bias slightly high for uppercase CN.
  var units = 0.0;
  for (final code in text.codeUnits) {
    if (code == 0x20) {
      units += 0.278;
    } else if (code >= 0x41 && code <= 0x5A) {
      units += 0.667; // A-Z
    } else if (code >= 0x61 && code <= 0x7A) {
      units += 0.556; // a-z
    } else if (code >= 0x30 && code <= 0x39) {
      units += 0.556; // 0-9
    } else {
      units += 0.6;
    }
  }
  return units * fontSize;
}

/// Size the stamp from CN + timestamp. Logo aspect is preserved when provided.
AppearanceLayout computeAppearanceLayout({
  required String signerName,
  required String signingTimeLabel,
  AppearanceLogo? logo,
  double fontSize = 9.0,
}) {
  final cn = signerName.length > 80
      ? '${signerName.substring(0, 77)}...'
      : signerName;
  final line1 = 'Digitally signed by $cn';
  final line2 = signingTimeLabel;

  final lineHeight = fontSize * 1.3;
  final margin = 6.0;
  final gap = 8.0;

  final textWidth = math.max(
    estimateHelveticaWidth(line1, fontSize),
    estimateHelveticaWidth(line2, fontSize),
  );
  final textHeight = lineHeight * 2;

  double logoW = 0;
  double logoH = 0;
  if (logo != null) {
    logoH = math.max(textHeight, 28.0).clamp(28.0, 40.0);
    final aspect = logo.pixelWidth / logo.pixelHeight;
    logoW = logoH * aspect;
  }

  final contentHeight = math.max(logoH, textHeight);
  final width = margin + logoW + (logo != null ? gap : 0) + textWidth + margin;
  final height = margin + contentHeight + margin;

  return AppearanceLayout(
    width: width.ceilToDouble(),
    height: height.ceilToDouble(),
    margin: margin,
    logoSide: logoH, // stored as logo height; width derived from aspect at paint
    fontSize: fontSize,
    lineHeight: lineHeight,
    line1: line1,
    line2: line2,
  );
}

/// Grow/shrink an anchor /Rect to [neededWidth]×[neededHeight], keeping the
/// bottom-left corner fixed (typical signature field placement).
List<double> fitAppearanceRect(
  List<double> anchor,
  AppearanceLayout layout,
) {
  final x1 = anchor[0];
  final y1 = anchor[1];
  return [x1, y1, x1 + layout.width, y1 + layout.height];
}

/// Build a visible signature appearance stream for [layout].
AppearanceStream buildAppearance({
  required AppearanceLayout layout,
  AppearanceLogo? logo,
}) {
  final width = layout.width;
  final height = layout.height;
  final margin = layout.margin;
  final fontSize = layout.fontSize;
  final lineHeight = layout.lineHeight;
  final lines = [layout.line1, layout.line2];

  double logoW = 0;
  double logoH = 0;
  if (logo != null) {
    logoH = layout.logoSide;
    logoW = logoH * (logo.pixelWidth / logo.pixelHeight);
  }
  final textLeft = margin + logoW + (logo != null ? 8.0 : 0.0);

  final stream = StringBuffer();

  // Light background + border
  stream.writeln('0.96 0.96 0.96 rg');
  stream.writeln('0 0 ${_fmt(width)} ${_fmt(height)} re f');
  stream.writeln('0.35 0.35 0.35 RG');
  stream.writeln('0.5 w');
  stream.writeln('0 0 ${_fmt(width)} ${_fmt(height)} re S');

  if (logo != null) {
    final logoY = (height - logoH) / 2;
    stream.writeln('q');
    stream.writeln(
      '${_fmt(logoW)} 0 0 ${_fmt(logoH)} ${_fmt(margin)} ${_fmt(logoY)} cm',
    );
    stream.writeln('/Im1 Do');
    stream.writeln('Q');
  }

  stream.writeln('BT');
  stream.writeln('/F1 ${_fmt(fontSize)} Tf');
  stream.writeln('0 0 0 rg');

  final blockHeight = lines.length * lineHeight;
  var y = (height + blockHeight) / 2 - fontSize;

  for (final line in lines) {
    stream.writeln('${_fmt(textLeft)} ${_fmt(y)} Td');
    stream.writeln('(${_escapePdfText(line)}) Tj');
    stream.writeln('${_fmt(-textLeft)} ${_fmt(-y)} Td');
    y -= lineHeight;
  }

  stream.writeln('ET');

  return AppearanceStream(
    streamBytes: latin1.encode(stream.toString()),
    width: width,
    height: height,
  );
}

/// Build the Form XObject dictionary + stream body.
String buildAppearanceXObject(
  AppearanceStream appearance, {
  int? logoImageObjNum,
}) {
  final streamData = appearance.streamBytes;
  final buf = StringBuffer();
  buf.writeln('<<');
  buf.writeln('  /Type /XObject');
  buf.writeln('  /Subtype /Form');
  buf.writeln(
    '  /BBox [0 0 ${_fmt(appearance.width)} ${_fmt(appearance.height)}]',
  );
  buf.writeln('  /Matrix [1 0 0 1 0 0]');
  buf.write('  /Resources <<');
  buf.write(
    ' /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>',
  );
  if (logoImageObjNum != null) {
    buf.write(' /XObject << /Im1 $logoImageObjNum 0 R >>');
  }
  buf.writeln(' >>');
  buf.writeln('  /Length ${streamData.length}');
  buf.writeln('>>');
  buf.writeln('stream');
  buf.write(latin1.decode(streamData));
  buf.writeln();
  buf.write('endstream');
  return buf.toString();
}

/// Soft-mask (DeviceGray alpha) Image XObject body.
String buildLogoSoftMaskXObject(AppearanceLogo logo) {
  final alpha = logo.alphaBytes!;
  final buf = StringBuffer();
  buf.writeln('<<');
  buf.writeln('  /Type /XObject');
  buf.writeln('  /Subtype /Image');
  buf.writeln('  /Width ${logo.pixelWidth}');
  buf.writeln('  /Height ${logo.pixelHeight}');
  buf.writeln('  /ColorSpace /DeviceGray');
  buf.writeln('  /BitsPerComponent 8');
  buf.writeln('  /Length ${alpha.length}');
  buf.writeln('>>');
  buf.writeln('stream');
  buf.write(latin1.decode(alpha));
  buf.writeln();
  buf.write('endstream');
  return buf.toString();
}

/// RGB Image XObject body, optionally referencing a soft-mask object.
String buildLogoImageXObject(AppearanceLogo logo, {int? softMaskObjNum}) {
  final data = logo.rgbBytes;
  final buf = StringBuffer();
  buf.writeln('<<');
  buf.writeln('  /Type /XObject');
  buf.writeln('  /Subtype /Image');
  buf.writeln('  /Width ${logo.pixelWidth}');
  buf.writeln('  /Height ${logo.pixelHeight}');
  buf.writeln('  /ColorSpace /DeviceRGB');
  buf.writeln('  /BitsPerComponent 8');
  if (softMaskObjNum != null) {
    buf.writeln('  /SMask $softMaskObjNum 0 R');
  }
  buf.writeln('  /Length ${data.length}');
  buf.writeln('>>');
  buf.writeln('stream');
  buf.write(latin1.decode(data));
  buf.writeln();
  buf.write('endstream');
  return buf.toString();
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

String _escapePdfText(String s) {
  return s
      .replaceAll('\\', '\\\\')
      .replaceAll('(', '\\(')
      .replaceAll(')', '\\)');
}
