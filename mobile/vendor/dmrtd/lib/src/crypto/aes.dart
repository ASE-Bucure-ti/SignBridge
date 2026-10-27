//  Created by Nejc Skerjanc, copyright © 2023 ZeroPass. All rights reserved.

import 'dart:typed_data';
import 'package:dmrtd/extensions.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

import '../lds/asn1ObjectIdentifiers.dart';

class AESCipherError implements Exception {
  final String message;
  AESCipherError(this.message);
  @override
  String toString() => message;
}

enum BLOCK_CIPHER_MODE { ECB, CBC }

/// Class implements AES encryption/decryption and CMAC calculation.
/// It uses pointycastle library for AES implementation.
/// CMAC mac size is fixed to 64 bits.
/// IV length is fixed to 128 bits in AES.
///
const int AES_BLOCK_SIZE = 16;

class AESCipher {
  static final _log = Logger("AESCipher");
  static final _factory = () => AESEngine();

  late KEY_LENGTH _size;

  AESCipher({required KEY_LENGTH size}) : _size = size;

  int get size {
    switch (_size) {
      case KEY_LENGTH.s128:
        return 16;
      case KEY_LENGTH.s192:
        return 24;
      case KEY_LENGTH.s256:
        return 32;
      default:
        throw AESCipherError("Invalid key size. Must be 16, 24, or 32 bytes.");
    }
  }

  //comments from docs
  // The iv must be exactly 128-bites (16 bytes) long, which is the AES block size.
  //  The key must be exactly 128-bits, 192-bits or 256-bits (i.e. 16, 24 or 32 bytes);
  //  This is what determines whether AES-128, AES-192 or AES-256 is being performed.

  Uint8List encrypt(
      {required Uint8List data,
      required Uint8List key,
      Uint8List? iv,
      BLOCK_CIPHER_MODE mode = BLOCK_CIPHER_MODE.CBC,
      bool padding = false}) {
    _log.finest(
        "AESCipher.encrypt; data size: ${data.length}, data: ${data.hex()}");
    _log.sdVerbose(
        "AESCipher.encrypt; data:${data.hex()}, key size: ${key.length}, key: ${key.hex()}");

    if (key.length != size) {
      _log.error(
          "AESCipher.encrypt; AES${size * 8} key length must be ${size * 8} bits.");
      throw AESCipherError(
          "AESCipher.encrypt; AES${size * 8} key length must be ${size * 8} bits.");
    }

    if (iv != null) {
      _log.sdVerbose(
          "AESCipher.encrypt; iv size: ${iv.length}, iv: ${iv.hex()}");
      if (iv.length != AES_BLOCK_SIZE) {
        _log.error("AESCipher.encrypt; iv length is not 128 bits.");
        throw AESCipherError("AESCipher.encrypt; iv length is not 128 bits.");
      }
    } else if (mode == BLOCK_CIPHER_MODE.CBC) {
      iv = Uint8List(AES_BLOCK_SIZE);
      _log.sdVerbose("AESCipher.encrypt; iv is null");
    }
    final paddedData;
    if (padding) {
      _log.finest("Padding data with zeros to block size: $AES_BLOCK_SIZE");
      paddedData =
          pad(data: data, blockSize: AES_BLOCK_SIZE); //AES has no padding
    } else {
      _log.finest("Data will not be padded.");
      paddedData = data;
    }
    var cipher;
    try {
      if (mode == BLOCK_CIPHER_MODE.CBC) {
        _log.sdDebug(
            'AESCipher.encrypt CBC init: keyLen=${key.length}, ivLen=${iv!.length}, dataLen=${paddedData.length}');
        cipher = CBCBlockCipher(_factory())
          ..init(true, ParametersWithIV(KeyParameter(key), iv));
      } else {
        cipher = ECBBlockCipher(_factory())
          ..init(true, KeyParameter(key)); //ECB mode
      }
    } on ArgumentError catch (e, st) {
      _log.error(
          'AESCipher.encrypt init failed: mode=$mode keyLen=${key.length} ivLen=${iv?.length} dataLen=${paddedData.length} error=$e\n$st');
      rethrow;
    }

    //return cipher.process(paddedData);
    return _processBlocks(cipher: cipher, data: paddedData);
  }

  Uint8List decrypt(
      {required Uint8List data,
      required Uint8List key,
      Uint8List? iv,
      BLOCK_CIPHER_MODE mode = BLOCK_CIPHER_MODE.CBC}) {
    _log.finest(
        "AESCipher.decrypt; data size: ${data.length}, data: ${data.hex()}");
    _log.sdVerbose(
        "AESCipher.decrypt; data: ${data.hex()}, key size: ${key.length}, key: ${key.hex()}");

    if (key.length != size) {
      _log.error(
          "AESCipher.decrypt; AES${size * 8} key length must be ${size * 8} bits.");
      throw AESCipherError(
          "AESCipher.decrypt; AES${size * 8} key length must be ${size * 8} bits.");
    }

    if (iv != null) {
      _log.sdVerbose(
          "AESCipher.decrypt; iv size: ${iv.length}, iv: ${iv.hex()}");
      if (iv.length != AES_BLOCK_SIZE) {
        _log.error("AESCipher.encrypt; iv length is not 128 bits.");
        throw AESCipherError("AESCipher.encrypt; iv length is not 128 bits.");
      }
    } else {
      iv = Uint8List(AES_BLOCK_SIZE);
      _log.sdVerbose("AESCipher.decrypt; iv is null");
    }

    var cipher;
    try {
      if (mode == BLOCK_CIPHER_MODE.CBC) {
        _log.sdDebug(
            'AESCipher.decrypt CBC init: keyLen=${key.length}, ivLen=${iv!.length}, dataLen=${data.length}');
        cipher = CBCBlockCipher(_factory())
          ..init(false, ParametersWithIV(KeyParameter(key), iv));
      } else {
        cipher = ECBBlockCipher(_factory())..init(false, KeyParameter(key));
      }
    } on ArgumentError catch (e, st) {
      _log.error(
          'AESCipher.decrypt init failed: mode=$mode keyLen=${key.length} ivLen=${iv?.length} dataLen=${data.length} error=$e\n$st');
      rethrow;
    }
    return Uint8List.fromList(
        _processBlocks(cipher: cipher, data: data).toList());
  }

  Uint8List _processBlocks(
      {required BlockCipher cipher, required Uint8List data}) {
    _log.finest("AESCipher._processBlocks; data size: ${data.length}");
    _log.sdVerbose("AESCipher._processBlocks; data: ${data.hex()}");
    final output = Uint8List(data.length);

    for (int i = 0; i < data.length; i += cipher.blockSize) {
      cipher.processBlock(data, i, output, i);
    }
    _log.sdVerbose("AESCipher._processBlocks; output data: ${output.hex()}");

    return output;
  }

  Uint8List pad({required Uint8List data, int blockSize = AES_BLOCK_SIZE}) {
    _log.finest("Padding data with zeros to block size: $blockSize");
    _log.sdVerbose("Data to pad: ${data.hex()} ");
    final padLength = blockSize - (data.length % blockSize);
    List<int> list = data.toList()..addAll(List.filled(padLength, 0));
    return Uint8List.fromList(list);
  }

  Uint8List calculateCMAC({required Uint8List data, required Uint8List key}) {
    _log.sdDebug(
        'AESCipher.calculateCMAC: keyLen=${key.length}, dataLen=${data.length}');

    if (key.length != size) {
      _log.error(
          "AESCipher.calculateCMAC; AES${size * 8} key length must be ${size * 8} bits.");
      throw AESCipherError(
          "AESCipher.calculateCMAC; AES${size * 8} key length must be ${size * 8} bits.");
    }

    final subkeys = _generateCmacSubkeys(key);
    final k1 = subkeys.$1;
    final k2 = subkeys.$2;

    final blockCount = data.isEmpty
        ? 1
        : ((data.length + AES_BLOCK_SIZE - 1) ~/ AES_BLOCK_SIZE);
    final lastBlockComplete =
        data.isNotEmpty && data.length % AES_BLOCK_SIZE == 0;

    final state = Uint8List(AES_BLOCK_SIZE);
    for (var blockIndex = 0; blockIndex < blockCount - 1; blockIndex++) {
      final start = blockIndex * AES_BLOCK_SIZE;
      final block = data.sublist(start, start + AES_BLOCK_SIZE);
      final input = _xorBlocks(state, block);
      state.setAll(0, _encryptAesBlock(input, key));
    }

    Uint8List lastBlock;
    if (lastBlockComplete) {
      final start = (blockCount - 1) * AES_BLOCK_SIZE;
      lastBlock = _xorBlocks(data.sublist(start, start + AES_BLOCK_SIZE), k1);
    } else {
      final start = blockCount > 1 ? (blockCount - 1) * AES_BLOCK_SIZE : 0;
      final tail = start < data.length ? data.sublist(start) : Uint8List(0);
      final padded = Uint8List(AES_BLOCK_SIZE);
      padded.setAll(0, tail);
      padded[tail.length] = 0x80;
      lastBlock = _xorBlocks(padded, k2);
    }

    final tag = _encryptAesBlock(_xorBlocks(state, lastBlock), key);
    return tag.sublist(0, 8);
  }

  (Uint8List, Uint8List) _generateCmacSubkeys(Uint8List key) {
    final l = _encryptAesBlock(Uint8List(AES_BLOCK_SIZE), key);
    final k1 = _doubleBlock(l);
    final k2 = _doubleBlock(k1);
    return (k1, k2);
  }

  Uint8List _encryptAesBlock(Uint8List block, Uint8List key) {
    final engine = AESEngine()..init(true, KeyParameter(key));
    final output = Uint8List(AES_BLOCK_SIZE);
    engine.processBlock(block, 0, output, 0);
    return output;
  }

  Uint8List _xorBlocks(Uint8List left, Uint8List right) {
    final output = Uint8List(AES_BLOCK_SIZE);
    for (var index = 0; index < AES_BLOCK_SIZE; index++) {
      output[index] = left[index] ^ right[index];
    }
    return output;
  }

  Uint8List _doubleBlock(Uint8List input) {
    final output = Uint8List(AES_BLOCK_SIZE);
    var carry = 0;
    for (var index = AES_BLOCK_SIZE - 1; index >= 0; index--) {
      final value = input[index];
      output[index] = ((value << 1) & 0xFF) | carry;
      carry = (value & 0x80) != 0 ? 1 : 0;
    }
    if ((input[0] & 0x80) != 0) {
      output[AES_BLOCK_SIZE - 1] ^= 0x87;
    }
    return output;
  }
}

class AESCipher128 extends AESCipher {
  AESCipher128() : super(size: KEY_LENGTH.s128);
}

class AESCipher192 extends AESCipher {
  AESCipher192() : super(size: KEY_LENGTH.s192);
}

class AESCipher256 extends AESCipher {
  AESCipher256() : super(size: KEY_LENGTH.s256);
}

class AESChiperSelector {
  static final _log = Logger("AESChiperSelector");

  static AESCipher getChiper({required KEY_LENGTH size}) {
    switch (size) {
      case KEY_LENGTH.s128:
        _log.finer("AES chiper with 128-bit key size selected.");
        return AESCipher128();
      case KEY_LENGTH.s192:
        _log.finer("AES chiper with 192-bit key size selected.");
        return AESCipher192();
      case KEY_LENGTH.s256:
        _log.finer("AES chiper with 256-bit key size selected.");
        return AESCipher256();

      default:
        _log.error("AESChiperSelector; Size is not supported.");
        throw AESCipherError("AESChiperSelector; Size is not supported.");
    }
  }
}
