// SignBridge — Callback poster (fire-and-forget)

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../protocol/models.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

class CallbackPoster {
  final Dio _dio;

  CallbackPoster({Dio? dio}) : _dio = dio ?? Dio();

  /// POST a progress callback. Errors are logged but never thrown (fire-and-forget).
  Future<void> postProgress(
    CallbacksConfig callbacks,
    ProgressCallbackPayload payload,
  ) async {
    if (callbacks.progress == null) return;
    await _post(callbacks.progress!, payload.toJson(), callbacks.headers);
  }

  /// POST a success callback. Errors are logged but never thrown.
  Future<void> postSuccess(
    CallbacksConfig callbacks,
    SuccessCallbackPayload payload,
  ) async {
    await _post(callbacks.onSuccess, payload.toJson(), callbacks.headers);
  }

  /// POST an error callback. Errors are logged but never thrown.
  Future<void> postError(
    CallbacksConfig callbacks,
    ErrorCallbackPayload payload,
  ) async {
    await _post(callbacks.onError, payload.toJson(), callbacks.headers);
  }

  Future<void> _post(
    String url,
    Map<String, dynamic> body,
    Map<String, String>? headers,
  ) async {
    try {
      _log.d('Posting callback to $url');
      await _dio.post(
        url,
        data: body,
        options: Options(headers: headers),
      );
    } catch (e) {
      // Fire-and-forget: log but don't propagate
      _log.w('Callback POST to $url failed: $e');
    }
  }
}
