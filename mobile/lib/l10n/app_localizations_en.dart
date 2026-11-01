// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SignBridge';

  @override
  String get appSubtitle => 'SignBridge Mobile';

  @override
  String get waitingForRequest => 'Waiting for a signing request…';

  @override
  String get homeDeepLinkHint =>
      'Open a document from your browser to start signing.\nThe app receives the request via deep link.';

  @override
  String get canSaved => 'CAN saved on this phone';

  @override
  String get canNotSet => 'CAN not set — tap to add';

  @override
  String get changeCan => 'Change CAN';

  @override
  String get setCan => 'Set CAN';

  @override
  String get saveCan => 'Save CAN';

  @override
  String get replaceCan => 'Replace CAN';

  @override
  String get canScreenTitle => 'Card Access Number (CAN)';

  @override
  String get canFirstTimeHint =>
      'Before the first signature, save the CAN from your Romanian electronic identity card (CEI). You only need to do this once on this phone.';

  @override
  String get canAlreadySaved =>
      'A CAN is already saved on this phone. You can edit it below. It is only replaced after you confirm.';

  @override
  String get replaceCanConfirmTitle => 'Replace CAN?';

  @override
  String get replaceCanConfirmBody =>
      'Are you sure you want to replace the saved CAN on this phone?';

  @override
  String get confirm => 'Confirm';

  @override
  String get cancel => 'Cancel';

  @override
  String get enterSixDigitCan => 'Enter the 6-digit CAN';

  @override
  String get canLocationHint =>
      'The CAN is printed on the front of the card, bottom-right, under the expiry date.';

  @override
  String get whereToFindOnCei => 'Where to find it on the CEI';

  @override
  String get ceiFrontTitle => 'Front view';

  @override
  String get ceiBackTitle => 'Back view';

  @override
  String get ceiFront1 => 'Flags of the European Union and Romania';

  @override
  String get ceiFront2 => 'Coat of arms of Romania';

  @override
  String get ceiFront3 => 'Holder’s personal data';

  @override
  String get ceiFront4 => 'Identity document number';

  @override
  String get ceiFront5 => 'Identity document expiry date';

  @override
  String get ceiFront6 => 'CAN number';

  @override
  String get ceiFront7 => 'Holder’s handwritten signature';

  @override
  String get ceiFront8 => '“Electronic document” symbol';

  @override
  String get ceiBack1 => 'Chip (electronic storage medium)';

  @override
  String get ceiBack2 => 'Issue date and issuing authority';

  @override
  String get ceiBack3 => 'Holder’s photograph and the text “ROU”';

  @override
  String get ceiBack4 => 'MRZ (Machine Readable Zone), for optical reading';

  @override
  String get ceiSource =>
      'Source: carteadeidentitate.gov.ro — General Directorate for Personal Records / Ministry of Internal Affairs';

  @override
  String get openOfficialPage => 'Open official page';

  @override
  String get pinScreenTitle => 'Signing PIN';

  @override
  String get enterSigningPin => 'Enter your 6-digit signing PIN';

  @override
  String get signingPinHint =>
      'This is the PIN for signing chosen when you activated the CEI — not the CAN printed on the card, and not the 4-digit authentication PIN.';

  @override
  String get onboardingTitle => 'Sign with your Romanian eID';

  @override
  String get onboardingBody =>
      'SignBridge signs documents from websites using NFC and your CEI. Nothing is signed until you confirm with your signing PIN.';

  @override
  String get onboardingStepCanTitle => 'Save the CAN once';

  @override
  String get onboardingStepCanBody =>
      'The 6-digit CAN is printed on the front of the card. It opens a secure NFC session and is separate from the signing PIN.';

  @override
  String get onboardingStepLinkTitle => 'Open from a website';

  @override
  String get onboardingStepLinkBody =>
      'When a site asks you to sign, SignBridge opens via deep link. If you never opened the app before, you can set the CAN then.';

  @override
  String get onboardingStepHoldTitle => 'Hold the card still';

  @override
  String get onboardingStepHoldBody =>
      'Keep the CEI against the phone until the signature finishes.';

  @override
  String get setCanNow => 'Set CAN now';

  @override
  String get setCanLater => 'I’ll set it when I sign';

  @override
  String get signingTitle => 'Signing';

  @override
  String documentsCount(int count) {
    return '$count document(s)';
  }

  @override
  String get holdCardHint =>
      'Hold your eID card to the back of the phone\nand keep it still until signing completes.';

  @override
  String get statusPreparing => 'Preparing…';

  @override
  String get statusCheckingCan => 'Checking CAN…';

  @override
  String get statusEnterCan => 'Enter CAN';

  @override
  String get statusEnterPin => 'Enter your signing PIN';

  @override
  String get statusTapCard => 'Hold your eID card…';

  @override
  String get statusAuthenticating => 'Authenticating…';

  @override
  String get statusReadingCertificate => 'Reading certificate…';

  @override
  String get statusPreparingDocument => 'Preparing document…';

  @override
  String get statusVerifyingPin => 'Verifying PIN…';

  @override
  String get statusSigningDocument => 'Signing document…';

  @override
  String statusSigningDocumentN(int index) {
    return 'Signing document $index…';
  }

  @override
  String get statusUploading => 'Uploading…';

  @override
  String get statusWritingSignedPdf => 'Writing signed PDF…';

  @override
  String get statusDone => 'Done';

  @override
  String get successTitle => 'Success';

  @override
  String get errorTitle => 'Error';

  @override
  String get done => 'Done';

  @override
  String get signedSuccessfullyTitle => 'Signed successfully';

  @override
  String get signedSuccessfullyMessage =>
      'All documents have been signed and uploaded.';

  @override
  String get sampleSignedTitle => 'Sample PDF signed';

  @override
  String get sampleSignedMessage =>
      'A sample document was signed with your eID and saved in the app’s private storage on this phone.';

  @override
  String get signingFailedTitle => 'Signing failed';

  @override
  String get requestErrorTitle => 'Request error';

  @override
  String get errorCancelled => 'Cancelled.';

  @override
  String get errorWrongPin =>
      'Wrong signing PIN. Do not keep guessing — the PIN will lock.';

  @override
  String errorWrongPinRetries(int retries) {
    return 'Wrong signing PIN. $retries attempt(s) remaining. Do not keep guessing — the PIN will lock.';
  }

  @override
  String get errorPinBlocked =>
      'Your signing PIN is blocked after too many wrong attempts. Reactivate the signing function at a public community service for personal records, then try again.';

  @override
  String get errorWrongCan =>
      'Could not open a secure session with the card. Check the 6-digit CAN on the front of your eID and try again. A wrong CAN does not lock your signing PIN.';

  @override
  String get errorNfcLost =>
      'The NFC connection was lost. Hold the card still against the back of the phone until signing finishes.';

  @override
  String get errorNfcUnavailable =>
      'NFC is unavailable. Enable NFC in system settings and try again.';

  @override
  String get errorCertRead =>
      'Could not read the signing certificate from the card. Make sure this is a Romanian electronic identity card (CEI) with an active signing certificate.';

  @override
  String get errorCertMismatch =>
      'This card’s signing certificate does not match the one requested by the website. Use the correct eID card.';

  @override
  String get errorDownload =>
      'Could not download the document. Check your internet connection and try again.';

  @override
  String get errorUpload =>
      'The signature was created, but uploading the signed document failed. Check your internet connection and try again from the website.';

  @override
  String get errorSignFailed =>
      'Signing failed on the card. Hold the card still and try again.';

  @override
  String get errorTimeout =>
      'The operation timed out. Hold the card still against the phone and try again.';

  @override
  String get errorCertNotFound =>
      'No matching signing certificate was found on this card.';

  @override
  String get errorUnsupportedType => 'This document type is not supported yet.';

  @override
  String get errorUnsupportedVersion =>
      'This signing request uses an unsupported protocol version.';

  @override
  String get errorGeneric =>
      'Something went wrong while signing. Please try again.';
}
