// SignBridge — Content uploader

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../protocol/errors.dart';
import '../protocol/models.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

class Uploader {
  final Dio _dio;

  Uploader({Dio? dio}) : _dio = dio ?? Dio();

  /// Upload signed content to [config.uploadUrl].
  /// Returns the response status code and body.
  Future<(int statusCode, String body)> upload({
    required UploadConfig config,
    required Uint8List data,
  }) async {
    try {
      final method = config.httpMethod ?? 'PUT';
      _log.i('Uploading ${data.length} bytes to ${config.uploadUrl} ($method)');

      final contentType = switch (config.signedContentType) {
        SignedContentType.pdf => 'application/pdf',
        SignedContentType.xml => 'application/xml',
        SignedContentType.binary => 'application/octet-stream',
        SignedContentType.string => 'text/plain',
      };

      // Send the byte list directly so Dio sets Content-Length.
      // A Stream body becomes chunked transfer and many servers
      // (including our E2E harness) then read zero bytes.
      final options = Options(
        method: method,
        headers: {
          'Content-Type': contentType,
          'Content-Length': data.length.toString(),
          ...?config.headers,
        },
        responseType: ResponseType.plain,
      );

      final response = await _dio.request<String>(
        config.uploadUrl,
        data: data,
        options: options,
      );

      final statusCode = response.statusCode ?? 200;
      final body = response.data ?? '';
      _log.i('Upload complete: $statusCode');
      return (statusCode, body);
    } on DioException catch (e) {
      throw SigningError(ErrorCode.uploadFailed, 'Upload failed: ${e.message}');
    }
  }
}
