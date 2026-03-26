// SignBridge — Content downloader (dio-based)

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../protocol/errors.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

class Downloader {
  final Dio _dio;

  Downloader({Dio? dio}) : _dio = dio ?? Dio();

  /// Download content from [url] and return raw bytes.
  Future<Uint8List> download({
    required String url,
    String httpMethod = 'GET',
    Map<String, String>? headers,
  }) async {
    try {
      _log.i('Downloading from $url ($httpMethod)');

      final options = Options(
        method: httpMethod,
        responseType: ResponseType.bytes,
        headers: headers,
      );

      final response = await _dio.request<List<int>>(url, options: options);
      final bytes = Uint8List.fromList(response.data!);
      _log.i('Downloaded ${bytes.length} bytes');
      return bytes;
    } on DioException catch (e) {
      throw SigningError(
        ErrorCode.downloadFailed,
        'Download failed: ${e.message}',
      );
    }
  }
}
