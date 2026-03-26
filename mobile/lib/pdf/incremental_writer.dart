// SignBridge — PDF incremental update writer
//
// Appends new objects to the PDF without modifying the original bytes.
// This is the standard PDF incremental update mechanism (§7.5.6):
//
//   [original PDF bytes]
//   [new/modified objects]
//   [new xref table]
//   trailer << /Size N /Prev oldStartxref /Root ... >>
//   startxref
//   <offset-of-new-xref>
//   %%EOF
//
// Used to add: signature dictionary, widget annotation, appearance XObject,
// updated catalog with /AcroForm, and optionally updated page /Annots.
//
// The entire signing pipeline:
//   1. parsePdf()           → structural info
//   2. findOrPlanSigField() → where to place the signature
//   3. buildIncremental()   → append objects + xref + trailer
//   4. prepareForSigning()  → compute ByteRange digest
//   5. (NFC card signs the digest → CMS envelope)
//   6. embedSignature()     → patch CMS into /Contents
//
// References: PDF Reference 1.7, §7.5.6

import 'dart:convert';
import 'dart:typed_data';
import 'package:logger/logger.dart';

import 'acroform.dart';
import 'appearance.dart';
import 'parser.dart';
import 'signer.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// Result of building an incremental update.
class IncrementalUpdate {
  /// The full PDF (original + appended bytes).
  final Uint8List bytes;

  /// Object numbers allocated for new objects.
  final int sigDictObjNum;
  final int? widgetObjNum;
  final int? appearanceObjNum;
  final int? catalogObjNum;
  final int? pageObjNum;
  final int? acroFormObjNum;

  IncrementalUpdate({
    required this.bytes,
    required this.sigDictObjNum,
    this.widgetObjNum,
    this.appearanceObjNum,
    this.catalogObjNum,
    this.pageObjNum,
    this.acroFormObjNum,
  });
}

/// Build an incremental update that adds a digital signature to the PDF.
///
/// [pdf]           — parsed PDF info from [parsePdf].
/// [sigField]      — signature field info from [findOrPlanSigField].
/// [signerName]    — CN from the signer's certificate.
/// [signingTime]   — DateTime for /M and appearance.
/// [reason]        — /Reason value.
/// [location]      — /Location value.
IncrementalUpdate buildIncremental({
  required PdfInfo pdf,
  required SigFieldInfo sigField,
  required String signerName,
  required DateTime signingTime,
  String reason = 'Signed by SignBridge',
  String location = 'SignBridge Mobile',
}) {
  final originalBytes = pdf.bytes;
  final pdfStr = latin1.decode(originalBytes);
  final buf = BytesBuilder();
  buf.add(originalBytes);

  // Ensure the original PDF ends with a newline
  if (originalBytes.isNotEmpty && originalBytes.last != 0x0A) {
    buf.add(latin1.encode('\n'));
  }

  // Track new objects: (objNum, byteOffset, content)
  final newObjects = <_NewObject>[];
  var nextObjNum = pdf.size;

  // ── 1. Signature dictionary object ──
  final sigDictObjNum = nextObjNum++;
  final timeStr = formatPdfDate(signingTime);
  final sigDictBody = buildSigDict(
    signingTime: timeStr,
    reason: reason,
    location: location,
  );

  newObjects.add(_NewObject(sigDictObjNum, sigDictBody));

  // ── 2. Appearance XObject (for visible signature) ──
  int? apObjNum;
  String? apXObjectBody;
  final appearance = buildAppearance(
    signerName: signerName,
    signingTime: timeStr,
    rect: sigField.rect,
  );
  apObjNum = nextObjNum++;
  apXObjectBody = buildAppearanceXObject(appearance);
  newObjects.add(_NewObject(apObjNum, apXObjectBody));

  // ── 3. Widget annotation (if new field) ──
  int? widgetObjNum;
  if (sigField.isNew) {
    widgetObjNum = nextObjNum++;
    final widgetBody = _buildWidgetAnnotation(
      sigField: sigField,
      sigDictObjNum: sigDictObjNum,
      appearanceObjNum: apObjNum,
    );
    newObjects.add(_NewObject(widgetObjNum, widgetBody));
  } else {
    // Existing widget — update it to point to our sig dict and appearance
    widgetObjNum = sigField.existingWidgetObjNum;
    if (widgetObjNum != null) {
      final widgetBody = _buildWidgetAnnotation(
        sigField: sigField,
        sigDictObjNum: sigDictObjNum,
        appearanceObjNum: apObjNum,
      );
      // Re-emit the widget object with the same obj number
      newObjects.add(_NewObject(widgetObjNum, widgetBody));
    }
  }

  // ── 4. Updated page object (add widget to /Annots if new) ──
  int? updatedPageObjNum;
  if (sigField.isNew && widgetObjNum != null) {
    updatedPageObjNum = sigField.pageObjNum;
    final pageBody = _buildUpdatedPage(
      pdfStr: pdfStr,
      pdf: pdf,
      pageObjNum: updatedPageObjNum,
      newAnnotRef: PdfRef(widgetObjNum, 0),
    );
    if (pageBody != null) {
      newObjects.add(_NewObject(updatedPageObjNum, pageBody));
    }
  }

  // ── 5. AcroForm object (new or updated) ──
  int? acroFormObjNum;
  final existingFieldRefs = extractExistingFieldRefs(pdf);
  final fieldRef = PdfRef(widgetObjNum ?? sigDictObjNum, 0);
  final acroFormBody = buildAcroFormDict(
    existingFieldRefs: existingFieldRefs,
    newFieldRef: sigField.isNew ? fieldRef : null,
    sigFlags: 3,
  );

  if (pdf.acroFormRef != null) {
    // Re-emit existing AcroForm object
    acroFormObjNum = pdf.acroFormRef!.objNum;
    newObjects.add(_NewObject(acroFormObjNum, acroFormBody));
  } else {
    // Create new AcroForm object
    acroFormObjNum = nextObjNum++;
    newObjects.add(_NewObject(acroFormObjNum, acroFormBody));
  }

  // ── 6. Updated catalog (point to AcroForm) ──
  int? catalogObjNum;
  if (pdf.acroFormRef == null || pdf.acroFormInline != null) {
    // Need to update catalog to reference the new AcroForm object
    catalogObjNum = pdf.rootRef.objNum;
    final catalogBody = _buildUpdatedCatalog(
      pdf: pdf,
      acroFormObjNum: acroFormObjNum,
    );
    newObjects.add(_NewObject(catalogObjNum, catalogBody));
  }

  // ── Write new objects ──
  final objectOffsets = <int, int>{};
  for (final obj in newObjects) {
    objectOffsets[obj.objNum] = buf.length;
    final objStr = '${obj.objNum} 0 obj\n${obj.body}\nendobj\n';
    buf.add(latin1.encode(objStr));
  }

  // ── Write new xref table ──
  final newXrefOffset = buf.length;
  final xrefBuf = StringBuffer();
  xrefBuf.writeln('xref');

  // Group consecutive object numbers into subsections
  final sortedObjNums = objectOffsets.keys.toList()..sort();
  var i = 0;
  while (i < sortedObjNums.length) {
    final subsectionStart = sortedObjNums[i];
    var subsectionEnd = subsectionStart;
    while (i + 1 < sortedObjNums.length &&
        sortedObjNums[i + 1] == subsectionEnd + 1) {
      i++;
      subsectionEnd = sortedObjNums[i];
    }
    final count = subsectionEnd - subsectionStart + 1;
    xrefBuf.writeln('$subsectionStart $count');
    for (var n = subsectionStart; n <= subsectionEnd; n++) {
      final offset = objectOffsets[n]!;
      xrefBuf.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
    }
    i++;
  }

  buf.add(latin1.encode(xrefBuf.toString()));

  // ── Write trailer ──
  final newSize = nextObjNum;
  final trailerBuf = StringBuffer();
  trailerBuf.writeln('trailer');
  trailerBuf.writeln('<<');
  trailerBuf.writeln('  /Size $newSize');
  trailerBuf.writeln('  /Root ${pdf.rootRef.objNum} ${pdf.rootRef.genNum} R');
  if (pdf.infoRef != null) {
    trailerBuf.writeln(
      '  /Info ${pdf.infoRef!.objNum} ${pdf.infoRef!.genNum} R',
    );
  }
  trailerBuf.writeln('  /Prev ${pdf.startxrefOffset}');
  trailerBuf.writeln('>>');
  trailerBuf.writeln('startxref');
  trailerBuf.writeln('$newXrefOffset');
  trailerBuf.writeln('%%EOF');

  buf.add(latin1.encode(trailerBuf.toString()));

  _log.i(
    'Incremental update: ${newObjects.length} objects, '
    'new size=$newSize, xref@$newXrefOffset',
  );

  return IncrementalUpdate(
    bytes: buf.toBytes(),
    sigDictObjNum: sigDictObjNum,
    widgetObjNum: widgetObjNum,
    appearanceObjNum: apObjNum,
    catalogObjNum: catalogObjNum,
    pageObjNum: updatedPageObjNum,
    acroFormObjNum: acroFormObjNum,
  );
}

// ─── Object Builders ────────────────────────────────────────────────────────

class _NewObject {
  final int objNum;
  final String body;
  _NewObject(this.objNum, this.body);
}

/// Build a widget annotation dictionary for a signature field.
String _buildWidgetAnnotation({
  required SigFieldInfo sigField,
  required int sigDictObjNum,
  required int? appearanceObjNum,
}) {
  final r = sigField.rect;
  final buf = StringBuffer();
  buf.writeln('<<');
  buf.writeln('  /Type /Annot');
  buf.writeln('  /Subtype /Widget');
  buf.writeln('  /FT /Sig');
  buf.writeln('  /T (${sigField.fieldName})');
  buf.writeln('  /V $sigDictObjNum 0 R');
  buf.writeln('  /F 132'); // Print + Locked
  buf.writeln(
    '  /Rect [${_fmtD(r[0])} ${_fmtD(r[1])} ${_fmtD(r[2])} ${_fmtD(r[3])}]',
  );
  buf.writeln('  /P ${sigField.pageObjNum} 0 R');
  if (appearanceObjNum != null) {
    buf.writeln('  /AP << /N $appearanceObjNum 0 R >>');
  }
  buf.writeln('>>');
  return buf.toString();
}

/// Build an updated page dictionary with a new annotation reference.
String? _buildUpdatedPage({
  required String pdfStr,
  required PdfInfo pdf,
  required int pageObjNum,
  required PdfRef newAnnotRef,
}) {
  final entry = pdf.xref[pageObjNum];
  if (entry == null) return null;

  try {
    final pageDict = readObjectDictAtOffset(pdfStr, entry.offset);

    // Extract existing /Annots references
    final annotsMatch = RegExp(
      r'/Annots\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(pageDict);
    final existingAnnots = annotsMatch != null
        ? findAllRefs(annotsMatch.group(1)!)
        : <PdfRef>[];

    // Build new /Annots array
    final annotsBuf = StringBuffer('[');
    for (final ref in existingAnnots) {
      annotsBuf.write(' ${ref.objNum} ${ref.genNum} R');
    }
    annotsBuf.write(' ${newAnnotRef.objNum} ${newAnnotRef.genNum} R');
    annotsBuf.write(' ]');

    // Rebuild the page dictionary
    // Remove old /Annots, add new /Annots
    var newDict = pageDict;
    if (annotsMatch != null) {
      newDict = newDict.replaceFirst(
        RegExp(r'/Annots\s*\[.*?\]', dotAll: true),
        '/Annots $annotsBuf',
      );
    } else {
      // Insert /Annots before the closing >>
      final lastGt = newDict.lastIndexOf('>>');
      if (lastGt > 0) {
        newDict =
            '${newDict.substring(0, lastGt)}  /Annots $annotsBuf\n${newDict.substring(lastGt)}';
      }
    }

    return newDict;
  } catch (e) {
    _log.w('Could not update page $pageObjNum: $e');
    return null;
  }
}

/// Build an updated catalog dictionary pointing to the AcroForm.
String _buildUpdatedCatalog({
  required PdfInfo pdf,
  required int acroFormObjNum,
}) {
  var catalogDict = pdf.catalogDict;

  // Remove any existing inline /AcroForm
  catalogDict = catalogDict.replaceFirst(
    RegExp(r'/AcroForm\s*<<[^>]*(?:<<[^>]*>>[^>]*)*>>'),
    '',
  );

  // Remove any existing /AcroForm reference
  catalogDict = catalogDict.replaceFirst(
    RegExp(r'/AcroForm\s+\d+\s+\d+\s+R'),
    '',
  );

  // Insert /AcroForm reference before closing >>
  final lastGt = catalogDict.lastIndexOf('>>');
  if (lastGt > 0) {
    catalogDict =
        '${catalogDict.substring(0, lastGt)}  /AcroForm $acroFormObjNum 0 R\n${catalogDict.substring(lastGt)}';
  }

  return catalogDict;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Format a double for PDF output.
String _fmtD(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}
