// SignBridge — High-level card reader (powered by dmrtd library)
//
// Uses the ZeroPass/dmrtd library for PACE authentication and Secure
// Messaging, the same library used by the official ROeID app.
//
// Flow recovered from ROeID 2.3.352 RomaniaEidSigner._executeSigningSequence:
//   1. NFC connect
//   2. Read EF.CardAccess (no SM yet)
//   3. SELECT manager applet, then PKI applet, both in the clear
//   4. One PACE with the 6-digit CAN, on the already selected PKI applet
//   5. SELECT + READ BINARY of signing certificate file CE8E (through SM)
//   6. VERIFY eSign PIN (through SM)
//   7. MSE:SET AT (through SM)
//   8. INTERNAL AUTHENTICATE of the SHA-384 hash (through SM)

import 'dart:typed_data';
import 'dart:async';
import 'package:dmrtd/dmrtd.dart';
import 'package:dmrtd/internal.dart';
// ignore: implementation_imports
import 'package:dmrtd/src/proto/can_key.dart';
import 'package:logger/logger.dart';

import '../util/sb_log.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

void _sb(String message) {
  sbLog(message);
  _log.i(message);
}

/// Manager applet from RomaniaEidSigner._aidManager.
/// Hex `A000000077030C60000000FE00000500` (the last 00 is part of the AID).
final _managerAid = Uint8List.fromList([
  0xA0,
  0x00,
  0x00,
  0x00,
  0x77,
  0x03,
  0x0C,
  0x60,
  0x00,
  0x00,
  0x00,
  0xFE,
  0x00,
  0x00,
  0x05,
  0x00,
]);

/// PKI applet from RomaniaEidSigner._aidPki.
/// Hex `E828BD080FD25047656E65726963`, not the ICAO DF1 AID.
final _pkiAid = Uint8List.fromList([
  0xE8,
  0x28,
  0xBD,
  0x08,
  0x0F,
  0xD2,
  0x50,
  0x47,
  0x65,
  0x6E,
  0x65,
  0x72,
  0x69,
  0x63,
]);

/// VERIFY P2 used by RomaniaEidSigner. This is the PIN reference, not the key id.
const _eSignPinRef = 0x05;

/// Signing certificate elementary file selected as `00 A4 02 04 CE 8E`.
const _signingCertFileId = 0xCE8E;

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

/// High-level card interaction API using dmrtd for PACE + Secure Messaging.
class CardReader {
  late NfcProvider _nfc;
  late MrtdApi _api;
  EfCardAccess? _cachedCardAccess;

  /// Poll for an NFC tag and connect.
  Future<void> connect({
    String iosAlertMessage = 'Hold your eID card to the phone',
  }) async {
    _sb('NFC connect');
    _nfc = NfcProvider();
    await _nfc.connect(iosAlertMessage: iosAlertMessage);
    _api = MrtdApi(_nfc);
    _sb('NFC connected');
  }

  /// Disconnect from the NFC card.
  Future<void> disconnect({String? iosAlertMessage}) async {
    _sb('NFC disconnect');
    await _nfc.disconnect(iosAlertMessage: iosAlertMessage);
  }

  /// Open the signing channel the way ROeID does.
  ///
  /// CardAccess and both applet selects go out in the clear. PACE runs once,
  /// after the PKI applet is selected, with [can] as a [CanKey] (six ASCII
  /// digits, password reference 0x02). A wrong CAN fails PACE and does not
  /// touch the eSign PIN counter.
  Future<void> openSigningSession(String can) async {
    var retried = false;

    while (true) {
      try {
        _sb('SELECT MF and read EF.CardAccess (CAN not used yet, PIN not sent)');
        await _api.selectMasterFile();
        final rawCardAccess = await _api.readFileBySFI(EfCardAccess.SFI);
        _cachedCardAccess = EfCardAccess.fromBytes(rawCardAccess);
        _sb('EF.CardAccess ${rawCardAccess.length} bytes');

        await _selectManagerApplet();

        _sb('SELECT PKI E828BD080FD25047656E65726963 p2=0C (clear, before PACE)');
        await _api.icc.selectFileByDFName(dfName: _pkiAid, p2: 0x0C);
        _sb('PKI applet selected');

        _sb('PACE start, CAN length=${can.length} (wrong CAN does not touch the eSign PIN)');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await _api.initSessionViaPACE(CanKey(can), _cachedCardAccess!);
        _sb('PACE established, SM active');
        return;
      } catch (e, st) {
        final transientCommError =
            !retried &&
            (e.toString().contains('Communication error') ||
                e.toString().contains('Tag was lost') ||
                e.toString().contains('NfcProviderError'));
        if (!transientCommError) {
          _log.e('openSigningSession failed: $e', error: e, stackTrace: st);
          rethrow;
        }
        retried = true;
        _log.w('Transient NFC error before PIN verify, retrying once');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  Future<void> _selectManagerApplet() async {
    _sb('SELECT manager applet p2=0C (clear, before PACE)');
    try {
      await _api.icc.selectFileByDFName(dfName: _managerAid, p2: 0x0C);
      _sb('Manager applet selected');
    } catch (e, st) {
      _sb('Manager select failed, continuing: $e');
      _log.t(st.toString());
    }
  }

  /// Verify the 6-digit eSign PIN (through SM channel).
  /// Returns -1 on success, or the number of remaining retries on wrong PIN.
  Future<int> verifyEsignPin(String pin) async {
    if (pin.length != 6) {
      throw ArgumentError('eSign PIN must be 6 digits');
    }

    _sb(
      'VERIFY about to be sent: 00 20 00 05, ${pin.length} ASCII digits padded to 12 with FF. This consumes one eSign PIN attempt.',
    );
    final pinData = _encodePinForVerify(pin);
    final cmd = CommandAPDU(
      cla: 0x00,
      ins: 0x20, // VERIFY
      p1: 0x00,
      p2: _eSignPinRef,
      data: pinData,
      ne: 0, // no Le byte
    );

    final resp = await _transceiveSm(cmd, label: 'VERIFY');
    return _handleVerifyResponse(resp);
  }

  int _handleVerifyResponse(ResponseAPDU resp) {
    if (resp.status == StatusWord.success) {
      _sb('VERIFY SW=9000');
      return -1;
    }

    // Wrong PIN: SW=63CX where X = retries remaining
    if (resp.status.sw1 == 0x63 && (resp.status.sw2 & 0xF0) == 0xC0) {
      final retries = resp.status.sw2 & 0x0F;
      _sb('VERIFY SW=63C$retries — stop, do not retry');
      return retries;
    }

    if (resp.status == StatusWord.authenticationMethodBlocked) {
      throw StateError(
        'eSign PIN is blocked (too many wrong attempts). '
        'Unblock it with the official ROeID app or at a dedicated desk.',
      );
    }

    throw StateError('PIN verification failed: ${resp.status.description()}');
  }

  /// Read the signing certificate from the card (DER-encoded X.509).
  Future<CardCertificate> readSigningCertificate() async {
    _sb('SELECT file CE8E (00 A4 02 04). PIN not sent yet.');
    final select = CommandAPDU(
      cla: 0x00,
      ins: 0xA4,
      p1: 0x02,
      p2: 0x04,
      data: Uint8List.fromList([
        (_signingCertFileId >> 8) & 0xFF,
        _signingCertFileId & 0xFF,
      ]),
    );
    final selected = await _transceiveSm(select, label: 'SELECT CE8E');
    if (selected.status != StatusWord.success) {
      throw StateError(
        'SELECT CE8E failed: ${selected.status.description()}',
      );
    }

    final chunks = BytesBuilder(copy: false);
    var offset = 0;
    const chunk = 200;
    while (offset < 8192) {
      final read = CommandAPDU(
        cla: 0x00,
        ins: 0xB0,
        p1: (offset >> 8) & 0xFF,
        p2: offset & 0xFF,
        ne: chunk,
      );
      final resp = await _transceiveSm(read, label: 'READ BINARY @$offset');
      final data = resp.data ?? Uint8List(0);
      // 6282 means the file ended inside this read. The bytes are still valid.
      final endOfFile = resp.status == StatusWord.unexpectedEOF;
      if (resp.status != StatusWord.success && !endOfFile) {
        if (chunks.isNotEmpty) break;
        throw StateError(
          'Failed to read signing certificate (CE8E): ${resp.status.description()}',
        );
      }
      if (data.isNotEmpty) {
        chunks.add(data);
        offset += data.length;
        _sb('CE8E kept ${data.length} bytes, total $offset');
      }
      if (endOfFile || data.length < chunk) break;
    }

    final certData = chunks.toBytes();
    if (certData.isEmpty) {
      throw StateError('Failed to read signing certificate (CE8E)');
    }
    _sb('CE8E read ${certData.length} bytes');
    return CardCertificate(certData);
  }

  /// MSE:SET AT copied from RomaniaEidSigner: mechanism `FF 20 08 00`, key `8E`.
  Future<void> mseSetSigning() async {
    _sb('MSE:SET AT 00 22 41 A4, key ref 8E');
    final data = Uint8List.fromList([
      0x80, 0x04, 0xFF, 0x20, 0x08, 0x00, // cryptographic mechanism
      0x84, 0x01, 0x8E, // private key reference
    ]);
    final cmd = CommandAPDU(
      cla: 0x00,
      ins: 0x22,
      p1: 0x41,
      p2: 0xA4,
      data: data,
    );
    final resp = await _transceiveSm(cmd, label: 'MSE:SET');
    if (resp.status != StatusWord.success) {
      throw StateError('MSE:SET failed: ${resp.status.description()}');
    }
    _sb('MSE:SET SW=9000');
  }

  /// Sign a hash using INTERNAL AUTHENTICATE.
  Future<CardSignature> signHash(Uint8List hash) async {
    _sb('INTERNAL AUTHENTICATE 00 88 00 00, hash=${hash.length} bytes, Le=256');

    final sigBytes = await _api.icc.internalAuthenticate(data: hash, ne: 256);

    _sb('INTERNAL AUTHENTICATE returned ${sigBytes.length} bytes');
    return CardSignature(sigBytes);
  }

  // ── Custom APDU transport through SM ──────────────────────────────────────

  /// Send a CommandAPDU through the Secure Messaging channel.
  /// Uses dmrtd's SM protect/unprotect on the shared ICC SM instance.
  Future<ResponseAPDU> _transceiveSm(
    CommandAPDU cmd, {
    required String label,
  }) async {
    final sm = _api.icc.sm;
    final wrapped = sm != null ? sm.protect(cmd) : cmd;
    final rawResp = await _nfc.transceive(wrapped.toBytes());
    final rapdu = ResponseAPDU.fromBytes(rawResp);
    final result = sm != null ? sm.unprotect(rapdu) : rapdu;
    final sw = result.status.value.toRadixString(16).padLeft(4, '0');
    final dataLen = cmd.ins == 0x20 ? 'hidden' : '${cmd.data?.length ?? 0}';
    _sb(
      '$label cla=${cmd.cla.toRadixString(16)} '
      'ins=${cmd.ins.toRadixString(16)} '
      'p1=${cmd.p1.toRadixString(16)} '
      'p2=${cmd.p2.toRadixString(16)} '
      'lc=$dataLen sm=${sm != null} SW=$sw',
    );
    return result;
  }

  // ── PIN encoding ──────────────────────────────────────────────────────────

  /// EnrollmentReader._encodePinAsciiPadded: UTF-8 digits into a 12-byte
  /// buffer filled with 0xFF. "123456" becomes 31 32 33 34 35 36 FF FF FF FF FF FF.
  static Uint8List _encodePinForVerify(String pin) {
    final bytes = Uint8List(12);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0xFF;
    }
    final encoded = Uint8List.fromList(pin.codeUnits);
    final n = encoded.length < 12 ? encoded.length : 12;
    bytes.setRange(0, n, encoded);
    return bytes;
  }
}
