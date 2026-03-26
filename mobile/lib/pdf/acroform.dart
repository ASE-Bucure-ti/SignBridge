// SignBridge — AcroForm handling
//
// Finds or creates signature fields in the PDF's interactive form:
//   - Locate existing /AcroForm in the catalog
//   - Find signature field matching pdfOptions.label (/T name)
//   - Extract /Rect coordinates from existing fields
//   - Create new signature field + widget annotation if not found
//   - Ensure /SigFlags 3 (SignaturesExist + AppendOnly)
//   - Update /Fields array
//
// All modifications happen via incremental update — original PDF is untouched.

import 'parser.dart';

/// Default signature rectangle [x1 y1 x2 y2] in points.
/// Bottom-left of first page, 200×50 pt box.
const defaultSigRect = [36.0, 36.0, 236.0, 86.0];

/// Information about a signature field found or to be created.
class SigFieldInfo {
  /// Object number of the existing widget annotation (null if new).
  final int? existingWidgetObjNum;

  /// Rectangle coordinates [x1, y1, x2, y2] in PDF points.
  final List<double> rect;

  /// The page object number this field is on.
  final int pageObjNum;

  /// Field name (/T value).
  final String fieldName;

  SigFieldInfo({
    this.existingWidgetObjNum,
    required this.rect,
    required this.pageObjNum,
    required this.fieldName,
  });

  bool get isNew => existingWidgetObjNum == null;
}

/// Search for an existing signature field by label, or determine placement for a new one.
///
/// If [label] is non-null and a matching field is found, returns its info.
/// Otherwise, returns info for creating a new field on the last page.
SigFieldInfo findOrPlanSigField(PdfInfo pdf, String? label) {
  final pdfStr = String.fromCharCodes(pdf.bytes);

  // Try to find existing field by label
  if (label != null && label.isNotEmpty) {
    final found = _findFieldByLabel(pdfStr, pdf, label);
    if (found != null) return found;
  }

  // No existing field — plan a new one on the last page
  final pageObjNum = pdf.lastPageObjNum ?? 1;
  final fieldName = label ?? 'Signature1';

  return SigFieldInfo(
    rect: List.of(defaultSigRect),
    pageObjNum: pageObjNum,
    fieldName: fieldName,
  );
}

/// Build the AcroForm dictionary string for the catalog update.
///
/// [existingFieldRefs] — refs to existing /Fields entries (preserved).
/// [newFieldRef] — ref to the new signature field (if creating one).
/// [sigFlags] — typically 3 (SignaturesExist | AppendOnly).
String buildAcroFormDict({
  List<PdfRef> existingFieldRefs = const [],
  PdfRef? newFieldRef,
  int sigFlags = 3,
}) {
  final fields = StringBuffer('[');
  for (final ref in existingFieldRefs) {
    fields.write(' ${ref.objNum} ${ref.genNum} R');
  }
  if (newFieldRef != null) {
    fields.write(' ${newFieldRef.objNum} ${newFieldRef.genNum} R');
  }
  fields.write(' ]');

  return '<< /SigFlags $sigFlags /Fields $fields >>';
}

/// Extract existing /Fields references from an AcroForm dictionary.
List<PdfRef> extractExistingFieldRefs(PdfInfo pdf) {
  String? acroFormDict;

  if (pdf.acroFormRef != null) {
    final pdfStr = String.fromCharCodes(pdf.bytes);
    try {
      acroFormDict = readObjectDict(pdfStr, pdf.acroFormRef!, pdf.xref);
    } catch (_) {
      return [];
    }
  } else if (pdf.acroFormInline != null) {
    acroFormDict = pdf.acroFormInline;
  }

  if (acroFormDict == null) return [];

  // Extract /Fields [ ref1 ref2 ... ]
  final fieldsMatch = RegExp(
    r'/Fields\s*\[(.*?)\]',
    dotAll: true,
  ).firstMatch(acroFormDict);
  if (fieldsMatch == null) return [];

  return findAllRefs(fieldsMatch.group(1)!);
}

// ─── Internal ───────────────────────────────────────────────────────────────

SigFieldInfo? _findFieldByLabel(String pdfStr, PdfInfo pdf, String label) {
  // Scan all objects in xref for signature fields with matching /T
  for (final entry in pdf.xref.values) {
    if (!entry.inUse) continue;
    try {
      final dict = readObjectDictAtOffset(pdfStr, entry.offset);
      // Check if this is a signature field or widget with /FT /Sig
      if (!dict.contains('/FT /Sig') && !dict.contains('/FT/Sig')) continue;

      // Check /T (field name)
      final fieldName = extractStringValue(dict, '/T');
      if (fieldName == null) continue;
      if (fieldName != label) continue;

      // Found matching field — extract rect and page
      final rect = extractRect(dict) ?? List.of(defaultSigRect);
      final pageObjNum =
          _resolvePageForWidget(pdfStr, pdf, entry.objNum) ??
          pdf.lastPageObjNum ??
          1;

      return SigFieldInfo(
        existingWidgetObjNum: entry.objNum,
        rect: rect,
        pageObjNum: pageObjNum,
        fieldName: label,
      );
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Try to find which page a widget annotation belongs to.
int? _resolvePageForWidget(String pdfStr, PdfInfo pdf, int widgetObjNum) {
  // Check each page's /Annots array for a reference to this widget
  if (pdf.pagesRef == null) return null;

  try {
    final pagesDict = readObjectDict(pdfStr, pdf.pagesRef!, pdf.xref);
    final kidsMatch = RegExp(
      r'/Kids\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(pagesDict);
    if (kidsMatch == null) return null;

    final pageRefs = findAllRefs(kidsMatch.group(1)!);
    for (final pageRef in pageRefs) {
      final pageDict = readObjectDict(pdfStr, pageRef, pdf.xref);
      final annotsMatch = RegExp(
        r'/Annots\s*\[(.*?)\]',
        dotAll: true,
      ).firstMatch(pageDict);
      if (annotsMatch == null) continue;

      final annotRefs = findAllRefs(annotsMatch.group(1)!);
      for (final annotRef in annotRefs) {
        if (annotRef.objNum == widgetObjNum) {
          return pageRef.objNum;
        }
      }
    }
  } catch (_) {
    // Fall through
  }
  return null;
}
