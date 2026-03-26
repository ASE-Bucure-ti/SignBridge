// SignBridge — PDF structure parser
//
// Minimal PDF parser that extracts only what's needed for signing:
//   - startxref offset
//   - Cross-reference table (classic xref or xref streams)
//   - Trailer dictionary (/Root, /Size, /Prev, /Info)
//   - Catalog (/Root) → /AcroForm, /Pages
//   - Indirect object reading by offset
//   - Page object resolution (for widget annotation placement)
//
// Does NOT render or fully interpret PDF content — only structural parsing.
//
// References: PDF Reference 1.7 (ISO 32000-1)

import 'dart:convert';
import 'dart:typed_data';
import 'package:logger/logger.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

// ─── Cross-Reference Entry ──────────────────────────────────────────────────

/// A single xref entry: byte offset of an object.
class XrefEntry {
  final int objNum;
  final int genNum;
  final int offset;
  final bool inUse;

  XrefEntry({
    required this.objNum,
    required this.genNum,
    required this.offset,
    required this.inUse,
  });

  @override
  String toString() =>
      'XrefEntry($objNum $genNum ${inUse ? "n" : "f"} @$offset)';
}

// ─── PDF Object Reference ───────────────────────────────────────────────────

/// An indirect object reference: "N G R".
class PdfRef {
  final int objNum;
  final int genNum;

  const PdfRef(this.objNum, this.genNum);

  @override
  String toString() => '$objNum $genNum R';

  @override
  bool operator ==(Object other) =>
      other is PdfRef && objNum == other.objNum && genNum == other.genNum;

  @override
  int get hashCode => objNum.hashCode ^ genNum.hashCode;
}

// ─── Parsed PDF Info ────────────────────────────────────────────────────────

/// Structural information extracted from a PDF.
class PdfInfo {
  /// Raw PDF bytes.
  final Uint8List bytes;

  /// Offset of the last startxref value.
  final int startxrefOffset;

  /// The xref table (objNum → entry). Merged from all xref sections.
  final Map<int, XrefEntry> xref;

  /// Trailer dictionary values.
  final int size;
  final PdfRef rootRef;
  final int? prevXrefOffset;
  final PdfRef? infoRef;

  /// Catalog dictionary raw string.
  final String catalogDict;

  /// Reference to the AcroForm object (if exists in catalog, may be inline).
  final PdfRef? acroFormRef;

  /// Inline AcroForm dictionary (if embedded directly in catalog).
  final String? acroFormInline;

  /// Reference to Pages object.
  final PdfRef? pagesRef;

  /// The last page's object number (for annotation placement).
  int? lastPageObjNum;

  PdfInfo({
    required this.bytes,
    required this.startxrefOffset,
    required this.xref,
    required this.size,
    required this.rootRef,
    this.prevXrefOffset,
    this.infoRef,
    required this.catalogDict,
    this.acroFormRef,
    this.acroFormInline,
    this.pagesRef,
    this.lastPageObjNum,
  });
}

// ─── Parser ─────────────────────────────────────────────────────────────────

/// Parse a PDF file and extract structural information needed for signing.
PdfInfo parsePdf(Uint8List bytes) {
  final pdfStr = latin1.decode(bytes);

  // Validate magic
  if (!pdfStr.startsWith('%PDF-')) {
    throw FormatException('Not a PDF file (missing %PDF- header)');
  }

  // Check for encryption
  if (RegExp(r'/Encrypt\s').hasMatch(pdfStr)) {
    throw UnsupportedError('Encrypted PDFs cannot be signed');
  }

  // 1. Find startxref
  final startxrefOffset = _findStartxref(pdfStr);
  _log.d('PDF parsed: startxref=$startxrefOffset');

  // 2. Parse xref table + trailer (follow /Prev chain)
  final xref = <int, XrefEntry>{};
  String? trailerStr;
  int? prevOffset;
  int currentXrefOffset = startxrefOffset;

  while (true) {
    final result = _parseXrefSection(pdfStr, currentXrefOffset, xref);
    trailerStr ??= result.trailerStr;
    prevOffset ??= result.prevOffset;

    if (result.prevOffset != null && result.prevOffset != prevOffset) {
      // Follow /Prev chain — only first trailer matters for /Root etc.
    }

    if (result.prevOffset != null) {
      currentXrefOffset = result.prevOffset!;
      // Don't recurse infinitely — break after the initial trailer is captured
      final nextResult = _parseXrefSection(pdfStr, currentXrefOffset, xref);
      if (nextResult.prevOffset != null &&
          nextResult.prevOffset != currentXrefOffset) {
        currentXrefOffset = nextResult.prevOffset!;
        // One more level max for common cases
        _parseXrefSection(pdfStr, currentXrefOffset, xref);
      }
      break;
    } else {
      break;
    }
  }

  if (trailerStr == null) {
    throw FormatException('Could not parse PDF trailer');
  }

  // 3. Parse trailer values
  final size = _extractIntValue(trailerStr, '/Size');
  if (size == null) {
    throw FormatException('/Size not found in trailer');
  }

  final rootRef = _extractRef(trailerStr, '/Root');
  if (rootRef == null) {
    throw FormatException('/Root not found in trailer');
  }

  final prevXref = _extractIntValue(trailerStr, '/Prev');
  final infoRef = _extractRef(trailerStr, '/Info');

  // 4. Read catalog object
  final catalogDict = readObjectDict(pdfStr, rootRef, xref);

  // 5. Parse catalog for /AcroForm and /Pages
  PdfRef? acroFormRef;
  String? acroFormInline;
  final acroFormMatch = RegExp(
    r'/AcroForm\s+(\d+)\s+(\d+)\s+R',
  ).firstMatch(catalogDict);
  if (acroFormMatch != null) {
    acroFormRef = PdfRef(
      int.parse(acroFormMatch.group(1)!),
      int.parse(acroFormMatch.group(2)!),
    );
  } else {
    // Check for inline AcroForm: /AcroForm << ... >>
    final inlineMatch = RegExp(
      r'/AcroForm\s*<<([^>]*(?:<<[^>]*>>[^>]*)*)>>',
    ).firstMatch(catalogDict);
    if (inlineMatch != null) {
      acroFormInline = '<<${inlineMatch.group(1)!}>>';
    }
  }

  final pagesRef = _extractRef(catalogDict, '/Pages');

  // 6. Find last page object number
  int? lastPageObjNum;
  if (pagesRef != null) {
    lastPageObjNum = _findLastPageObjNum(pdfStr, pagesRef, xref);
  }

  _log.i(
    'PDF: size=$size, root=${rootRef.objNum}, '
    'acroForm=${acroFormRef?.objNum ?? "inline"}, '
    'lastPage=$lastPageObjNum',
  );

  return PdfInfo(
    bytes: bytes,
    startxrefOffset: startxrefOffset,
    xref: xref,
    size: size,
    rootRef: rootRef,
    prevXrefOffset: prevXref,
    infoRef: infoRef,
    catalogDict: catalogDict,
    acroFormRef: acroFormRef,
    acroFormInline: acroFormInline,
    pagesRef: pagesRef,
    lastPageObjNum: lastPageObjNum,
  );
}

/// Read the dictionary portion of an indirect object.
String readObjectDict(String pdf, PdfRef ref, Map<int, XrefEntry> xref) {
  final entry = xref[ref.objNum];
  if (entry == null) {
    throw FormatException('Object ${ref.objNum} not found in xref');
  }
  return readObjectDictAtOffset(pdf, entry.offset);
}

/// Read the dictionary of an object at a given byte offset.
String readObjectDictAtOffset(String pdf, int offset) {
  // Skip "N G obj"
  final objStart = pdf.indexOf('obj', offset);
  if (objStart < 0) {
    throw FormatException('Object keyword not found at offset $offset');
  }
  final afterObj = objStart + 3;

  // Find the dictionary << ... >>
  final dictStart = pdf.indexOf('<<', afterObj);
  if (dictStart < 0 || dictStart - afterObj > 50) {
    // Object might not have a dictionary (could be stream, number, etc.)
    // Return the raw content between obj and endobj
    final endobj = pdf.indexOf('endobj', afterObj);
    if (endobj < 0) return '';
    return pdf.substring(afterObj, endobj).trim();
  }

  // Find matching >> (handle nested <<>>)
  final dictEnd = _findMatchingDictEnd(pdf, dictStart);
  return pdf.substring(dictStart, dictEnd + 2);
}

// ─── startxref ──────────────────────────────────────────────────────────────

int _findStartxref(String pdf) {
  // Scan backwards from EOF for "startxref"
  final searchRegion = pdf.length > 1024
      ? pdf.substring(pdf.length - 1024)
      : pdf;

  final match = RegExp(r'startxref\s+(\d+)').firstMatch(searchRegion);
  if (match != null) {
    return int.parse(match.group(1)!);
  }

  // Fallback: search entire file
  final fallbackMatch = RegExp(r'startxref\s+(\d+)').allMatches(pdf).lastOrNull;
  if (fallbackMatch != null) {
    return int.parse(fallbackMatch.group(1)!);
  }

  throw FormatException('startxref not found in PDF');
}

// ─── Xref Parsing ───────────────────────────────────────────────────────────

class _XrefResult {
  final String? trailerStr;
  final int? prevOffset;
  _XrefResult(this.trailerStr, this.prevOffset);
}

_XrefResult _parseXrefSection(
  String pdf,
  int offset,
  Map<int, XrefEntry> xref,
) {
  // Check if it's a classic xref table or xref stream
  final region = pdf.substring(offset, (offset + 20).clamp(0, pdf.length));
  if (region.startsWith('xref')) {
    return _parseClassicXref(pdf, offset, xref);
  } else {
    // Might be an xref stream (PDF 1.5+) — object at this offset
    return _parseXrefStream(pdf, offset, xref);
  }
}

_XrefResult _parseClassicXref(
  String pdf,
  int offset,
  Map<int, XrefEntry> xref,
) {
  var pos = offset + 4; // skip "xref"

  // Skip whitespace
  while (pos < pdf.length &&
      (pdf.codeUnitAt(pos) == 10 ||
          pdf.codeUnitAt(pos) == 13 ||
          pdf.codeUnitAt(pos) == 32)) {
    pos++;
  }

  // Parse subsections: "startObj count\n" followed by "offset gen n|f\n" lines
  while (pos < pdf.length) {
    // Check for trailer
    if (pdf
        .substring(pos, (pos + 7).clamp(0, pdf.length))
        .startsWith('trailer')) {
      break;
    }

    // Parse subsection header: "startObjNum count"
    final headerMatch = RegExp(r'(\d+)\s+(\d+)').matchAsPrefix(pdf, pos);
    if (headerMatch == null) break;

    final startObjNum = int.parse(headerMatch.group(1)!);
    final count = int.parse(headerMatch.group(2)!);
    pos = headerMatch.end;

    // Skip to next line
    while (pos < pdf.length &&
        (pdf.codeUnitAt(pos) == 10 ||
            pdf.codeUnitAt(pos) == 13 ||
            pdf.codeUnitAt(pos) == 32)) {
      pos++;
    }

    // Parse entries
    for (var i = 0; i < count; i++) {
      final entryMatch = RegExp(
        r'(\d{10})\s+(\d{5})\s+([nf])',
      ).matchAsPrefix(pdf, pos);
      if (entryMatch == null) break;

      final entryOffset = int.parse(entryMatch.group(1)!);
      final genNum = int.parse(entryMatch.group(2)!);
      final inUse = entryMatch.group(3) == 'n';
      final objNum = startObjNum + i;

      // Don't overwrite newer entries (first xref section has priority)
      if (!xref.containsKey(objNum)) {
        xref[objNum] = XrefEntry(
          objNum: objNum,
          genNum: genNum,
          offset: entryOffset,
          inUse: inUse,
        );
      }

      pos = entryMatch.end;
      // Skip EOL
      while (pos < pdf.length &&
          (pdf.codeUnitAt(pos) == 10 ||
              pdf.codeUnitAt(pos) == 13 ||
              pdf.codeUnitAt(pos) == 32)) {
        pos++;
      }
    }
  }

  // Parse trailer
  final trailerMatch = RegExp(
    r'trailer\s*<<([\s\S]*?)>>',
  ).firstMatch(pdf.substring(offset));
  final trailerStr = trailerMatch != null
      ? '<<${trailerMatch.group(1)!}>>'
      : null;
  final prevOffset = trailerStr != null
      ? _extractIntValue(trailerStr, '/Prev')
      : null;

  return _XrefResult(trailerStr, prevOffset);
}

_XrefResult _parseXrefStream(String pdf, int offset, Map<int, XrefEntry> xref) {
  // Xref stream: the xref is encoded as a stream object
  // For now, try to extract /Root, /Size from the stream object's dictionary
  // and parse the embedded xref data
  //
  // Minimal handling: extract trailer-equivalent values from the stream dict
  final dict = readObjectDictAtOffset(pdf, offset);

  final rootRef = _extractRef(dict, '/Root');
  final size = _extractIntValue(dict, '/Size');
  final prevOffset = _extractIntValue(dict, '/Prev');

  // For xref streams, we can't easily decode the compressed xref entries
  // without a full Flate decoder. Fall back to scanning for objects.
  if (xref.isEmpty && rootRef != null) {
    _scanForObjects(pdf, xref);
  }

  // Build a pseudo-trailer string
  final trailer = StringBuffer('<<');
  if (size != null) trailer.write(' /Size $size');
  if (rootRef != null) {
    trailer.write(' /Root ${rootRef.objNum} ${rootRef.genNum} R');
  }
  if (prevOffset != null) trailer.write(' /Prev $prevOffset');
  trailer.write(' >>');

  return _XrefResult(trailer.toString(), prevOffset);
}

/// Fallback: scan entire PDF for "N G obj" patterns to build xref.
void _scanForObjects(String pdf, Map<int, XrefEntry> xref) {
  final pattern = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
  for (final match in pattern.allMatches(pdf)) {
    final objNum = int.parse(match.group(1)!);
    final genNum = int.parse(match.group(2)!);
    if (!xref.containsKey(objNum)) {
      xref[objNum] = XrefEntry(
        objNum: objNum,
        genNum: genNum,
        offset: match.start,
        inUse: true,
      );
    }
  }
}

// ─── Page Resolution ────────────────────────────────────────────────────────

int? _findLastPageObjNum(
  String pdf,
  PdfRef pagesRef,
  Map<int, XrefEntry> xref,
) {
  try {
    final pagesDict = readObjectDict(pdf, pagesRef, xref);
    // /Kids [ref1 ref2 ... refN]
    final kidsMatch = RegExp(
      r'/Kids\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(pagesDict);
    if (kidsMatch == null) return null;

    final kidsStr = kidsMatch.group(1)!;
    final refs = RegExp(r'(\d+)\s+(\d+)\s+R').allMatches(kidsStr).toList();
    if (refs.isEmpty) return null;

    // Take the last kid — it might be a page or a pages node
    final lastKid = PdfRef(
      int.parse(refs.last.group(1)!),
      int.parse(refs.last.group(2)!),
    );

    // Check if it's a /Pages node (recurse) or a /Page
    final kidDict = readObjectDict(pdf, lastKid, xref);
    if (kidDict.contains('/Type /Pages')) {
      return _findLastPageObjNum(pdf, lastKid, xref);
    }
    return lastKid.objNum;
  } catch (e) {
    _log.w('Could not find last page: $e');
    return null;
  }
}

// ─── Dictionary Helpers ─────────────────────────────────────────────────────

/// Extract an integer value from a PDF dictionary string.
int? _extractIntValue(String dict, String key) {
  final match = RegExp('${RegExp.escape(key)}\\s+(\\d+)').firstMatch(dict);
  return match != null ? int.tryParse(match.group(1)!) : null;
}

/// Extract an indirect reference from a PDF dictionary string.
PdfRef? _extractRef(String dict, String key) {
  final match = RegExp(
    '${RegExp.escape(key)}\\s+(\\d+)\\s+(\\d+)\\s+R',
  ).firstMatch(dict);
  if (match == null) return null;
  return PdfRef(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// Find the matching ">>" for a "<<" at position [start].
int _findMatchingDictEnd(String pdf, int start) {
  var depth = 0;
  var i = start;
  while (i < pdf.length - 1) {
    if (pdf[i] == '<' && pdf[i + 1] == '<') {
      depth++;
      i += 2;
    } else if (pdf[i] == '>' && pdf[i + 1] == '>') {
      depth--;
      if (depth == 0) return i;
      i += 2;
    } else {
      i++;
    }
  }
  // Fallback: return end of string
  return pdf.length - 2;
}

/// Extract a Name value (e.g., "/Filter /Adobe.PPKLite" → "Adobe.PPKLite").
String? extractNameValue(String dict, String key) {
  final match = RegExp('${RegExp.escape(key)}\\s+/(\\S+)').firstMatch(dict);
  return match?.group(1);
}

/// Extract a string value in parentheses (e.g., "/T (Field Name)" → "Field Name").
String? extractStringValue(String dict, String key) {
  final match = RegExp(
    '${RegExp.escape(key)}\\s*\\(([^)]*)\\)',
  ).firstMatch(dict);
  return match?.group(1);
}

/// Extract a Rect array (e.g., "/Rect [0 0 200 50]" → [0.0, 0.0, 200.0, 50.0]).
List<double>? extractRect(String dict) {
  final match = RegExp(r'/Rect\s*\[\s*([^\]]+)\]').firstMatch(dict);
  if (match == null) return null;
  final parts = match.group(1)!.trim().split(RegExp(r'\s+'));
  if (parts.length != 4) return null;
  return parts.map(double.parse).toList();
}

/// Find all indirect references in a string.
List<PdfRef> findAllRefs(String str) {
  return RegExp(r'(\d+)\s+(\d+)\s+R')
      .allMatches(str)
      .map((m) => PdfRef(int.parse(m.group(1)!), int.parse(m.group(2)!)))
      .toList();
}
