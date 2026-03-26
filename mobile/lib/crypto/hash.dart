// SignBridge — SHA hash utilities
//
// Thin wrappers over pointycastle for SHA-256 and SHA-384.
// Used by: CMS builder (signedAttributes hash, messageDigest),
//          PDF signer (byte-range digest).

import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';

/// Compute SHA-256 digest.
Uint8List sha256(Uint8List data) {
  final d = Digest('SHA-256');
  return d.process(data);
}

/// Compute SHA-384 digest.
Uint8List sha384(Uint8List data) {
  final d = Digest('SHA-384');
  return d.process(data);
}

/// Compute SHA-256 digest incrementally from chunks.
class Sha256Sink {
  final _digest = Digest('SHA-256');
  final _buffer = BytesBuilder();

  void add(Uint8List chunk) => _buffer.add(chunk);

  Uint8List finish() => _digest.process(_buffer.toBytes());
}

/// Compute SHA-384 digest incrementally from chunks.
class Sha384Sink {
  final _digest = Digest('SHA-384');
  final _buffer = BytesBuilder();

  void add(Uint8List chunk) => _buffer.add(chunk);

  Uint8List finish() => _digest.process(_buffer.toBytes());
}
