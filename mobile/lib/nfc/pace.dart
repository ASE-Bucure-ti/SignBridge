// SignBridge — PACE protocol implementation (BSI TR-03110)
//
// Password Authenticated Connection Establishment (PACE) establishes a
// secure messaging channel between the app and the card using a shared
// secret (CAN or PIN).
//
// This implementation supports ECDH-GM (Generic Mapping) with AES-CBC-CMAC,
// which is the variant used by Romanian CEI cards.
//
// For eSign on Romanian CEI, the PKI applet only supports PACE with CAN
// (password type 0x02). After PACE establishes the secure channel, the
// eSign PIN is verified separately via VERIFY through SM.
//
// Protocol steps:
//   Step 0: Read EF.CardAccess → parse PACE OID + domain parameters
//   Step 1: Request encrypted nonce → decrypt with password-derived key
//   Step 2: Map nonce to new EC generator point
//   Step 3: Perform ECDH key agreement on mapped domain
//   Step 4: Derive session keys, mutual authentication via MAC tokens
//
// After PACE, all APDUs go through SecureMessaging.

import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:logger/logger.dart';
import 'apdu.dart';
import 'secure_messaging.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// Known EC domain parameter IDs from BSI TR-03110 Table A.2.
class StandardizedDomainParameters {
  // IDs 0-7: DH (not used for CEI)
  // IDs 8-15: ECDH
  static const int brainpoolP192r1 = 8;
  static const int brainpoolP224r1 = 9;
  static const int brainpoolP256r1 = 10;
  static const int brainpoolP320r1 = 11;
  static const int brainpoolP384r1 = 12;
  static const int brainpoolP512r1 = 13;
  static const int secp256r1 = 14; // NIST P-256
  static const int secp384r1 = 15; // NIST P-384
  // IDs 16-17: ECDH with 521-bit
  static const int brainpoolP256r1Alt = 16;
  static const int secp521r1 = 17;

  static ECDomainParameters getParams(int id) {
    return switch (id) {
      8 => ECDomainParameters('brainpoolp192r1'),
      9 => ECDomainParameters('brainpoolp224r1'),
      10 => ECDomainParameters('brainpoolp256r1'),
      11 => ECDomainParameters('brainpoolp320r1'),
      12 => ECDomainParameters('brainpoolp384r1'),
      13 => ECDomainParameters('brainpoolp512r1'),
      14 => ECDomainParameters('prime256v1'),
      15 => ECDomainParameters('secp384r1'),
      17 => ECDomainParameters('secp521r1'),
      _ => throw UnsupportedError(
        'Unknown standardized domain parameter ID: $id',
      ),
    };
  }
}

// (OID prefix removed — unused, OID matching done via string comparison)

/// Parsed PACE info from EF.CardAccess.
class PaceInfo {
  final List<int> oid;
  final int version;
  final int? parameterId; // standardized domain parameter ID

  // Derived from OID
  final int mappingType; // 1=DH-GM, 2=ECDH-GM, 3=DH-IM, 4=ECDH-IM
  final int cipherType; // 1=3DES, 2=AES-128, 3=AES-192, 4=AES-256

  PaceInfo({
    required this.oid,
    required this.version,
    this.parameterId,
    required this.mappingType,
    required this.cipherType,
  });

  bool get isEcdhGm => mappingType == 2;
  bool get isAes => cipherType >= 2;

  int get keyLength => switch (cipherType) {
    2 => 16, // AES-128
    3 => 24, // AES-192
    4 => 32, // AES-256
    _ => 8, // 3DES
  };
}

/// Parse EF.CardAccess to extract PaceInfo.
PaceInfo parsePaceInfo(Uint8List efCardAccess) {
  final parsed = ASN1Parser(efCardAccess);
  // EF.CardAccess is a SET of SecurityInfos
  final topLevel = parsed.nextObject();

  if (topLevel is ASN1Set) {
    for (final element in topLevel.elements) {
      final info = _tryParsePaceSecurityInfo(element);
      if (info != null) return info;
    }
  } else if (topLevel is ASN1Sequence) {
    // Some cards encode as SEQUENCE at top level
    final info = _tryParsePaceSecurityInfo(topLevel);
    if (info != null) return info;

    // Or it's a SEQUENCE of SEQUENCEs
    for (final element in topLevel.elements) {
      final info2 = _tryParsePaceSecurityInfo(element);
      if (info2 != null) return info2;
    }
  }

  throw StateError('No PACEInfo found in EF.CardAccess');
}

PaceInfo? _tryParsePaceSecurityInfo(ASN1Object obj) {
  if (obj is! ASN1Sequence) return null;
  final elements = obj.elements;
  if (elements.length < 2) return null;

  final oidObj = elements[0];
  if (oidObj is! ASN1ObjectIdentifier) return null;

  // Decode the OID to check if it's a PACE OID
  final oidString = oidObj.identifier;
  if (oidString == null) return null;
  if (!oidString.startsWith('0.4.0.127.0.7.2.2.4')) return null;

  // Parse OID components after the PACE prefix
  final parts = oidString.split('.').map(int.parse).toList();
  // OID: 0.4.0.127.0.7.2.2.4.<mappingType>.<cipherType>
  if (parts.length < 11) return null;

  final mappingType = parts[9]; // 1=DH-GM, 2=ECDH-GM, 3=DH-IM, 4=ECDH-IM
  final cipherType = parts[10]; // 1=3DES, 2=AES-128, 3=AES-192, 4=AES-256

  // Version (required INTEGER)
  final versionObj = elements[1];
  final version = (versionObj as ASN1Integer).intValue;

  // Optional: parameterId
  int? parameterId;
  if (elements.length > 2) {
    final paramObj = elements[2];
    if (paramObj is ASN1Integer) {
      parameterId = paramObj.intValue;
    }
  }

  return PaceInfo(
    oid: parts,
    version: version,
    parameterId: parameterId,
    mappingType: mappingType,
    cipherType: cipherType,
  );
}

/// Transceive function type — sends APDU bytes, returns response bytes.
/// This decouples PACE from the NFC transport so it can be tested.
typedef Transceive = Future<Uint8List> Function(Uint8List command);

/// PACE password type constants (BSI TR-03110 Part 3, Table 6).
class PacePasswordType {
  static const int mrz = 0x01;
  static const int can = 0x02;
  static const int pin = 0x03;
  static const int puk = 0x04;
}

/// Run the full PACE protocol and return a [SecureMessaging] session.
///
/// [transceive] sends raw bytes to the card and returns raw response.
/// [password] is the shared secret (PIN or CAN).
/// [passwordType] is 0x02 for CAN, 0x03 for PIN (see [PacePasswordType]).
/// [paceInfo] is parsed from EF.CardAccess.
Future<SecureMessaging> performPace({
  required Transceive transceive,
  required String password,
  int passwordType = PacePasswordType.pin,
  required PaceInfo paceInfo,
}) async {
  if (!paceInfo.isEcdhGm) {
    throw UnsupportedError(
      'Only ECDH-GM PACE is supported, got mapping type ${paceInfo.mappingType}',
    );
  }
  if (!paceInfo.isAes) {
    throw UnsupportedError('Only AES-based PACE is supported');
  }

  final domainParams = StandardizedDomainParameters.getParams(
    paceInfo.parameterId ?? StandardizedDomainParameters.brainpoolP256r1,
  );

  final keyLen = paceInfo.keyLength;
  _log.d(
    'PACE params: OID=${paceInfo.oid.join(".")}, '
    'paramId=${paceInfo.parameterId}, keyLen=$keyLen, '
    'fieldSize=${domainParams.curve.fieldSize}',
  );

  // Wrap transceive with logging
  Future<Uint8List> logTransceive(Uint8List cmd) async {
    final hex = cmd.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _log.d('PACE >>> $hex');
    final resp = await transceive(cmd);
    final rHex = resp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    _log.d('PACE <<< $rHex');
    return resp;
  }

  // Derive Kπ from password using KDF (BSI TR-03110)
  final kPi = _kdfPi(password, keyLen);
  _log.d(
    'PACE: Kπ derived from password (type=0x${passwordType.toRadixString(16)})',
  );

  // ── MSE:SET AT — Select PACE protocol and password reference ────────────
  _log.i('PACE: MSE:SET AT (select PACE protocol)');
  final oidDer = ASN1ObjectIdentifier.fromComponents(paceInfo.oid).encodedBytes;
  // Extract OID value bytes (skip tag 0x06 and single-byte length)
  final oidValue = oidDer.sublist(2);
  // Data: cryptographic mechanism (tag 0x80) + password reference (tag 0x83)
  final mseData = Uint8List.fromList([
    0x80, oidValue.length, ...oidValue,
    0x83, 0x01, passwordType, // 0x02=CAN, 0x03=PIN
  ]);
  final mseCmd = mseSet(p1: 0xC1, p2: 0xA4, data: mseData);
  final mseResp = ResponseApdu.fromBytes(await logTransceive(mseCmd.encode()));
  if (!mseResp.isOk) {
    throw StateError('MSE:SET AT failed: SW=${mseResp.sw.toRadixString(16)}');
  }
  _log.d('PACE: MSE:SET AT OK');

  // ── Step 0: General Authenticate — Request encrypted nonce ──────────────
  _log.i('PACE step 0: Requesting encrypted nonce');
  final step0Data = Uint8List.fromList([0x7C, 0x00]); // empty dynamic auth data
  final step0Cmd = generalAuthenticate(data: step0Data, isChaining: true);
  final step0Resp = ResponseApdu.fromBytes(
    await logTransceive(step0Cmd.encode()),
  );

  if (!step0Resp.isOk) {
    throw StateError(
      'PACE step 0 failed: SW=${step0Resp.sw.toRadixString(16)}',
    );
  }

  // Parse response: 7C { 80 <encrypted nonce> }
  final encNonce = _extractTag(step0Resp.data, 0x80);
  if (encNonce == null) {
    throw StateError('PACE step 0: No encrypted nonce in response');
  }

  // Decrypt nonce with Kπ (AES-CBC, zero IV)
  final nonce = _decryptAesCbc(kPi, encNonce);
  _log.d('PACE step 1: Nonce decrypted (${nonce.length} bytes)');

  // ── Step 2: Map nonce to new generator ──────────────────────────────────
  _log.i('PACE step 2: ECDH key agreement (ephemeral)');

  final secureRandom = _getSecureRandom();
  final curve = domainParams.curve;
  final G = domainParams.G;
  final n = domainParams.n;

  // Generate ephemeral key pair 1 for mapping
  final sk1 = _generatePrivateKey(n, secureRandom);
  final pk1 = (G * sk1)!;

  // Send our public key PK_Map_1
  final pk1Encoded = _encodeEcPoint(pk1, curve);
  _log.d(
    'PACE step 2: pk1Encoded=${pk1Encoded.length} bytes, first byte=0x${pk1Encoded[0].toRadixString(16)}',
  );
  final step2Data = _wrapDynAuth(0x81, pk1Encoded);
  _log.d('PACE step 2: wrapped data=${step2Data.length} bytes');
  final step2Cmd = generalAuthenticate(data: step2Data, isChaining: true);
  final step2Resp = ResponseApdu.fromBytes(
    await logTransceive(step2Cmd.encode()),
  );

  if (!step2Resp.isOk) {
    throw StateError(
      'PACE step 2 failed: SW=${step2Resp.sw.toRadixString(16)}',
    );
  }

  // Parse card's ephemeral public key PK_Map_card
  final pkCardMap = _extractTag(step2Resp.data, 0x82);
  if (pkCardMap == null) {
    throw StateError('PACE step 2: No card mapping public key');
  }

  final cardPk1 = _decodeEcPoint(pkCardMap, curve);

  // Shared secret H = sk1 * cardPk1
  final sharedH = (cardPk1 * sk1)!;

  // Map generator: G' = s*G + H  (s = nonce interpreted as BigInt)
  final s = _bytesToBigInt(nonce);
  final sG = (G * s)!;
  final mappedG = (sG + sharedH)!;
  _log.d('PACE step 2: Generator mapped');

  // ── Step 3: Key agreement on mapped domain ──────────────────────────────
  _log.i('PACE step 3: Key agreement on mapped domain');

  // Generate ephemeral key pair 2 (on the mapped generator)
  final sk2 = _generatePrivateKey(n, secureRandom);
  final pk2 = (mappedG * sk2)!;

  final pk2Encoded = _encodeEcPoint(pk2, curve);
  final step3Data = _wrapDynAuth(0x83, pk2Encoded);
  final step3Cmd = generalAuthenticate(data: step3Data, isChaining: true);
  final step3Resp = ResponseApdu.fromBytes(
    await logTransceive(step3Cmd.encode()),
  );

  if (!step3Resp.isOk) {
    throw StateError(
      'PACE step 3 failed: SW=${step3Resp.sw.toRadixString(16)}',
    );
  }

  final pkCardEph = _extractTag(step3Resp.data, 0x84);
  if (pkCardEph == null) {
    throw StateError('PACE step 3: No card ephemeral public key');
  }

  final cardPk2 = _decodeEcPoint(pkCardEph, curve);

  // Shared secret K = sk2 * cardPk2
  final sharedK = (cardPk2 * sk2)!;
  final fieldSize = (curve.fieldSize + 7) ~/ 8;
  // getEncoded normalizes projective→affine; extract x from 04||x||y
  final sharedKEnc = sharedK.getEncoded(false);
  final sharedSecret = Uint8List.fromList(sharedKEnc.sublist(1, 1 + fieldSize));

  // ── Derive session keys ─────────────────────────────────────────────────
  final ksEnc = _kdfEnc(sharedSecret, keyLen);
  final ksMac = _kdfMac(sharedSecret, keyLen);
  _log.d(
    'PACE: Session keys derived (KS_ENC=${ksEnc.length}B, KS_MAC=${ksMac.length}B)',
  );

  // ── Step 4: Mutual authentication ───────────────────────────────────────
  _log.i('PACE step 4: Mutual authentication');

  // Compute our MAC token: CMAC(KS_MAC, mapping_of_card_pk2)
  // The "mapping" is the encoded public key of the OTHER side
  // Per BSI TR-03110 Part 3, Section A.2.4: MAC token input is an OID + public key object
  final tokenInputCard = _buildAuthToken(paceInfo.oid, pkCardEph);
  final ourMac = _computeCmac(ksMac, tokenInputCard);

  // Send our MAC token, receive card's MAC token
  final step4Data = _wrapDynAuth(0x85, ourMac.sublist(0, 8));
  final step4Cmd = generalAuthenticate(data: step4Data, isChaining: false);
  final step4Resp = ResponseApdu.fromBytes(
    await logTransceive(step4Cmd.encode()),
  );

  if (!step4Resp.isOk) {
    throw StateError(
      'PACE step 4 failed: SW=${step4Resp.sw.toRadixString(16)}',
    );
  }

  // Verify card's MAC token
  final cardMac = _extractTag(step4Resp.data, 0x86);
  if (cardMac == null) {
    throw StateError('PACE step 4: No card MAC token');
  }

  final tokenInputOurs = _buildAuthToken(paceInfo.oid, pk2Encoded);
  final expectedCardMac = _computeCmac(ksMac, tokenInputOurs);

  if (!_constantTimeEquals(cardMac, expectedCardMac.sublist(0, 8))) {
    throw StateError('PACE step 4: Card MAC verification failed');
  }

  _log.i('Finished PACE SM key establishment');

  // Initial SSC = last 4 bytes of card mac token | last 4 bytes of our mac token
  // (per BSI TR-03110)
  final ssc = Uint8List(keyLen); // same length as cipher block
  // For AES, SSC is typically initialized to zero and incremented
  // Some implementations use concatenation of mac token tails
  // We use zero-init as that's the most common approach
  return SecureMessaging(ksEnc: ksEnc, ksMac: ksMac, ssc: ssc);
}

// ── KDF functions (BSI TR-03110 Part 3, A.2.3) ─────────────────────────────

/// KDF for π (password) → key. Uses SHA-1 for AES-128, SHA-256 for AES-192/256.
Uint8List _kdfPi(String password, int keyLen) {
  // K = KDF(π, 3) where KDF(K, c) = H(K || 00000003)
  final passwordBytes = Uint8List.fromList(password.codeUnits);
  return _kdf(passwordBytes, 3, keyLen);
}

/// KDF for session encryption key.
Uint8List _kdfEnc(Uint8List sharedSecret, int keyLen) {
  return _kdf(sharedSecret, 1, keyLen);
}

/// KDF for session MAC key.
Uint8List _kdfMac(Uint8List sharedSecret, int keyLen) {
  return _kdf(sharedSecret, 2, keyLen);
}

/// Core KDF: H(key || counter_as_4_big_endian_bytes), truncated to keyLen.
Uint8List _kdf(Uint8List key, int counter, int keyLen) {
  final input = BytesBuilder();
  input.add(key);
  input.add(
    Uint8List.fromList([
      (counter >> 24) & 0xFF,
      (counter >> 16) & 0xFF,
      (counter >> 8) & 0xFF,
      counter & 0xFF,
    ]),
  );

  final Digest hash;
  if (keyLen <= 16) {
    hash = SHA1Digest();
  } else {
    hash = SHA256Digest();
  }

  final digest = hash.process(input.toBytes());
  return Uint8List.fromList(digest.sublist(0, keyLen));
}

// ── AES-CBC decrypt (for nonce decryption) ──────────────────────────────────

Uint8List _decryptAesCbc(Uint8List key, Uint8List data) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), Uint8List(16)));
  final output = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, output, i);
  }
  return output;
}

// ── AES-CMAC ────────────────────────────────────────────────────────────────

Uint8List _computeCmac(Uint8List key, Uint8List data) {
  final cmac = CMac(AESEngine(), 128)..init(KeyParameter(key));
  return cmac.process(data);
}

// ── EC point encoding/decoding ──────────────────────────────────────────────

Uint8List _encodeEcPoint(ECPoint point, ECCurve curve) {
  // getEncoded(false) returns uncompressed format (04 || x || y)
  // and handles normalization from projective to affine coordinates
  return Uint8List.fromList(point.getEncoded(false));
}

ECPoint _decodeEcPoint(Uint8List encoded, ECCurve curve) {
  final point = curve.decodePoint(encoded.toList());
  if (point == null) {
    throw StateError('Failed to decode EC point');
  }
  return point;
}

// ── BigInt <-> Bytes ────────────────────────────────────────────────────────

BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

// ── Private key generation ──────────────────────────────────────────────────

BigInt _generatePrivateKey(BigInt n, SecureRandom random) {
  final bitLen = n.bitLength;
  BigInt k;
  do {
    k = random.nextBigInteger(bitLen);
  } while (k <= BigInt.one || k >= n);
  return k;
}

FortunaRandom _getSecureRandom() {
  final random = FortunaRandom();
  final rng = Random.secure();
  final seed = Uint8List(32);
  for (var i = 0; i < seed.length; i++) {
    seed[i] = rng.nextInt(256);
  }
  random.seed(KeyParameter(seed));
  return random;
}

// ── TLV helpers for PACE General Authenticate ───────────────────────────────

/// Wrap data in 7C { tag <data> } dynamic authentication data.
Uint8List _wrapDynAuth(int tag, Uint8List data) {
  final inner = BytesBuilder();
  inner.addByte(tag);
  _addLength(inner, data.length);
  inner.add(data);
  final innerBytes = inner.toBytes();

  final outer = BytesBuilder();
  outer.addByte(0x7C);
  _addLength(outer, innerBytes.length);
  outer.add(innerBytes);
  return outer.toBytes();
}

/// Extract a TLV-tagged value from within a 7C dynamic auth data structure.
Uint8List? _extractTag(Uint8List data, int targetTag) {
  if (data.isEmpty) return null;

  // Skip outer 7C wrapper
  var offset = 0;
  if (data[offset] == 0x7C) {
    offset++;
    final (_, newOffset) = _readLength(data, offset);
    offset = newOffset;
  }

  // Scan inner TLVs
  while (offset < data.length) {
    if (offset >= data.length) break;
    final tag = data[offset++];
    if (offset >= data.length) break;
    final (length, newOffset) = _readLength(data, offset);
    offset = newOffset;

    if (tag == targetTag) {
      return data.sublist(offset, offset + length);
    }
    offset += length;
  }

  return null;
}

(int, int) _readLength(Uint8List data, int offset) {
  final first = data[offset++];
  if (first < 0x80) return (first, offset);
  final numBytes = first & 0x7F;
  var length = 0;
  for (var i = 0; i < numBytes; i++) {
    length = (length << 8) | data[offset++];
  }
  return (length, offset);
}

void _addLength(BytesBuilder builder, int length) {
  if (length < 0x80) {
    builder.addByte(length);
  } else if (length <= 0xFF) {
    builder.addByte(0x81);
    builder.addByte(length);
  } else {
    builder.addByte(0x82);
    builder.addByte((length >> 8) & 0xFF);
    builder.addByte(length & 0xFF);
  }
}

/// Build the authentication token input for MAC computation.
/// Per BSI TR-03110: `7F49 { 06 OID 86 publicKey }`
Uint8List _buildAuthToken(List<int> oidParts, Uint8List publicKey) {
  // Encode OID
  final oidEncoded = ASN1ObjectIdentifier.fromComponents(oidParts).encodedBytes;

  // Build 86 publicKey
  final pkTag = BytesBuilder();
  pkTag.addByte(0x86);
  _addLength(pkTag, publicKey.length);
  pkTag.add(publicKey);

  // Build 7F49 { OID, PK }
  final innerBuilder = BytesBuilder();
  innerBuilder.add(oidEncoded);
  innerBuilder.add(pkTag.toBytes());
  final innerBytes = innerBuilder.toBytes();

  final builder = BytesBuilder();
  builder.addByte(0x7F);
  builder.addByte(0x49);
  _addLength(builder, innerBytes.length);
  builder.add(innerBytes);
  return builder.toBytes();
}

bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
