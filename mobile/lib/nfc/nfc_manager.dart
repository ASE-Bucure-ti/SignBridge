// SignBridge — NFC session lifecycle manager
//
// Wraps flutter_nfc_kit to provide:
// - Tag discovery + ISO-DEP connection
// - Raw APDU transceiving
// - GET RESPONSE chaining (for long responses)
// - Session timeout management
// - Cleanup guarantees

import 'dart:typed_data';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:logger/logger.dart';
import 'apdu.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// NFC session manager — handles tag discovery and APDU transceiving.
class NfcManager {
  bool _sessionActive = false;

  /// Whether an NFC session is currently active.
  bool get isSessionActive => _sessionActive;

  /// Check if the device has NFC hardware.
  Future<bool> isNfcAvailable() async {
    final availability = await FlutterNfcKit.nfcAvailability;
    return availability == NFCAvailability.available;
  }

  /// Start an NFC session: poll for a tag and connect.
  /// Returns the discovered tag info.
  /// On iOS, [alertMessage] is shown in the NFC system dialog.
  Future<NFCTag> startSession({
    String alertMessage = 'Hold your eID card to the back of the phone',
  }) async {
    _log.i('Starting NFC session...');
    final tag = await FlutterNfcKit.poll(iosAlertMessage: alertMessage);
    _sessionActive = true;
    _log.i('NFC tag discovered: ${tag.type}, ${tag.standard}');
    return tag;
  }

  /// Send a raw APDU command to the card and return the response.
  /// Handles GET RESPONSE chaining automatically.
  Future<ResponseApdu> transceive(CommandApdu command) async {
    if (!_sessionActive) {
      throw StateError('NFC session not active');
    }

    _log.d('>>> ${command.toString()}');
    final responseBytes = await _transceiveRaw(command.encode());
    var response = ResponseApdu.fromBytes(responseBytes);

    // Handle GET RESPONSE chaining (61XX)
    if (response.hasMoreData) {
      final fullData = BytesBuilder();
      fullData.add(response.data);

      while (response.hasMoreData) {
        final remaining = SW.remainingBytes(response.sw);
        final getResp = getResponse(remaining);
        _log.d('>>> GET RESPONSE ($remaining bytes)');
        final chainResp = await _transceiveRaw(getResp.encode());
        response = ResponseApdu.fromBytes(chainResp);
        fullData.add(response.data);
      }

      response = ResponseApdu(fullData.toBytes(), response.sw);
    }

    _log.d('<<< ${response.toString()}');
    return response;
  }

  /// Send raw bytes and get raw response bytes.
  /// This is the low-level transceive used by PACE before SM is established.
  Future<Uint8List> transceiveRaw(Uint8List command) async {
    if (!_sessionActive) {
      throw StateError('NFC session not active');
    }
    return _transceiveRaw(command);
  }

  Future<Uint8List> _transceiveRaw(Uint8List command) async {
    final hex = bytesToHex(command);
    final responseHex = await FlutterNfcKit.transceive(hex);
    return hexToBytes(responseHex);
  }

  /// Update the iOS NFC alert message during an active session.
  Future<void> setAlertMessage(String message) async {
    await FlutterNfcKit.setIosAlertMessage(message);
  }

  /// End the NFC session.
  Future<void> endSession({String? iosAlertMessage}) async {
    if (!_sessionActive) return;
    _log.i('Ending NFC session');
    try {
      await FlutterNfcKit.finish(iosAlertMessage: iosAlertMessage);
    } finally {
      _sessionActive = false;
    }
  }

  /// End the session with an error message (iOS).
  Future<void> endSessionWithError(String errorMessage) async {
    if (!_sessionActive) return;
    _log.w('Ending NFC session with error: $errorMessage');
    try {
      await FlutterNfcKit.finish(iosErrorMessage: errorMessage);
    } finally {
      _sessionActive = false;
    }
  }
}
