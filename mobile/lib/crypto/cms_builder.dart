// SignBridge — CMS/PKCS#7 SignedData builder
//
// Builds a complete CMS (RFC 5652) detached signature envelope
// suitable for embedding in a PDF (/SubFilter /adbe.pkcs7.detached).
//
// ASN.1 structure produced:
//
//   ContentInfo {
//     contentType  OID  id-signedData (1.2.840.113549.1.7.2)
//     content [0]  SignedData {
//       version              INTEGER 1
//       digestAlgorithms     SET OF AlgorithmIdentifier
//       encapContentInfo     EncapsulatedContentInfo { id-data }  (detached → no eContent)
//       certificates    [0]  SET OF Certificate
//       signerInfos          SET OF SignerInfo {
//         version              INTEGER 1
//         sid                  IssuerAndSerialNumber
//         digestAlgorithm      AlgorithmIdentifier
//         signedAttrs     [0]  SET OF Attribute
//         signatureAlgorithm   AlgorithmIdentifier
//         signature            OCTET STRING
//         unsignedAttrs   [1]  SET OF Attribute  (optional — TSA timestamp)
//       }
//     }
//   }
//
// The card signs the DER-encoded signedAttributes (re-tagged as SET).
// This file builds everything EXCEPT the raw signature (that comes from the card).
//
// Flow:
//   1. buildSignedAttributes(contentDigest, cert, signingTime)
//   2. Hash the DER-encoded signedAttributes → send to card (INTERNAL AUTHENTICATE)
//   3. buildCms(signedAttrsDer, signature, cert, digestOid, sigAlgOid, tsaToken?)

import 'dart:typed_data';
import 'package:asn1lib/asn1lib.dart';
import 'hash.dart';
import 'certificate.dart';

// ─── OID Constants ──────────────────────────────────────────────────────────

/// id-data (1.2.840.113549.1.7.1) — CMS data content type
final _oidData = [1, 2, 840, 113549, 1, 7, 1];

/// id-signedData (1.2.840.113549.1.7.2)
final _oidSignedData = [1, 2, 840, 113549, 1, 7, 2];

/// id-contentType (1.2.840.113549.1.9.3) — signed attribute
final _oidContentType = [1, 2, 840, 113549, 1, 9, 3];

/// id-messageDigest (1.2.840.113549.1.9.4) — signed attribute
final _oidMessageDigest = [1, 2, 840, 113549, 1, 9, 4];

/// id-signingTime (1.2.840.113549.1.9.5) — signed attribute
final _oidSigningTime = [1, 2, 840, 113549, 1, 9, 5];

/// id-aa-signingCertificateV2 (1.2.840.113549.1.9.16.2.47)
final _oidSigningCertificateV2 = [1, 2, 840, 113549, 1, 9, 16, 2, 47];

/// id-aa-timeStampToken (1.2.840.113549.1.9.16.2.14)
final _oidTimeStampToken = [1, 2, 840, 113549, 1, 9, 16, 2, 14];

/// id-sha256 (2.16.840.1.101.3.4.2.1)
final _oidSha256 = [2, 16, 840, 1, 101, 3, 4, 2, 1];

/// id-sha384 (2.16.840.1.101.3.4.2.2)
final _oidSha384 = [2, 16, 840, 1, 101, 3, 4, 2, 2];

/// id-ecdsaWithSHA256 (1.2.840.10045.4.3.2)
final _oidEcdsaSha256 = [1, 2, 840, 10045, 4, 3, 2];

/// id-ecdsaWithSHA384 (1.2.840.10045.4.3.3)
final _oidEcdsaSha384 = [1, 2, 840, 10045, 4, 3, 3];

/// sha256WithRSAEncryption (1.2.840.113549.1.1.11)
final _oidRsaSha256 = [1, 2, 840, 113549, 1, 1, 11];

/// sha384WithRSAEncryption (1.2.840.113549.1.1.12)
final _oidRsaSha384 = [1, 2, 840, 113549, 1, 1, 12];

// ─── Digest Algorithm Selection ─────────────────────────────────────────────

/// Supported digest algorithms for the CMS envelope.
enum CmsDigestAlgorithm { sha256, sha384 }

/// Supported signature algorithms (determined by card's key type).
enum CmsSignatureAlgorithm { ecdsaSha256, ecdsaSha384, rsaSha256, rsaSha384 }

List<int> _digestOid(CmsDigestAlgorithm alg) => switch (alg) {
  CmsDigestAlgorithm.sha256 => _oidSha256,
  CmsDigestAlgorithm.sha384 => _oidSha384,
};

List<int> _signatureOid(CmsSignatureAlgorithm alg) => switch (alg) {
  CmsSignatureAlgorithm.ecdsaSha256 => _oidEcdsaSha256,
  CmsSignatureAlgorithm.ecdsaSha384 => _oidEcdsaSha384,
  CmsSignatureAlgorithm.rsaSha256 => _oidRsaSha256,
  CmsSignatureAlgorithm.rsaSha384 => _oidRsaSha384,
};

Uint8List _computeDigest(CmsDigestAlgorithm alg, Uint8List data) =>
    switch (alg) {
      CmsDigestAlgorithm.sha256 => sha256(data),
      CmsDigestAlgorithm.sha384 => sha384(data),
    };

// ─── Signed Attributes ─────────────────────────────────────────────────────

/// Build the SignedAttributes SET and return its DER encoding.
///
/// The returned bytes are tagged as SET (0x31) — the form that gets
/// hashed and sent to the card for signing.
///
/// [contentDigest] is the hash of the PDF byte-range content.
/// [cert] is the parsed signing certificate.
/// [signingTime] is the signing timestamp.
/// [digestAlgorithm] selects SHA-256 or SHA-384.
Uint8List buildSignedAttributes({
  required Uint8List contentDigest,
  required CertificateInfo cert,
  required DateTime signingTime,
  required CmsDigestAlgorithm digestAlgorithm,
}) {
  final attrs = <ASN1Object>[];

  // 1. contentType attribute
  attrs.add(
    _buildAttribute(_oidContentType, [
      ASN1ObjectIdentifier.fromComponents(_oidData),
    ]),
  );

  // 2. signingTime attribute
  attrs.add(
    _buildAttribute(_oidSigningTime, [_encodeSigningTime(signingTime)]),
  );

  // 3. messageDigest attribute
  attrs.add(
    _buildAttribute(_oidMessageDigest, [ASN1OctetString(contentDigest)]),
  );

  // 4. signingCertificateV2 attribute (RFC 5035)
  attrs.add(_buildSigningCertificateV2Attribute(cert, digestAlgorithm));

  // Encode as SET (tag 0x31) for hashing
  final set = ASN1Set();
  for (final attr in attrs) {
    set.add(attr);
  }

  final encoded = set.encodedBytes;
  // Ensure tag is 0x31 (SET) not 0xA0 (IMPLICIT [0])
  // asn1lib's ASN1Set should already use 0x31
  return Uint8List.fromList(encoded);
}

/// Build the complete CMS ContentInfo (DER-encoded).
///
/// Call this AFTER obtaining the raw signature from the card.
///
/// [signedAttributesDer] — the exact bytes returned by [buildSignedAttributes].
/// [signature] — raw signature bytes from INTERNAL AUTHENTICATE.
/// [cert] — the signing certificate.
/// [digestAlgorithm] — SHA-256 or SHA-384.
/// [signatureAlgorithm] — ECDSA-SHA384, RSA-SHA256, etc.
/// [tsaToken] — optional RFC 3161 timestamp token (DER-encoded).
Uint8List buildCms({
  required Uint8List signedAttributesDer,
  required Uint8List signature,
  required CertificateInfo cert,
  required CmsDigestAlgorithm digestAlgorithm,
  required CmsSignatureAlgorithm signatureAlgorithm,
  Uint8List? tsaToken,
}) {
  // ── SignerInfo ──
  final signerInfo = _buildSignerInfo(
    cert: cert,
    digestAlgorithm: digestAlgorithm,
    signatureAlgorithm: signatureAlgorithm,
    signedAttributesDer: signedAttributesDer,
    signature: signature,
    tsaToken: tsaToken,
  );

  // ── SignedData ──
  final signedData = _buildSignedData(
    digestAlgorithm: digestAlgorithm,
    certDer: cert.derBytes,
    signerInfo: signerInfo,
  );

  // ── ContentInfo ──
  return _buildContentInfo(signedData);
}

/// Hash the signed attributes for the card to sign.
Uint8List hashSignedAttributes(
  Uint8List signedAttributesDer,
  CmsDigestAlgorithm digestAlgorithm,
) {
  return _computeDigest(digestAlgorithm, signedAttributesDer);
}

// ─── Internal Builders ──────────────────────────────────────────────────────

/// ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT ANY }
Uint8List _buildContentInfo(Uint8List signedDataDer) {
  final builder = BytesBuilder();

  // contentType: id-signedData
  final oid = ASN1ObjectIdentifier.fromComponents(_oidSignedData).encodedBytes;

  // content [0] EXPLICIT — wrap signedData in context tag 0xA0
  final contentTagged = _wrapExplicitTag(0, signedDataDer);

  // SEQUENCE { oid, [0] signedData }
  final inner = BytesBuilder();
  inner.add(oid);
  inner.add(contentTagged);

  _writeSequence(builder, inner.toBytes());
  return builder.toBytes();
}

/// SignedData ::= SEQUENCE {
///   version, digestAlgorithms, encapContentInfo,
///   certificates [0] IMPLICIT, signerInfos
/// }
Uint8List _buildSignedData({
  required CmsDigestAlgorithm digestAlgorithm,
  required Uint8List certDer,
  required Uint8List signerInfo,
}) {
  final inner = BytesBuilder();

  // version INTEGER 1
  inner.add(ASN1Integer(BigInt.one).encodedBytes);

  // digestAlgorithms SET OF AlgorithmIdentifier
  final algIdDer = _buildAlgorithmIdentifier(_digestOid(digestAlgorithm));
  final algSet = BytesBuilder();
  _writeTag(algSet, 0x31, algIdDer); // SET
  inner.add(algSet.toBytes());

  // encapContentInfo (detached — no eContent)
  final encapInner = BytesBuilder();
  encapInner.add(ASN1ObjectIdentifier.fromComponents(_oidData).encodedBytes);
  final encap = BytesBuilder();
  _writeSequence(encap, encapInner.toBytes());
  inner.add(encap.toBytes());

  // certificates [0] IMPLICIT SET OF Certificate
  // Tag is 0xA0 (context, constructed, 0)
  final certTagged = BytesBuilder();
  _writeTag(certTagged, 0xA0, certDer);
  inner.add(certTagged.toBytes());

  // signerInfos SET OF SignerInfo
  final siSet = BytesBuilder();
  _writeTag(siSet, 0x31, signerInfo); // SET
  inner.add(siSet.toBytes());

  final result = BytesBuilder();
  _writeSequence(result, inner.toBytes());
  return result.toBytes();
}

/// SignerInfo ::= SEQUENCE {
///   version, sid, digestAlgorithm, signedAttrs [0],
///   signatureAlgorithm, signature, unsignedAttrs [1]
/// }
Uint8List _buildSignerInfo({
  required CertificateInfo cert,
  required CmsDigestAlgorithm digestAlgorithm,
  required CmsSignatureAlgorithm signatureAlgorithm,
  required Uint8List signedAttributesDer,
  required Uint8List signature,
  Uint8List? tsaToken,
}) {
  final inner = BytesBuilder();

  // version INTEGER 1
  inner.add(ASN1Integer(BigInt.one).encodedBytes);

  // sid: IssuerAndSerialNumber SEQUENCE { issuer, serial }
  final sidInner = BytesBuilder();
  sidInner.add(cert.issuerDer);
  sidInner.add(ASN1Integer(cert.serialNumber).encodedBytes);
  final sid = BytesBuilder();
  _writeSequence(sid, sidInner.toBytes());
  inner.add(sid.toBytes());

  // digestAlgorithm AlgorithmIdentifier
  inner.add(_buildAlgorithmIdentifier(_digestOid(digestAlgorithm)));

  // signedAttrs [0] IMPLICIT SET — re-tag from 0x31 to 0xA0
  final retagged = Uint8List.fromList(signedAttributesDer);
  retagged[0] = 0xA0; // re-tag: SET (0x31) → IMPLICIT [0] (0xA0)
  inner.add(retagged);

  // signatureAlgorithm AlgorithmIdentifier
  inner.add(_buildAlgorithmIdentifier(_signatureOid(signatureAlgorithm)));

  // signature OCTET STRING
  inner.add(ASN1OctetString(signature).encodedBytes);

  // unsignedAttrs [1] IMPLICIT SET (optional)
  if (tsaToken != null) {
    final unsignedAttrs = _buildAttribute(_oidTimeStampToken, [
      ASN1OctetString(tsaToken),
    ]);
    final unsignedSet = BytesBuilder();
    unsignedSet.add(unsignedAttrs.encodedBytes);
    final tagged = BytesBuilder();
    _writeTag(tagged, 0xA1, unsignedSet.toBytes());
    inner.add(tagged.toBytes());
  }

  final result = BytesBuilder();
  _writeSequence(result, inner.toBytes());
  return result.toBytes();
}

/// AlgorithmIdentifier ::= SEQUENCE { algorithm OID, parameters ANY OPTIONAL }
Uint8List _buildAlgorithmIdentifier(List<int> oid) {
  final inner = BytesBuilder();
  inner.add(ASN1ObjectIdentifier.fromComponents(oid).encodedBytes);
  // For SHA and ECDSA: parameters are absent or NULL
  // SHA-256/384 require explicit NULL parameters per RFC 5754
  if (_isShaOid(oid)) {
    inner.add(ASN1Null().encodedBytes);
  }
  // ECDSA: parameters absent (not NULL) per RFC 5753
  // RSA: parameters NULL
  if (_isRsaOid(oid)) {
    inner.add(ASN1Null().encodedBytes);
  }

  final result = BytesBuilder();
  _writeSequence(result, inner.toBytes());
  return result.toBytes();
}

bool _isShaOid(List<int> oid) =>
    _listEquals(oid, _oidSha256) || _listEquals(oid, _oidSha384);

bool _isRsaOid(List<int> oid) =>
    _listEquals(oid, _oidRsaSha256) || _listEquals(oid, _oidRsaSha384);

/// Build an Attribute SEQUENCE { attrType OID, attrValues SET OF ANY }.
ASN1Sequence _buildAttribute(List<int> oid, List<ASN1Object> values) {
  final seq = ASN1Sequence();
  seq.add(ASN1ObjectIdentifier.fromComponents(oid));
  final valSet = ASN1Set();
  for (final v in values) {
    valSet.add(v);
  }
  seq.add(valSet);
  return seq;
}

/// Build the signingCertificateV2 attribute (RFC 5035).
///
/// SigningCertificateV2 ::= SEQUENCE {
///   certs  SEQUENCE OF ESSCertIDv2
/// }
/// ESSCertIDv2 ::= SEQUENCE {
///   hashAlgorithm  AlgorithmIdentifier DEFAULT sha256,
///   certHash       OCTET STRING,
///   issuerSerial   IssuerSerial OPTIONAL
/// }
/// IssuerSerial ::= SEQUENCE {
///   issuer         GeneralNames,
///   serialNumber   CertificateSerialNumber
/// }
ASN1Sequence _buildSigningCertificateV2Attribute(
  CertificateInfo cert,
  CmsDigestAlgorithm digestAlgorithm,
) {
  // Hash the full certificate DER
  final certHash = _computeDigest(digestAlgorithm, cert.derBytes);

  // ESSCertIDv2
  final essCertId = ASN1Sequence();

  // hashAlgorithm — include explicitly if not SHA-256 (the default)
  if (digestAlgorithm != CmsDigestAlgorithm.sha256) {
    final algId = ASN1Parser(
      Uint8List.fromList(
        _buildAlgorithmIdentifier(_digestOid(digestAlgorithm)),
      ),
    ).nextObject();
    essCertId.add(algId);
  }

  // certHash
  essCertId.add(ASN1OctetString(certHash));

  // issuerSerial
  final issuerSerial = ASN1Sequence();

  // GeneralNames ::= SEQUENCE OF GeneralName
  // GeneralName ::= [4] EXPLICIT Name
  // directoryName [4]
  final generalName = ASN1Object.preEncoded(0xA4, cert.issuerDer);
  final generalNames = ASN1Sequence();
  generalNames.add(generalName);
  issuerSerial.add(generalNames);
  issuerSerial.add(ASN1Integer(cert.serialNumber));
  essCertId.add(issuerSerial);

  // certs SEQUENCE OF ESSCertIDv2
  final certs = ASN1Sequence();
  certs.add(essCertId);

  // SigningCertificateV2
  final scv2 = ASN1Sequence();
  scv2.add(certs);

  return _buildAttribute(_oidSigningCertificateV2, [scv2]);
}

// ─── Time Encoding ──────────────────────────────────────────────────────────

/// Encode signing time as UTCTime (dates before 2050) or GeneralizedTime.
ASN1Object _encodeSigningTime(DateTime dt) {
  final utc = dt.toUtc();
  if (utc.year < 2050) {
    return ASN1UtcTime(utc);
  }
  return ASN1GeneralizedTime(utc);
}

// ─── Low-level TLV Helpers ──────────────────────────────────────────────────

void _writeSequence(BytesBuilder builder, Uint8List content) {
  _writeTag(builder, 0x30, content);
}

void _writeTag(BytesBuilder builder, int tag, Uint8List content) {
  builder.addByte(tag);
  _writeLength(builder, content.length);
  builder.add(content);
}

void _writeLength(BytesBuilder builder, int length) {
  if (length < 0x80) {
    builder.addByte(length);
  } else if (length < 0x100) {
    builder.addByte(0x81);
    builder.addByte(length);
  } else if (length < 0x10000) {
    builder.addByte(0x82);
    builder.addByte((length >> 8) & 0xFF);
    builder.addByte(length & 0xFF);
  } else if (length < 0x1000000) {
    builder.addByte(0x83);
    builder.addByte((length >> 16) & 0xFF);
    builder.addByte((length >> 8) & 0xFF);
    builder.addByte(length & 0xFF);
  } else {
    builder.addByte(0x84);
    builder.addByte((length >> 24) & 0xFF);
    builder.addByte((length >> 16) & 0xFF);
    builder.addByte((length >> 8) & 0xFF);
    builder.addByte(length & 0xFF);
  }
}

/// Wrap content in an EXPLICIT context tag: [tagNum] CONSTRUCTED.
Uint8List _wrapExplicitTag(int tagNum, Uint8List content) {
  final builder = BytesBuilder();
  _writeTag(builder, 0xA0 | tagNum, content);
  return builder.toBytes();
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
