// SignBridge — High-level card reader
//
// Orchestrates the complete card interaction:
//   1. Read EF.CardAccess → parse PACE parameters
//   2. Perform PACE with CAN → establish SM channel
//   3. SELECT PKI Applet (A0000002471001)
//   4. VERIFY eSign PIN (6 digits) through SM
//   5. READ signing certificate (DER)
//   6. MSE:SET → configure signing algorithm
//   7. INTERNAL AUTHENTICATE → card signs the hash
//
// All steps after PACE use SecureMessaging.

import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'apdu.dart';
import 'nfc_manager.dart';
import 'pace.dart';
import 'secure_messaging.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// AID for the BSI eSign PKI applet on Romanian CEI.
final _pkiAid = hexToBytes('A0000002471001');

/// EF.CardAccess file identifier (short EF ID on most cards, or read via SELECT MF).
const _efCardAccessId = 0x011C;

/// PIN reference for eSign PIN (P2 in VERIFY).
const _eSignPinRef = 0x81;

/// Result of reading the card's signing certificate.
class CardCertificate {
  final Uint8List derBytes;
  CardCertificate(this.derBytes);
}

/// Result of a signing operation.
class CardSignature {
  final Uint8List signatureBytes;
  CardSignature(this.signatureBytes);
}

/// High-level card interaction API.
class CardReader {
  final NfcManager _nfc;
  SecureMessaging? _sm;

  CardReader(this._nfc);

  /// Read EF.CardAccess from the card and parse PACE parameters.
  Future<PaceInfo> readPaceInfo() async {
    _log.i('Reading EF.CardAccess...');

    // SELECT Master File
    final mfResp = await _nfc.transceive(selectMf());
    // Not all cards require MF select to succeed — some start at MF
    _log.d('SELECT MF: ${mfResp.sw.toRadixString(16)}');

    // SELECT EF.CardAccess
    final selectResp = await _nfc.transceive(selectFile(_efCardAccessId));
    if (!selectResp.isOk) {
      // Try alternative: some cards have EF.CardAccess at a different location
      // or accessible directly via short file ID in READ BINARY
      _log.w(
        'SELECT EF.CardAccess failed: ${selectResp.sw.toRadixString(16)}, trying direct read',
      );
    }

    // READ BINARY — read EF.CardAccess content
    // Start with a reasonable chunk and extend if needed
    final data = await _readBinaryFull();
    _log.i('EF.CardAccess: ${data.length} bytes');

    return parsePaceInfo(data);
  }

  /// Perform PACE authentication using the CAN.
  Future<void> authenticate(String can, PaceInfo paceInfo) async {
    _log.i('Starting PACE authentication...');
    _sm = await performPace(
      transceive: (cmd) => _nfc.transceiveRaw(cmd),
      can: can,
      paceInfo: paceInfo,
    );
    _log.i('PACE authentication successful');
  }

  /// SELECT the PKI applet (through SM channel).
  Future<void> selectPkiApplet() async {
    _log.i('Selecting PKI Applet...');
    final cmd = selectByAid(_pkiAid);
    final resp = await _transceiveSm(cmd);
    if (!resp.isOk) {
      throw StateError('PKI select failed: SW=${resp.sw.toRadixString(16)}');
    }
    _log.i('PKI selected');
  }

  /// Verify the 6-digit eSign PIN (through SM channel).
  /// Returns the number of remaining retries on wrong PIN, or -1 on success.
  Future<int> verifyEsignPin(String pin) async {
    if (pin.length != 6) {
      throw ArgumentError('eSign PIN must be 6 digits');
    }

    _log.i('Verifying eSign PIN...');
    final pinData = encodePinForVerify(pin);
    final cmd = verifyPin(_eSignPinRef, pinData);
    final resp = await _transceiveSm(cmd);

    if (resp.isOk) {
      _log.i('eSign PIN verified');
      return -1; // success
    }

    if (resp.isWrongPin) {
      final retries = resp.pinRetries;
      _log.w('Wrong PIN, $retries retries remaining');
      return retries;
    }

    if (resp.sw == SW.authMethodBlocked) {
      throw StateError('eSign PIN is blocked (too many wrong attempts)');
    }

    throw StateError(
      'PIN verification failed: SW=${resp.sw.toRadixString(16)}',
    );
  }

  /// Read the signing certificate from the card (DER-encoded X.509).
  Future<CardCertificate> readSigningCertificate() async {
    _log.i('Reading signing certificate...');

    // The certificate is typically in a known EF under the PKI applet.
    // Common file IDs: 0xC000, 0xC001, or discoverable via EF.DIR.
    // First try the most common location.
    for (final fileId in [0xC000, 0xC001]) {
      final selectResp = await _transceiveSm(selectFile(fileId));
      if (selectResp.isOk) {
        _log.d('Certificate EF selected: ${fileId.toRadixString(16)}');
        final certData = await _readBinarySmFull();
        if (certData.isNotEmpty) {
          _log.i('Signing Cert (DER, ${certData.length} bytes)');
          return CardCertificate(certData);
        }
      }
    }

    throw StateError(
      'Certificate extraction error: no signing certificate found',
    );
  }

  /// Configure the signing algorithm via MSE:SET.
  /// Uses ECDSA with SHA-384 (most common for Romanian CEI).
  Future<void> mseSetSigning() async {
    _log.i('MSE:SET for signing...');

    // Algorithm template: OID for ECDSA-SHA384 + key reference
    // Tag 80 = algorithm OID, Tag 84 = key reference
    // ECDSA with SHA-384: OID 0.4.0.127.0.7.2.2.2.2.3
    // For BSI cards, the template is: 80 0A <OID> 84 01 <keyRef>
    //
    // Simplified: some cards accept just the algorithm reference byte
    // We send the standard MSE:SET for computation (P1=0x41) + digital signature (P2=0xB6)
    final data = Uint8List.fromList([
      0x80, 0x0A, // Tag 80, length 10 — crypto mechanism OID
      // OID: 0.4.0.127.0.7.2.2.2.2.3 (id-TA-ECDSA-SHA-384)
      0x06, 0x08, 0x04, 0x00, 0x7F, 0x00, 0x07, 0x02, 0x02, 0x02,
      0x84,
      0x01,
      0x81, // Tag 84, length 1 — private key reference (0x81 = signing key)
    ]);

    final cmd = mseSet(p1: 0x41, p2: 0xB6, data: data);
    final resp = await _transceiveSm(cmd);

    if (!resp.isOk) {
      // Try fallback: RSA-SHA256 for cards
      _log.w(
        'MSE:SET ECDSA-SHA384 failed (${resp.sw.toRadixString(16)}), trying RSA-SHA256',
      );
      final rsaData = Uint8List.fromList([
        0x80, 0x0A,
        // OID: 1.2.840.113549.1.1.11 (sha256WithRSAEncryption)
        0x06, 0x08, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01,
        0x84, 0x01, 0x81,
      ]);
      final rsaCmd = mseSet(p1: 0x41, p2: 0xB6, data: rsaData);
      final rsaResp = await _transceiveSm(rsaCmd);
      if (!rsaResp.isOk) {
        throw StateError('MSE:SET failed: SW=${rsaResp.sw.toRadixString(16)}');
      }
    }

    _log.i('MSE:SET complete');
  }

  /// Sign a hash using INTERNAL AUTHENTICATE.
  /// Returns the raw signature bytes from the card.
  Future<CardSignature> signHash(Uint8List hash) async {
    _log.i('INTERNAL AUTHENTICATE (${hash.length} bytes hash)...');

    final cmd = internalAuthenticate(hash);
    final resp = await _transceiveSm(cmd);

    if (!resp.isOk) {
      throw StateError(
        'INTERNAL AUTHENTICATE failed: SW=${resp.sw.toRadixString(16)}',
      );
    }

    _log.i('Signature received: ${resp.data.length} bytes');
    return CardSignature(resp.data);
  }

  // ── SM-wrapped transceive ─────────────────────────────────────────────────

  Future<ResponseApdu> _transceiveSm(CommandApdu cmd) async {
    if (_sm == null) {
      throw StateError('Secure Messaging not established — run PACE first');
    }
    final wrappedCmd = _sm!.wrapCommand(cmd);
    final wrappedResp = await _nfc.transceive(wrappedCmd);
    return _sm!.unwrapResponse(wrappedResp);
  }

  // ── READ BINARY helpers ───────────────────────────────────────────────────

  /// Read full binary content from currently selected EF (no SM).
  Future<Uint8List> _readBinaryFull() async {
    final data = BytesBuilder();
    var offset = 0;
    const chunkSize = 0xDF; // safe chunk under 256
    while (true) {
      final cmd = readBinary(offset, chunkSize);
      final resp = await _nfc.transceive(cmd);
      if (resp.isOk && resp.data.isNotEmpty) {
        data.add(resp.data);
        offset += resp.data.length;
        if (resp.data.length < chunkSize) break; // last chunk
      } else {
        break;
      }
    }
    return data.toBytes();
  }

  /// Read full binary content from currently selected EF (through SM).
  Future<Uint8List> _readBinarySmFull() async {
    final data = BytesBuilder();
    var offset = 0;
    const chunkSize = 0xDF;
    while (true) {
      final cmd = readBinary(offset, chunkSize);
      final resp = await _transceiveSm(cmd);
      if (resp.isOk && resp.data.isNotEmpty) {
        data.add(resp.data);
        offset += resp.data.length;
        if (resp.data.length < chunkSize) break;
      } else {
        break;
      }
    }
    return data.toBytes();
  }
}
