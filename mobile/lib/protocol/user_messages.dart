// SignBridge — user-facing error messages (localized)

import '../l10n/app_localizations.dart';
import 'errors.dart';

/// Maps internal exceptions to short, actionable text for the UI.
String userFacingMessage(AppLocalizations l10n, Object error) {
  if (error is SigningError) {
    return _signingErrorMessage(l10n, error);
  }

  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('authenticationmethodblocked') ||
      lower.contains('pin is blocked') ||
      lower.contains('too many wrong')) {
    return l10n.errorPinBlocked;
  }

  if (lower.contains('pace') ||
      lower.contains('can key') ||
      lower.contains('wrong can') ||
      lower.contains('mutual authentication')) {
    return l10n.errorWrongCan;
  }

  if (lower.contains('tag was lost') ||
      lower.contains('tag is out of range') ||
      lower.contains('communication error') ||
      lower.contains('nfcprovidererror') ||
      lower.contains('session invalidated')) {
    return l10n.errorNfcLost;
  }

  if (lower.contains('nfc') &&
      (lower.contains('not available') || lower.contains('disabled'))) {
    return l10n.errorNfcUnavailable;
  }

  if (lower.contains('ce8e') || lower.contains('signing certificate')) {
    return l10n.errorCertRead;
  }

  if (lower.contains('cancelled') || lower.contains('canceled')) {
    return l10n.errorCancelled;
  }

  return raw
      .replaceFirst(RegExp(r'^(Exception|StateError|ArgumentError):\s*'), '')
      .trim();
}

String _signingErrorMessage(AppLocalizations l10n, SigningError error) {
  switch (error.code) {
    case ErrorCode.cancelledByUser:
      return l10n.errorCancelled;
    case ErrorCode.badRequest:
      if (error.message.toLowerCase().contains('wrong pin')) {
        final match = RegExp(r'(\d+)\s*retries').firstMatch(error.message);
        final left = int.tryParse(match?.group(1) ?? '');
        if (left != null) return l10n.errorWrongPinRetries(left);
        return l10n.errorWrongPin;
      }
      if (error.message.toLowerCase().contains('does not match')) {
        return l10n.errorCertMismatch;
      }
      return error.message;
    case ErrorCode.downloadFailed:
      return l10n.errorDownload;
    case ErrorCode.uploadFailed:
      return l10n.errorUpload;
    case ErrorCode.signFailed:
      final remapped = userFacingMessage(l10n, Exception(error.message));
      if (remapped == l10n.errorWrongCan ||
          remapped == l10n.errorNfcLost ||
          remapped == l10n.errorPinBlocked ||
          remapped == l10n.errorCertRead ||
          remapped == l10n.errorNfcUnavailable ||
          remapped == l10n.errorCancelled) {
        return remapped;
      }
      return l10n.errorSignFailed;
    case ErrorCode.timeout:
      return l10n.errorTimeout;
    case ErrorCode.certNotFound:
      return l10n.errorCertNotFound;
    case ErrorCode.unsupportedType:
      return l10n.errorUnsupportedType;
    case ErrorCode.unsupportedVersion:
      return l10n.errorUnsupportedVersion;
    default:
      return error.message.isNotEmpty ? error.message : l10n.errorGeneric;
  }
}

/// Wrap low-level card/NFC failures into [SigningError].
///
/// Keeps an English technical [SigningError.message] for logs; the UI must
/// call [userFacingMessage] with [AppLocalizations].
SigningError asSigningError(Object error, {String? objectId}) {
  if (error is SigningError) return error;
  return SigningError(
    ErrorCode.signFailed,
    error.toString(),
    objectId: objectId,
  );
}
