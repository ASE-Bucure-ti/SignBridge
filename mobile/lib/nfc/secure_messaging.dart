// SignBridge — Secure Messaging (SM) wrapper for APDUs after PACE
//
// After PACE establishes session keys (KS_ENC, KS_MAC), all APDUs must be
// wrapped: data encrypted with AES-CBC, MAC computed with AES-CMAC over
// the padded APDU structure, and a Send Sequence Counter (SSC) incremented
// for each command/response pair.
//
// References: BSI TR-03110, ISO 7816-4 Secure Messaging

import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'apdu.dart';

/// TLV tags used in SM-wrapped APDUs.
class SmTag {
  static const int paddingContentIndicator =
      0x87; // encrypted data (with padding indicator)
  static const int cryptogram = 0x85; // encrypted data (no padding indicator)
  static const int mac = 0x8E; // MAC value
  static const int statusWord = 0x99; // protected SW1-SW2
  static const int le = 0x97; // protected Le
}

/// Holds the Secure Messaging session state.
class SecureMessaging {
  final Uint8List ksEnc; // AES encryption key
  final Uint8List ksMac; // AES-CMAC key
  Uint8List ssc; // Send Sequence Counter (big-endian, typically 8 or 16 bytes)

  SecureMessaging({
    required this.ksEnc,
    required this.ksMac,
    required this.ssc,
  });

  /// Increment the SSC by 1 (big-endian).
  void incrementSsc() {
    for (var i = ssc.length - 1; i >= 0; i--) {
      ssc[i]++;
      if (ssc[i] != 0) break; // no carry
    }
  }

  /// Wrap a command APDU with Secure Messaging.
  CommandApdu wrapCommand(CommandApdu cmd) {
    incrementSsc();

    // Build the masked CLA (set SM bit 0x0C)
    final maskedCla = cmd.cla | 0x0C;

    // Header for MAC: CLA|0x0C INS P1 P2, padded to block boundary
    final header = _pad(
      Uint8List.fromList([maskedCla, cmd.ins, cmd.p1, cmd.p2]),
    );

    // Build data objects for MAC computation + command data
    final dataObjects = BytesBuilder();

    // DO'87 — Encrypted data (if command has data)
    Uint8List? do87;
    if (cmd.data != null && cmd.data!.isNotEmpty) {
      final paddedData = _pad(cmd.data!);
      final encrypted = _encryptAesCbc(paddedData);
      // Tag 87 + length + 01 (padding indicator) + encrypted
      final do87Builder = BytesBuilder();
      do87Builder.addByte(SmTag.paddingContentIndicator);
      _addLength(do87Builder, 1 + encrypted.length);
      do87Builder.addByte(0x01); // padding content indicator
      do87Builder.add(encrypted);
      do87 = do87Builder.toBytes();
      dataObjects.add(do87);
    }

    // DO'97 — Expected response length (Le)
    Uint8List? do97;
    if (cmd.le != null) {
      do97 = Uint8List.fromList([SmTag.le, 0x01, cmd.le! & 0xFF]);
      dataObjects.add(do97);
    }

    // Compute MAC over: SSC || header || DO'87 || DO'97
    final macInput = BytesBuilder();
    macInput.add(ssc);
    macInput.add(header);
    if (do87 != null) macInput.add(do87);
    if (do97 != null) macInput.add(do97);

    final macData = _pad(macInput.toBytes());
    final mac = _computeCmac(macData);

    // DO'8E — MAC (8 bytes)
    dataObjects.addByte(SmTag.mac);
    dataObjects.addByte(0x08);
    dataObjects.add(mac.sublist(0, 8));

    return CommandApdu(
      cla: maskedCla,
      ins: cmd.ins,
      p1: cmd.p1,
      p2: cmd.p2,
      data: dataObjects.toBytes(),
      le: 0, // always request max in SM
    );
  }

  /// Unwrap a SM-wrapped response APDU. Returns the decrypted data.
  /// Throws if MAC verification fails.
  ResponseApdu unwrapResponse(ResponseApdu resp) {
    incrementSsc();

    if (!resp.isOk && !resp.hasMoreData) {
      // SW indicates error — no SM wrapping to decode
      return resp;
    }

    final raw = resp.data;
    if (raw.isEmpty) {
      return ResponseApdu(Uint8List(0), resp.sw);
    }

    // Parse TLV objects from response data
    Uint8List? encryptedData;
    Uint8List? protectedSw;
    Uint8List? receivedMac;

    var offset = 0;
    while (offset < raw.length) {
      final tag = raw[offset++];
      final (length, newOffset) = _readLength(raw, offset);
      offset = newOffset;

      if (tag == SmTag.paddingContentIndicator) {
        // Skip padding indicator byte (0x01)
        encryptedData = raw.sublist(offset + 1, offset + length);
      } else if (tag == SmTag.cryptogram) {
        encryptedData = raw.sublist(offset, offset + length);
      } else if (tag == SmTag.statusWord) {
        protectedSw = raw.sublist(offset, offset + length);
      } else if (tag == SmTag.mac) {
        receivedMac = raw.sublist(offset, offset + length);
      }
      offset += length;
    }

    // Verify MAC
    if (receivedMac != null) {
      // Reconstruct MAC input: SSC || DO'87/85 || DO'99
      final macInput = BytesBuilder();
      macInput.add(ssc);

      // Re-find the DO'87/85 and DO'99 raw TLV in the original data
      offset = 0;
      while (offset < raw.length) {
        final tag = raw[offset];
        final tagStart = offset;
        offset++;
        final (length, newOffset) = _readLength(raw, offset);
        offset = newOffset + length;

        if (tag == SmTag.paddingContentIndicator ||
            tag == SmTag.cryptogram ||
            tag == SmTag.statusWord) {
          macInput.add(raw.sublist(tagStart, offset));
        }
      }

      final macData = _pad(macInput.toBytes());
      final expectedMac = _computeCmac(macData);

      if (!_constantTimeEquals(receivedMac, expectedMac.sublist(0, 8))) {
        throw StateError('Secure Messaging MAC verification failed');
      }
    }

    // Decrypt data
    Uint8List decryptedData;
    if (encryptedData != null) {
      decryptedData = _unpad(_decryptAesCbc(Uint8List.fromList(encryptedData)));
    } else {
      decryptedData = Uint8List(0);
    }

    // Reconstruct status word
    int sw;
    if (protectedSw != null && protectedSw.length == 2) {
      sw = (protectedSw[0] << 8) | protectedSw[1];
    } else {
      sw = resp.sw;
    }

    return ResponseApdu(decryptedData, sw);
  }

  // ── AES-CBC with zero IV ──────────────────────────────────────────────────

  Uint8List _encryptAesCbc(Uint8List data) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        true,
        ParametersWithIV(KeyParameter(ksEnc), Uint8List(16)),
      ); // zero IV
    return _processBlocks(cipher, data);
  }

  Uint8List _decryptAesCbc(Uint8List data) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV(KeyParameter(ksEnc), Uint8List(16)),
      ); // zero IV
    return _processBlocks(cipher, data);
  }

  static Uint8List _processBlocks(BlockCipher cipher, Uint8List input) {
    final output = Uint8List(input.length);
    final blockSize = cipher.blockSize;
    for (var i = 0; i < input.length; i += blockSize) {
      cipher.processBlock(input, i, output, i);
    }
    return output;
  }

  // ── AES-CMAC (RFC 4493) ──────────────────────────────────────────────────

  Uint8List _computeCmac(Uint8List data) {
    final cmac = CMac(AESEngine(), 128)..init(KeyParameter(ksMac));
    return cmac.process(data);
  }

  // ── ISO 9797-1 Padding Method 2 ──────────────────────────────────────────

  /// Pad data to AES block size (16 bytes) using 80 00 ... 00 padding.
  static Uint8List _pad(Uint8List data) {
    const blockSize = 16;
    final padLen = blockSize - ((data.length + 1) % blockSize);
    final padded = Uint8List(data.length + 1 + padLen);
    padded.setRange(0, data.length, data);
    padded[data.length] = 0x80;
    // Remaining bytes are already 0x00
    return padded;
  }

  /// Remove ISO 9797-1 Method 2 padding.
  static Uint8List _unpad(Uint8List data) {
    for (var i = data.length - 1; i >= 0; i--) {
      if (data[i] == 0x80) {
        return data.sublist(0, i);
      }
      if (data[i] != 0x00) {
        throw StateError('Invalid padding');
      }
    }
    throw StateError('Invalid padding: no 0x80 marker found');
  }

  // ── TLV length parsing (DER) ─────────────────────────────────────────────

  static (int, int) _readLength(Uint8List data, int offset) {
    final first = data[offset++];
    if (first < 0x80) {
      return (first, offset);
    }
    final numBytes = first & 0x7F;
    var length = 0;
    for (var i = 0; i < numBytes; i++) {
      length = (length << 8) | data[offset++];
    }
    return (length, offset);
  }

  static void _addLength(BytesBuilder builder, int length) {
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

  // ── Constant-time comparison ──────────────────────────────────────────────

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
