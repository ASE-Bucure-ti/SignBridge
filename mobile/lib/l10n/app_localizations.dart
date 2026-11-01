import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ro.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ro'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SignBridge'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SignBridge Mobile'**
  String get appSubtitle;

  /// No description provided for @waitingForRequest.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a signing request…'**
  String get waitingForRequest;

  /// No description provided for @homeDeepLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Open a document from your browser to start signing.\nThe app receives the request via deep link.'**
  String get homeDeepLinkHint;

  /// No description provided for @canSaved.
  ///
  /// In en, this message translates to:
  /// **'CAN saved on this phone'**
  String get canSaved;

  /// No description provided for @canNotSet.
  ///
  /// In en, this message translates to:
  /// **'CAN not set — tap to add'**
  String get canNotSet;

  /// No description provided for @changeCan.
  ///
  /// In en, this message translates to:
  /// **'Change CAN'**
  String get changeCan;

  /// No description provided for @setCan.
  ///
  /// In en, this message translates to:
  /// **'Set CAN'**
  String get setCan;

  /// No description provided for @saveCan.
  ///
  /// In en, this message translates to:
  /// **'Save CAN'**
  String get saveCan;

  /// No description provided for @replaceCan.
  ///
  /// In en, this message translates to:
  /// **'Replace CAN'**
  String get replaceCan;

  /// No description provided for @canScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Card Access Number (CAN)'**
  String get canScreenTitle;

  /// No description provided for @canFirstTimeHint.
  ///
  /// In en, this message translates to:
  /// **'Before the first signature, save the CAN from your Romanian electronic identity card (CEI). You only need to do this once on this phone.'**
  String get canFirstTimeHint;

  /// No description provided for @canAlreadySaved.
  ///
  /// In en, this message translates to:
  /// **'A CAN is already saved on this phone. You can edit it below. It is only replaced after you confirm.'**
  String get canAlreadySaved;

  /// No description provided for @replaceCanConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace CAN?'**
  String get replaceCanConfirmTitle;

  /// No description provided for @replaceCanConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to replace the saved CAN on this phone?'**
  String get replaceCanConfirmBody;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @enterSixDigitCan.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit CAN'**
  String get enterSixDigitCan;

  /// No description provided for @canLocationHint.
  ///
  /// In en, this message translates to:
  /// **'The CAN is printed on the front of the card, bottom-right, under the expiry date.'**
  String get canLocationHint;

  /// No description provided for @whereToFindOnCei.
  ///
  /// In en, this message translates to:
  /// **'Where to find it on the CEI'**
  String get whereToFindOnCei;

  /// No description provided for @ceiFrontTitle.
  ///
  /// In en, this message translates to:
  /// **'Front view'**
  String get ceiFrontTitle;

  /// No description provided for @ceiBackTitle.
  ///
  /// In en, this message translates to:
  /// **'Back view'**
  String get ceiBackTitle;

  /// No description provided for @ceiFront1.
  ///
  /// In en, this message translates to:
  /// **'Flags of the European Union and Romania'**
  String get ceiFront1;

  /// No description provided for @ceiFront2.
  ///
  /// In en, this message translates to:
  /// **'Coat of arms of Romania'**
  String get ceiFront2;

  /// No description provided for @ceiFront3.
  ///
  /// In en, this message translates to:
  /// **'Holder’s personal data'**
  String get ceiFront3;

  /// No description provided for @ceiFront4.
  ///
  /// In en, this message translates to:
  /// **'Identity document number'**
  String get ceiFront4;

  /// No description provided for @ceiFront5.
  ///
  /// In en, this message translates to:
  /// **'Identity document expiry date'**
  String get ceiFront5;

  /// No description provided for @ceiFront6.
  ///
  /// In en, this message translates to:
  /// **'CAN number'**
  String get ceiFront6;

  /// No description provided for @ceiFront7.
  ///
  /// In en, this message translates to:
  /// **'Holder’s handwritten signature'**
  String get ceiFront7;

  /// No description provided for @ceiFront8.
  ///
  /// In en, this message translates to:
  /// **'“Electronic document” symbol'**
  String get ceiFront8;

  /// No description provided for @ceiBack1.
  ///
  /// In en, this message translates to:
  /// **'Chip (electronic storage medium)'**
  String get ceiBack1;

  /// No description provided for @ceiBack2.
  ///
  /// In en, this message translates to:
  /// **'Issue date and issuing authority'**
  String get ceiBack2;

  /// No description provided for @ceiBack3.
  ///
  /// In en, this message translates to:
  /// **'Holder’s photograph and the text “ROU”'**
  String get ceiBack3;

  /// No description provided for @ceiBack4.
  ///
  /// In en, this message translates to:
  /// **'MRZ (Machine Readable Zone), for optical reading'**
  String get ceiBack4;

  /// No description provided for @ceiSource.
  ///
  /// In en, this message translates to:
  /// **'Source: carteadeidentitate.gov.ro — General Directorate for Personal Records / Ministry of Internal Affairs'**
  String get ceiSource;

  /// No description provided for @openOfficialPage.
  ///
  /// In en, this message translates to:
  /// **'Open official page'**
  String get openOfficialPage;

  /// No description provided for @pinScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Signing PIN'**
  String get pinScreenTitle;

  /// No description provided for @enterSigningPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your 6-digit signing PIN'**
  String get enterSigningPin;

  /// No description provided for @signingPinHint.
  ///
  /// In en, this message translates to:
  /// **'This is the PIN for signing chosen when you activated the CEI — not the CAN printed on the card, and not the 4-digit authentication PIN.'**
  String get signingPinHint;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign with your Romanian eID'**
  String get onboardingTitle;

  /// No description provided for @onboardingBody.
  ///
  /// In en, this message translates to:
  /// **'SignBridge signs documents from websites using NFC and your CEI. Nothing is signed until you confirm with your signing PIN.'**
  String get onboardingBody;

  /// No description provided for @onboardingStepCanTitle.
  ///
  /// In en, this message translates to:
  /// **'Save the CAN once'**
  String get onboardingStepCanTitle;

  /// No description provided for @onboardingStepCanBody.
  ///
  /// In en, this message translates to:
  /// **'The 6-digit CAN is printed on the front of the card. It opens a secure NFC session and is separate from the signing PIN.'**
  String get onboardingStepCanBody;

  /// No description provided for @onboardingStepLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Open from a website'**
  String get onboardingStepLinkTitle;

  /// No description provided for @onboardingStepLinkBody.
  ///
  /// In en, this message translates to:
  /// **'When a site asks you to sign, SignBridge opens via deep link. If you never opened the app before, you can set the CAN then.'**
  String get onboardingStepLinkBody;

  /// No description provided for @onboardingStepHoldTitle.
  ///
  /// In en, this message translates to:
  /// **'Hold the card still'**
  String get onboardingStepHoldTitle;

  /// No description provided for @onboardingStepHoldBody.
  ///
  /// In en, this message translates to:
  /// **'Keep the CEI against the phone until the signature finishes.'**
  String get onboardingStepHoldBody;

  /// No description provided for @setCanNow.
  ///
  /// In en, this message translates to:
  /// **'Set CAN now'**
  String get setCanNow;

  /// No description provided for @setCanLater.
  ///
  /// In en, this message translates to:
  /// **'I’ll set it when I sign'**
  String get setCanLater;

  /// No description provided for @signingTitle.
  ///
  /// In en, this message translates to:
  /// **'Signing'**
  String get signingTitle;

  /// No description provided for @documentsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} document(s)'**
  String documentsCount(int count);

  /// No description provided for @holdCardHint.
  ///
  /// In en, this message translates to:
  /// **'Hold your eID card to the back of the phone\nand keep it still until signing completes.'**
  String get holdCardHint;

  /// No description provided for @statusPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get statusPreparing;

  /// No description provided for @statusCheckingCan.
  ///
  /// In en, this message translates to:
  /// **'Checking CAN…'**
  String get statusCheckingCan;

  /// No description provided for @statusEnterCan.
  ///
  /// In en, this message translates to:
  /// **'Enter CAN'**
  String get statusEnterCan;

  /// No description provided for @statusEnterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter your signing PIN'**
  String get statusEnterPin;

  /// No description provided for @statusTapCard.
  ///
  /// In en, this message translates to:
  /// **'Hold your eID card…'**
  String get statusTapCard;

  /// No description provided for @statusAuthenticating.
  ///
  /// In en, this message translates to:
  /// **'Authenticating…'**
  String get statusAuthenticating;

  /// No description provided for @statusReadingCertificate.
  ///
  /// In en, this message translates to:
  /// **'Reading certificate…'**
  String get statusReadingCertificate;

  /// No description provided for @statusPreparingDocument.
  ///
  /// In en, this message translates to:
  /// **'Preparing document…'**
  String get statusPreparingDocument;

  /// No description provided for @statusVerifyingPin.
  ///
  /// In en, this message translates to:
  /// **'Verifying PIN…'**
  String get statusVerifyingPin;

  /// No description provided for @statusSigningDocument.
  ///
  /// In en, this message translates to:
  /// **'Signing document…'**
  String get statusSigningDocument;

  /// No description provided for @statusSigningDocumentN.
  ///
  /// In en, this message translates to:
  /// **'Signing document {index}…'**
  String statusSigningDocumentN(int index);

  /// No description provided for @statusUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get statusUploading;

  /// No description provided for @statusWritingSignedPdf.
  ///
  /// In en, this message translates to:
  /// **'Writing signed PDF…'**
  String get statusWritingSignedPdf;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get statusDone;

  /// No description provided for @successTitle.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get successTitle;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorTitle;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @signedSuccessfullyTitle.
  ///
  /// In en, this message translates to:
  /// **'Signed successfully'**
  String get signedSuccessfullyTitle;

  /// No description provided for @signedSuccessfullyMessage.
  ///
  /// In en, this message translates to:
  /// **'All documents have been signed and uploaded.'**
  String get signedSuccessfullyMessage;

  /// No description provided for @sampleSignedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample PDF signed'**
  String get sampleSignedTitle;

  /// No description provided for @sampleSignedMessage.
  ///
  /// In en, this message translates to:
  /// **'A sample document was signed with your eID and saved in the app’s private storage on this phone.'**
  String get sampleSignedMessage;

  /// No description provided for @signingFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Signing failed'**
  String get signingFailedTitle;

  /// No description provided for @requestErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Request error'**
  String get requestErrorTitle;

  /// No description provided for @errorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled.'**
  String get errorCancelled;

  /// No description provided for @errorWrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong signing PIN. Do not keep guessing — the PIN will lock.'**
  String get errorWrongPin;

  /// No description provided for @errorWrongPinRetries.
  ///
  /// In en, this message translates to:
  /// **'Wrong signing PIN. {retries} attempt(s) remaining. Do not keep guessing — the PIN will lock.'**
  String errorWrongPinRetries(int retries);

  /// No description provided for @errorPinBlocked.
  ///
  /// In en, this message translates to:
  /// **'Your signing PIN is blocked after too many wrong attempts. Reactivate the signing function at a public community service for personal records, then try again.'**
  String get errorPinBlocked;

  /// No description provided for @errorWrongCan.
  ///
  /// In en, this message translates to:
  /// **'Could not open a secure session with the card. Check the 6-digit CAN on the front of your eID and try again. A wrong CAN does not lock your signing PIN.'**
  String get errorWrongCan;

  /// No description provided for @errorNfcLost.
  ///
  /// In en, this message translates to:
  /// **'The NFC connection was lost. Hold the card still against the back of the phone until signing finishes.'**
  String get errorNfcLost;

  /// No description provided for @errorNfcUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NFC is unavailable. Enable NFC in system settings and try again.'**
  String get errorNfcUnavailable;

  /// No description provided for @errorCertRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read the signing certificate from the card. Make sure this is a Romanian electronic identity card (CEI) with an active signing certificate.'**
  String get errorCertRead;

  /// No description provided for @errorCertMismatch.
  ///
  /// In en, this message translates to:
  /// **'This card’s signing certificate does not match the one requested by the website. Use the correct eID card.'**
  String get errorCertMismatch;

  /// No description provided for @errorDownload.
  ///
  /// In en, this message translates to:
  /// **'Could not download the document. Check your internet connection and try again.'**
  String get errorDownload;

  /// No description provided for @errorUpload.
  ///
  /// In en, this message translates to:
  /// **'The signature was created, but uploading the signed document failed. Check your internet connection and try again from the website.'**
  String get errorUpload;

  /// No description provided for @errorSignFailed.
  ///
  /// In en, this message translates to:
  /// **'Signing failed on the card. Hold the card still and try again.'**
  String get errorSignFailed;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The operation timed out. Hold the card still against the phone and try again.'**
  String get errorTimeout;

  /// No description provided for @errorCertNotFound.
  ///
  /// In en, this message translates to:
  /// **'No matching signing certificate was found on this card.'**
  String get errorCertNotFound;

  /// No description provided for @errorUnsupportedType.
  ///
  /// In en, this message translates to:
  /// **'This document type is not supported yet.'**
  String get errorUnsupportedType;

  /// No description provided for @errorUnsupportedVersion.
  ///
  /// In en, this message translates to:
  /// **'This signing request uses an unsupported protocol version.'**
  String get errorUnsupportedVersion;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while signing. Please try again.'**
  String get errorGeneric;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ro'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ro':
      return AppLocalizationsRo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
