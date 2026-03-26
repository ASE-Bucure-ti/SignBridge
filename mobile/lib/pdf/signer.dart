// SignBridge — PDF ByteRange signer
//
// Implements PAdES-compliant byte-range signing (/adbe.pkcs7.detached):
//
//   1. Prepare: build signature dictionary with /ByteRange and /Contents
//      placeholders (fixed-width, will be patched after signing)
//   2. Compute: SHA-256 or SHA-384 digest over the two byte ranges
//      (everything except the hex /Contents value)
//   3. Patch: replace /ByteRange placeholder values and /Contents hex
//      string with actual CMS envelope
//
// The signing flow is:
//   prepareForSigning() → returns prepared PDF + digest to sign
//   embedSignature()    → patches CMS into the prepared PDF
//
// References: PDF Reference 1.7 §12.8.1, ETSI EN 319 142 (PAdES)

import 'dart:convert';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import '../crypto/hash.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// Size of the /Contents hex placeholder in bytes.
/// 16384 bytes = 32768 hex chars. Sufficient for most CMS envelopes.
const _contentsPlaceholderSize = 16384;

/// Fixed-width format for /ByteRange integer values (10 digits).
const _byteRangeWidth = 10;

/// Placeholder for /ByteRange values before patching.
final _byteRangePlaceholder =
    '[${'0' * _byteRangeWidth} ${'0' * _byteRangeWidth} ${'0' * _byteRangeWidth} ${'0' * _byteRangeWidth}]';

/// Placeholder for /Contents hex value (all zeros).
final _contentsPlaceholder = '<${'0' * _contentsPlaceholderSize * 2}>';

/// Result of preparing a PDF for signing.
class PreparedPdf {
  /// The prepared PDF bytes (with placeholders).
  final Uint8List bytes;

  /// The SHA digest of the byte ranges (to be signed by the card).
  final Uint8List digest;

  /// Byte offset where the /Contents hex string starts (the '<').
  final int contentsHexStart;

  /// Byte offset where the /Contents hex string ends (after '>').
  final int contentsHexEnd;

  /// The computed byte ranges [offset1, length1, offset2, length2].
  final List<int> byteRanges;

  /// Byte offset of the /ByteRange placeholder in the prepared PDF.
  final int byteRangePlaceholderOffset;

  PreparedPdf({
    required this.bytes,
    required this.digest,
    required this.contentsHexStart,
    required this.contentsHexEnd,
    required this.byteRanges,
    required this.byteRangePlaceholderOffset,
  });
}

/// Build the signature dictionary string.
///
/// This produces the /Type /Sig dictionary that goes between
/// "N 0 obj" and "endobj" in the PDF.
///
/// [sigValueRef] — object number for the /V reference (not used inline).
/// [signingTime] — formatted as PDF date string.
/// [reason] — /Reason value.
/// [location] — /Location value.
/// [contactInfo] — /ContactInfo value (optional).
String buildSigDict({
  required String signingTime,
  String reason = 'Signed by SignBridge',
  String location = 'SignBridge Mobile',
  String? contactInfo,
}) {
  final buf = StringBuffer();
  buf.writeln('<<');
  buf.writeln('  /Type /Sig');
  buf.writeln('  /Filter /Adobe.PPKLite');
  buf.writeln('  /SubFilter /adbe.pkcs7.detached');
  buf.writeln('  /ByteRange $_byteRangePlaceholder');
  buf.writeln('  /Contents $_contentsPlaceholder');
  buf.writeln('  /M (D:$signingTime)');
  buf.writeln('  /Reason ($reason)');
  buf.writeln('  /Location ($location)');
  if (contactInfo != null) {
    buf.writeln('  /ContactInfo ($contactInfo)');
  }
  buf.writeln('>>');
  return buf.toString();
}

/// Prepare the PDF for signing by locating the /Contents placeholder
/// and computing the byte-range digest.
///
/// [pdfBytes] — the full PDF (after incremental update with sig dict).
/// [useSha384] — if true, use SHA-384; otherwise SHA-256.
///
/// The caller must have already written the incremental update containing
/// the signature dictionary with placeholders.
PreparedPdf prepareForSigning(Uint8List pdfBytes, {bool useSha384 = true}) {
  final pdfStr = latin1.decode(pdfBytes);

  // Find the /Contents placeholder
  final contentsIdx = pdfStr.lastIndexOf('/Contents <');
  if (contentsIdx < 0) {
    throw StateError('/Contents placeholder not found in prepared PDF');
  }

  // Find the hex string boundaries
  final hexStart = pdfStr.indexOf('<', contentsIdx + '/Contents '.length);
  final hexEnd = pdfStr.indexOf('>', hexStart);
  if (hexStart < 0 || hexEnd < 0) {
    throw StateError('/Contents hex boundaries not found');
  }
  // hexStart points to '<', hexEnd points to '>'
  // The signed region excludes the hex string (from '<' to '>' inclusive)

  final contentsHexStart = hexStart;
  final contentsHexEnd = hexEnd + 1; // exclusive end

  // Compute byte ranges:
  // Range 1: from start of file to just before '<'
  // Range 2: from just after '>' to end of file
  final range1Start = 0;
  final range1Length = contentsHexStart;
  final range2Start = contentsHexEnd;
  final range2Length = pdfBytes.length - contentsHexEnd;

  final byteRanges = [range1Start, range1Length, range2Start, range2Length];

  // Find and patch /ByteRange placeholder
  final brIdx = pdfStr.lastIndexOf('/ByteRange [${'0' * _byteRangeWidth}');
  if (brIdx < 0) {
    throw StateError('/ByteRange placeholder not found');
  }

  // Patch byte range values (fixed-width to preserve offsets)
  final patchedPdf = Uint8List.fromList(pdfBytes);
  final brValue =
      '[${_pad(range1Start)} ${_pad(range1Length)} ${_pad(range2Start)} ${_pad(range2Length)}]';
  final brValueOffset = pdfStr.indexOf('[', brIdx);
  final brBytes = latin1.encode(brValue);
  patchedPdf.setRange(brValueOffset, brValueOffset + brBytes.length, brBytes);

  // Compute digest over the two byte ranges
  _log.d('ByteRange: $byteRanges');
  final digest = useSha384
      ? _computeByteRangeDigest384(patchedPdf, byteRanges)
      : _computeByteRangeDigest256(patchedPdf, byteRanges);

  return PreparedPdf(
    bytes: patchedPdf,
    digest: digest,
    contentsHexStart: contentsHexStart,
    contentsHexEnd: contentsHexEnd,
    byteRanges: byteRanges,
    byteRangePlaceholderOffset: brValueOffset,
  );
}

/// Embed the CMS signature into the prepared PDF.
///
/// Patches the /Contents hex placeholder with the actual CMS DER bytes.
/// Returns the final signed PDF.
Uint8List embedSignature(PreparedPdf prepared, Uint8List cmsSignature) {
  if (cmsSignature.length > _contentsPlaceholderSize) {
    throw StateError(
      'CMS signature (${cmsSignature.length} bytes) exceeds '
      'placeholder size ($_contentsPlaceholderSize bytes)',
    );
  }

  final pdf = Uint8List.fromList(prepared.bytes);

  // Convert CMS to hex and pad with zeros
  final hex = cmsSignature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final paddedHex = hex.padRight(_contentsPlaceholderSize * 2, '0');

  // Write hex between '<' and '>'
  // The '<' is at contentsHexStart, hex content starts at +1
  final hexBytes = latin1.encode(paddedHex);
  pdf.setRange(
    prepared.contentsHexStart + 1,
    prepared.contentsHexStart + 1 + hexBytes.length,
    hexBytes,
  );

  _log.i('Embedded CMS signature: ${cmsSignature.length} bytes');
  return pdf;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Pad an integer to fixed width for /ByteRange.
String _pad(int value) => value.toString().padLeft(_byteRangeWidth, '0');

/// Compute SHA-256 digest over byte ranges.
Uint8List _computeByteRangeDigest256(Uint8List pdf, List<int> ranges) {
  final sink = Sha256Sink();
  sink.add(Uint8List.sublistView(pdf, ranges[0], ranges[0] + ranges[1]));
  sink.add(Uint8List.sublistView(pdf, ranges[2], ranges[2] + ranges[3]));
  return sink.finish();
}

/// Compute SHA-384 digest over byte ranges.
Uint8List _computeByteRangeDigest384(Uint8List pdf, List<int> ranges) {
  final sink = Sha384Sink();
  sink.add(Uint8List.sublistView(pdf, ranges[0], ranges[0] + ranges[1]));
  sink.add(Uint8List.sublistView(pdf, ranges[2], ranges[2] + ranges[3]));
  return sink.finish();
}

/// Format a DateTime as a PDF date string: YYYYMMDDHHmmss+00'00'
String formatPdfDate(DateTime dt) {
  final utc = dt.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}'
      '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}'
      "+00'00'";
}
