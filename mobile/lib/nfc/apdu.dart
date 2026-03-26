// SignBridge — APDU command/response builders (ISO 7816-4)

import 'dart:typed_data';

/// Status word constants
class SW {
  static const int ok = 0x9000;
  static const int moreBytesPrefix = 0x61; // 61XX → XX more bytes available
  static const int wrongLength = 0x6700;
  static const int securityNotSatisfied = 0x6982;
  static const int authMethodBlocked = 0x6983;
  static const int conditionsNotSatisfied = 0x6985;
  static const int wrongData = 0x6A80;
  static const int fileNotFound = 0x6A82;
  static const int incorrectP1P2 = 0x6A86;
  static const int wrongPinPrefix = 0x63C0; // 63CX → X retries remaining
  static const int insNotSupported = 0x6D00;
  static const int claNotSupported = 0x6E00;

  /// Check if SW indicates more data available (61XX).
  static bool hasMoreData(int sw) => (sw >> 8) == moreBytesPrefix;

  /// Extract remaining byte count from 61XX.
  static int remainingBytes(int sw) => sw & 0xFF;

  /// Check if SW indicates wrong PIN with retry counter (63CX).
  static bool isWrongPin(int sw) => (sw & 0xFFF0) == wrongPinPrefix;

  /// Extract retry count from 63CX.
  static int pinRetries(int sw) => sw & 0x0F;
}

/// Raw APDU command builder.
class CommandApdu {
  final int cla;
  final int ins;
  final int p1;
  final int p2;
  final Uint8List? data;
  final int? le; // expected response length

  const CommandApdu({
    required this.cla,
    required this.ins,
    required this.p1,
    required this.p2,
    this.data,
    this.le,
  });

  /// Encode to byte array for transmission.
  Uint8List encode() {
    final hasData = data != null && data!.isNotEmpty;
    final hasLe = le != null;

    final buf = BytesBuilder();
    buf.addByte(cla);
    buf.addByte(ins);
    buf.addByte(p1);
    buf.addByte(p2);

    if (hasData) {
      buf.addByte(data!.length); // Lc
      buf.add(data!);
    }

    if (hasLe) {
      buf.addByte(le! & 0xFF); // Le (0x00 = 256)
    }

    return buf.toBytes();
  }

  @override
  String toString() {
    final hex = encode()
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    return 'C-APDU: $hex';
  }
}

/// Parsed APDU response.
class ResponseApdu {
  final Uint8List data;
  final int sw; // status word (2 bytes)

  const ResponseApdu(this.data, this.sw);

  int get sw1 => (sw >> 8) & 0xFF;
  int get sw2 => sw & 0xFF;

  bool get isOk => sw == SW.ok;
  bool get hasMoreData => SW.hasMoreData(sw);
  bool get isWrongPin => SW.isWrongPin(sw);
  int get pinRetries => SW.pinRetries(sw);

  /// Parse raw response bytes into ResponseApdu.
  factory ResponseApdu.fromBytes(Uint8List bytes) {
    if (bytes.length < 2) {
      throw ArgumentError('Response too short: ${bytes.length} bytes');
    }
    final sw = (bytes[bytes.length - 2] << 8) | bytes[bytes.length - 1];
    final data = bytes.sublist(0, bytes.length - 2);
    return ResponseApdu(Uint8List.fromList(data), sw);
  }

  @override
  String toString() {
    final swHex = sw.toRadixString(16).padLeft(4, '0');
    return 'R-APDU: ${data.length} bytes, SW=$swHex';
  }
}

// ── Standard APDU builders ───────────────────────────────────────────────────

/// SELECT by AID (P1=04, P2=0C for no FCI).
CommandApdu selectByAid(Uint8List aid) =>
    CommandApdu(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x0C, data: aid);

/// SELECT by file ID (P1=02 = select child EF under current DF).
CommandApdu selectFile(int fileId) => CommandApdu(
  cla: 0x00,
  ins: 0xA4,
  p1: 0x02,
  p2: 0x0C,
  data: Uint8List.fromList([(fileId >> 8) & 0xFF, fileId & 0xFF]),
);

/// SELECT Master File.
CommandApdu selectMf() =>
    const CommandApdu(cla: 0x00, ins: 0xA4, p1: 0x00, p2: 0x0C);

/// READ BINARY from current EF at [offset], requesting [length] bytes.
CommandApdu readBinary(int offset, int length) => CommandApdu(
  cla: 0x00,
  ins: 0xB0,
  p1: (offset >> 8) & 0x7F,
  p2: offset & 0xFF,
  le: length,
);

/// VERIFY PIN (P2 selects the PIN reference: 0x01=identity-PIN, 0x81=eSign-PIN).
CommandApdu verifyPin(int pinRef, Uint8List pinData) =>
    CommandApdu(cla: 0x00, ins: 0x20, p1: 0x00, p2: pinRef, data: pinData);

/// MSE:SET — Manage Security Environment (set cryptographic template).
/// [p1] = 0x41 (computation) or 0xC1 (decipherment)
/// [p2] = 0xA4 (authentication) or 0xB6 (digital signature)
CommandApdu mseSet({
  required int p1,
  required int p2,
  required Uint8List data,
}) => CommandApdu(cla: 0x00, ins: 0x22, p1: p1, p2: p2, data: data);

/// INTERNAL AUTHENTICATE — Card signs the given data (hash) using the current security env.
CommandApdu internalAuthenticate(Uint8List data) => CommandApdu(
  cla: 0x00,
  ins: 0x88,
  p1: 0x00,
  p2: 0x00,
  data: data,
  le: 0, // 0 = 256 bytes max
);

/// GET RESPONSE — Retrieve remaining response data after 61XX.
CommandApdu getResponse(int length) =>
    CommandApdu(cla: 0x00, ins: 0xC0, p1: 0x00, p2: 0x00, le: length);

/// GENERAL AUTHENTICATE (for PACE) — CLA=0x10 for chaining, 0x00 for last.
CommandApdu generalAuthenticate({
  required Uint8List data,
  bool isChaining = true,
}) => CommandApdu(
  cla: isChaining ? 0x10 : 0x00,
  ins: 0x86,
  p1: 0x00,
  p2: 0x00,
  data: data,
  le: isChaining ? null : 0,
);

/// Encode a PIN string into padded 8-byte format (ISO 9564 format 2).
/// PIN digits are BCD-encoded, padded with 0xFF.
Uint8List encodePinForVerify(String pin) {
  final bytes = Uint8List(8);
  // BCD encoding: first nibble = 0x2, second nibble = pin length
  bytes[0] = 0x20 | (pin.length & 0x0F);
  for (var i = 0; i < pin.length; i++) {
    final digit = pin.codeUnitAt(i) - 0x30;
    final byteIndex = 1 + (i ~/ 2);
    if (i.isEven) {
      bytes[byteIndex] = (digit << 4) | 0x0F;
    } else {
      bytes[byteIndex] = (bytes[byteIndex] & 0xF0) | digit;
    }
  }
  // Pad remaining with 0xFF
  for (var i = 1 + ((pin.length + 1) ~/ 2); i < 8; i++) {
    bytes[i] = 0xFF;
  }
  return bytes;
}

/// Parse a hex string like "A0000002471001" to bytes.
Uint8List hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

/// Encode bytes to hex string.
String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
