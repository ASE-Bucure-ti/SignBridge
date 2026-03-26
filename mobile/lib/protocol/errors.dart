// SignBridge Protocol v1.0.3 — Error types

enum ErrorCode {
  badRequest('BAD_REQUEST'),
  unsupportedVersion('UNSUPPORTED_VERSION'),
  unsupportedType('UNSUPPORTED_TYPE'),
  certNotFound('CERT_NOT_FOUND'),
  downloadFailed('DOWNLOAD_FAILED'),
  signFailed('SIGN_FAILED'),
  uploadFailed('UPLOAD_FAILED'),
  callbackFailed('CALLBACK_FAILED'),
  progressEndpointFailed('PROGRESS_ENDPOINT_FAILED'),
  timeout('TIMEOUT'),
  cancelledByUser('CANCELLED_BY_USER'),
  internalError('INTERNAL_ERROR');

  final String value;
  const ErrorCode(this.value);

  factory ErrorCode.fromJson(String json) =>
      ErrorCode.values.firstWhere((e) => e.value == json);

  String toJson() => value;
}

class SigningError implements Exception {
  final ErrorCode code;
  final String message;
  final String? objectId;

  const SigningError(this.code, this.message, {this.objectId});

  @override
  String toString() => 'SigningError(${code.value}): $message';

  Map<String, dynamic> toJson() => {
    if (objectId != null) 'id': objectId,
    'code': code.toJson(),
    'message': message,
  };
}
