// SignBridge — X.509 certificate DER parser
//
// Extracts fields needed for CMS construction and cert matching:
//   - Subject CN (Common Name) for certId matching
//   - Issuer (DER-encoded) for SignerInfo.sid
//   - Serial number for SignerInfo.sid
//   - tbsCertificate (DER) for signingCertificateV2 hash
//
// Does NOT validate signatures or chain — the card is trusted.

import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';

/// Parsed fields from an X.509 certificate.
class CertificateInfo {
  /// Raw DER bytes of the full certificate.
  final Uint8List derBytes;

  /// Raw DER bytes of the TBSCertificate (first element of the SEQUENCE).
  final Uint8List tbsCertificateDer;

  /// Issuer as raw DER-encoded SEQUENCE (for IssuerAndSerialNumber).
  final Uint8List issuerDer;

  /// Serial number as BigInt.
  final BigInt serialNumber;

  /// Subject Common Name (CN), or null if not present.
  final String? subjectCn;

  /// Issuer Common Name (CN), or null if not present.
  final String? issuerCn;

  /// Signature algorithm OID from TBSCertificate.
  final String? signatureAlgorithmOid;

  CertificateInfo({
    required this.derBytes,
    required this.tbsCertificateDer,
    required this.issuerDer,
    required this.serialNumber,
    this.subjectCn,
    this.issuerCn,
    this.signatureAlgorithmOid,
  });
}

/// Parse a DER-encoded X.509 certificate.
///
/// X.509 structure:
/// ```
/// Certificate ::= SEQUENCE {
///   tbsCertificate      TBSCertificate,       -- SEQUENCE
///   signatureAlgorithm  AlgorithmIdentifier,   -- SEQUENCE
///   signatureValue      BIT STRING
/// }
///
/// TBSCertificate ::= SEQUENCE {
///   version         [0] EXPLICIT INTEGER DEFAULT v1,
///   serialNumber         INTEGER,
///   signature            AlgorithmIdentifier,
///   issuer               Name (SEQUENCE of SETs of SEQUENCE),
///   validity             SEQUENCE { notBefore, notAfter },
///   subject              Name,
///   ...
/// }
/// ```
CertificateInfo parseCertificate(Uint8List derBytes) {
  final parser = ASN1Parser(derBytes);
  final cert = parser.nextObject() as ASN1Sequence;
  final elements = cert.elements;
  if (elements.length < 3) {
    throw FormatException('Invalid X.509 certificate: expected 3 elements');
  }

  // TBSCertificate
  final tbsCert = elements[0] as ASN1Sequence;
  final tbsDer = _extractDerBytes(derBytes, tbsCert);

  // Parse TBSCertificate fields
  final tbsElements = tbsCert.elements;
  var idx = 0;

  // version is [0] EXPLICIT — tagged, optional
  BigInt serialNumber;
  if (tbsElements[idx].tag == 0xA0) {
    // version present
    idx++;
    serialNumber = (tbsElements[idx] as ASN1Integer).valueAsBigInteger;
    idx++;
  } else {
    // version absent (v1 default)
    serialNumber = (tbsElements[idx] as ASN1Integer).valueAsBigInteger;
    idx++;
  }

  // signature AlgorithmIdentifier
  String? sigAlgOid;
  if (tbsElements[idx] is ASN1Sequence) {
    final algSeq = tbsElements[idx] as ASN1Sequence;
    if (algSeq.elements.isNotEmpty &&
        algSeq.elements[0] is ASN1ObjectIdentifier) {
      sigAlgOid = (algSeq.elements[0] as ASN1ObjectIdentifier).identifier;
    }
  }
  idx++;

  // issuer Name
  final issuerObj = tbsElements[idx];
  final issuerDer = _extractDerBytes(derBytes, issuerObj);
  final issuerCn = _extractCn(issuerObj);
  idx++;

  // validity (skip)
  idx++;

  // subject Name
  final subjectObj = tbsElements[idx];
  final subjectCn = _extractCn(subjectObj);

  return CertificateInfo(
    derBytes: derBytes,
    tbsCertificateDer: tbsDer,
    issuerDer: issuerDer,
    serialNumber: serialNumber,
    subjectCn: subjectCn,
    issuerCn: issuerCn,
    signatureAlgorithmOid: sigAlgOid,
  );
}

/// Extract Common Name (OID 2.5.4.3) from a Name (SEQUENCE of SETs of SEQUENCE).
String? _extractCn(ASN1Object nameObj) {
  // Name ::= SEQUENCE OF RelativeDistinguishedName
  // RDN  ::= SET OF AttributeTypeAndValue
  // ATAV ::= SEQUENCE { type OID, value ANY }
  if (nameObj is! ASN1Sequence) return null;
  for (final rdn in nameObj.elements) {
    if (rdn is! ASN1Set) continue;
    for (final atav in rdn.elements) {
      if (atav is! ASN1Sequence) continue;
      if (atav.elements.length < 2) continue;
      final oid = atav.elements[0];
      if (oid is! ASN1ObjectIdentifier) continue;
      // OID 2.5.4.3 = Common Name
      if (oid.identifier == '2.5.4.3') {
        final value = atav.elements[1];
        // Value can be UTF8String, PrintableString, etc.
        return _extractStringValue(value);
      }
    }
  }
  return null;
}

/// Extract string value from various ASN.1 string types.
String? _extractStringValue(ASN1Object obj) {
  if (obj is ASN1UTF8String) return obj.utf8StringValue;
  if (obj is ASN1PrintableString) return obj.stringValue;
  if (obj is ASN1IA5String) return obj.stringValue;
  // Fallback: decode value bytes as UTF-8
  try {
    final bytes = obj.valueBytes();
    return String.fromCharCodes(bytes);
  } catch (_) {
    return null;
  }
}

/// Extract DER bytes for a sub-object within a larger DER structure.
///
/// asn1lib records the offset and total encoded length. We use
/// encodedBytes which gives us the full TLV encoding of that element.
Uint8List _extractDerBytes(Uint8List fullDer, ASN1Object obj) {
  // The object's encodedBytes contains the full TLV for this element.
  // However, asn1lib may share the backing buffer. We need a clean copy.
  final encoded = obj.encodedBytes;
  // totalEncodedByteLength gives us the actual size
  final len = obj.totalEncodedByteLength;
  return Uint8List.fromList(encoded.sublist(0, len));
}

/// Normalize a string for diacritics-insensitive matching.
/// Mirrors the desktop Python host's `_normalize_for_matching()`.
String normalizeForMatching(String s) {
  // Lowercase
  var result = s.toLowerCase();
  // Common Romanian diacritics → ASCII
  const diacriticMap = {
    'ă': 'a',
    'â': 'a',
    'î': 'i',
    'ș': 's',
    'ş': 's',
    'ț': 't',
    'ţ': 't',
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ö': 'o',
    'ä': 'a',
  };
  for (final entry in diacriticMap.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  // Collapse whitespace
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return result;
}

/// Check if a certificate's CN matches the requested certId.
bool certIdMatches(CertificateInfo cert, String certId) {
  if (cert.subjectCn == null) return false;
  return normalizeForMatching(cert.subjectCn!) == normalizeForMatching(certId);
}
