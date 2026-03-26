// SignBridge Protocol v1.0.3 — Request validation

import 'errors.dart';
import 'models.dart';

const String supportedVersion = '1.0.3';

/// Validates a [SignRequest] and throws [SigningError] on failure.
void validateRequest(SignRequest request) {
  if (request.protocolVersion != supportedVersion) {
    throw SigningError(
      ErrorCode.unsupportedVersion,
      'Unsupported protocol version: ${request.protocolVersion} '
      '(expected $supportedVersion)',
    );
  }

  if (request.requestId.isEmpty) {
    throw SigningError(ErrorCode.badRequest, 'requestId is required');
  }

  if (request.appId.isEmpty) {
    throw SigningError(ErrorCode.badRequest, 'appId is required');
  }

  if (request.cert.certId.isEmpty) {
    throw SigningError(ErrorCode.badRequest, 'cert.certId is required');
  }

  final hasObjects = request.objects != null && request.objects!.isNotEmpty;
  final hasGroups =
      request.objectGroups != null && request.objectGroups!.isNotEmpty;

  if (!hasObjects && !hasGroups) {
    throw SigningError(
      ErrorCode.badRequest,
      'Request must contain at least one object or objectGroup',
    );
  }

  if (hasObjects) {
    for (final obj in request.objects!) {
      _validateObject(obj);
    }
  }

  if (hasGroups) {
    for (final group in request.objectGroups!) {
      _validateGroup(group);
    }
  }
}

void _validateObject(SignObject obj) {
  if (obj.id.isEmpty) {
    throw SigningError(ErrorCode.badRequest, 'Object id is required');
  }

  if (obj.dataType == DataType.pdf && obj.pdfOptions == null) {
    throw SigningError(
      ErrorCode.badRequest,
      'pdfOptions.label is required for PDF objects',
      objectId: obj.id,
    );
  }

  if (obj.content.isRemote && obj.content.remote!.downloadUrl.isEmpty) {
    throw SigningError(
      ErrorCode.badRequest,
      'downloadUrl is required for remote content',
      objectId: obj.id,
    );
  }

  if (obj.content.isInline && obj.content.inline!.content.isEmpty) {
    throw SigningError(
      ErrorCode.badRequest,
      'content is required for inline content',
      objectId: obj.id,
    );
  }

  if (obj.upload.uploadUrl.isEmpty) {
    throw SigningError(
      ErrorCode.badRequest,
      'upload.uploadUrl is required',
      objectId: obj.id,
    );
  }

  _validateCallbacks(obj.callbacks, obj.id);
}

void _validateGroup(ObjectGroup group) {
  if (group.objects.isEmpty) {
    throw SigningError(ErrorCode.badRequest, 'ObjectGroup must have objects');
  }

  if (group.mode == 'remote' &&
      (group.downloadUrl == null || group.downloadUrl!.isEmpty)) {
    throw SigningError(
      ErrorCode.badRequest,
      'downloadUrl is required for remote objectGroups',
    );
  }

  _validateCallbacks(group.callbacks, null);

  if (group.upload.uploadUrl.isEmpty) {
    throw SigningError(
      ErrorCode.badRequest,
      'upload.uploadUrl is required for objectGroup',
    );
  }
}

void _validateCallbacks(CallbacksConfig callbacks, String? objectId) {
  if (callbacks.onSuccess.isEmpty) {
    throw SigningError(
      ErrorCode.badRequest,
      'callbacks.onSuccess is required',
      objectId: objectId,
    );
  }
  if (callbacks.onError.isEmpty) {
    throw SigningError(
      ErrorCode.badRequest,
      'callbacks.onError is required',
      objectId: objectId,
    );
  }
}
