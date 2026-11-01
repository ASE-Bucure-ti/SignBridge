// Maps engine progress status keys/strings to localized UI text.

import 'app_localizations.dart';

String localizeStatus(AppLocalizations l10n, String status) {
  if (status.startsWith('Signing document ') && status.endsWith('...')) {
    final n = int.tryParse(
      status.replaceFirst('Signing document ', '').replaceAll('...', ''),
    );
    if (n != null) return l10n.statusSigningDocumentN(n);
  }

  switch (status) {
    case 'Preparing...':
    case 'Preparing…':
      return l10n.statusPreparing;
    case 'Checking CAN...':
    case 'Checking CAN…':
      return l10n.statusCheckingCan;
    case 'Enter CAN':
      return l10n.statusEnterCan;
    case 'Enter your eSign PIN':
    case 'Enter your signing PIN':
      return l10n.statusEnterPin;
    case 'Tap your eID card...':
    case 'Tap your eID card…':
    case 'Hold your eID card...':
    case 'Hold your eID card…':
      return l10n.statusTapCard;
    case 'Authenticating...':
    case 'Authenticating…':
      return l10n.statusAuthenticating;
    case 'Reading certificate...':
    case 'Reading certificate…':
      return l10n.statusReadingCertificate;
    case 'Preparing document...':
    case 'Preparing document…':
      return l10n.statusPreparingDocument;
    case 'Verifying PIN...':
    case 'Verifying PIN…':
      return l10n.statusVerifyingPin;
    case 'Signing document...':
    case 'Signing document…':
      return l10n.statusSigningDocument;
    case 'Uploading...':
    case 'Uploading…':
      return l10n.statusUploading;
    case 'Writing signed PDF...':
    case 'Writing signed PDF…':
      return l10n.statusWritingSignedPdf;
    case 'Done':
      return l10n.statusDone;
    default:
      return status;
  }
}
