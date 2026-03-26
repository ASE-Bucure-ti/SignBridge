// SignBridge — Request handler: deep link → parse → validate → engine

import 'dart:convert';
import 'package:logger/logger.dart';
import '../protocol/models.dart';
import '../protocol/validator.dart';
import '../protocol/errors.dart';
import 'engine.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

class RequestHandler {
  final Engine _engine;

  RequestHandler({Engine? engine}) : _engine = engine ?? Engine();

  /// Parse a deep link URI into a [SignRequest].
  ///
  /// Supports two forms:
  /// - `signbridge://sign?payload=<base64url-encoded-JSON>`
  /// - `signbridge://sign?ref=<id>&endpoint=<url>` (future: fetch full payload)
  SignRequest parseDeepLink(Uri uri) {
    final payload = uri.queryParameters['payload'];
    if (payload == null || payload.isEmpty) {
      throw const SigningError(
        ErrorCode.badRequest,
        'Deep link missing payload parameter',
      );
    }

    try {
      final jsonString = utf8.decode(
        base64Url.decode(base64Url.normalize(payload)),
      );
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return SignRequest.fromJson(json);
    } catch (e) {
      if (e is SigningError) rethrow;
      throw SigningError(ErrorCode.badRequest, 'Failed to decode payload: $e');
    }
  }

  /// Validate the request and return the ACK response.
  SignResponse validateAndAck(SignRequest request) {
    try {
      validateRequest(request);
      _log.i('Request ${request.requestId} validated');

      return SignResponse(
        protocolVersion: request.protocolVersion,
        requestId: request.requestId,
        status: 'accepted',
      );
    } on SigningError catch (e) {
      _log.e('Validation failed: $e');
      return SignResponse(
        protocolVersion: request.protocolVersion,
        requestId: request.requestId,
        status: 'error',
        errors: [ErrorObject(code: e.code, message: e.message, id: e.objectId)],
      );
    }
  }

  /// Process the request (download → sign → upload).
  /// This is the async part that runs after ACK.
  Future<void> processRequest(
    SignRequest request, {
    required CanRequester requestCan,
    required PinRequester requestPin,
    EngineProgressCallback? onProgress,
  }) async {
    await _engine.process(
      request,
      requestCan: requestCan,
      requestPin: requestPin,
      onProgress: onProgress,
    );
  }
}
