// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'SignBridge';

  @override
  String get appSubtitle => 'SignBridge Mobile';

  @override
  String get waitingForRequest => 'Se așteaptă o cerere de semnare…';

  @override
  String get homeDeepLinkHint =>
      'Deschideți un document din browser pentru a începe semnarea.\nAplicația primește cererea prin deep link.';

  @override
  String get canSaved => 'CAN salvat pe acest telefon';

  @override
  String get canNotSet => 'CAN nesetat — apăsați pentru a-l adăuga';

  @override
  String get changeCan => 'Schimbați CAN-ul';

  @override
  String get setCan => 'Setați CAN-ul';

  @override
  String get saveCan => 'Salvați CAN-ul';

  @override
  String get replaceCan => 'Înlocuiți CAN-ul';

  @override
  String get canScreenTitle => 'Numărul CAN';

  @override
  String get canFirstTimeHint =>
      'Înainte de prima semnare, salvați CAN-ul de pe cartea electronică de identitate (CEI). Este suficient o singură dată pe acest telefon.';

  @override
  String get canAlreadySaved =>
      'Un CAN este deja salvat pe acest telefon. Îl puteți edita mai jos. Se înlocuiește doar după confirmare.';

  @override
  String get replaceCanConfirmTitle => 'Înlocuiți CAN-ul?';

  @override
  String get replaceCanConfirmBody =>
      'Sunteți sigur/ă că doriți să înlocuiți CAN-ul salvat pe acest telefon?';

  @override
  String get confirm => 'Confirmați';

  @override
  String get cancel => 'Anulați';

  @override
  String get enterSixDigitCan => 'Introduceți CAN-ul din 6 cifre';

  @override
  String get canLocationHint =>
      'CAN-ul este tipărit pe fața CEI, în dreapta-jos, sub data de expirare a actului de identitate.';

  @override
  String get whereToFindOnCei => 'Unde îl găsiți pe CEI';

  @override
  String get ceiFrontTitle => 'Vedere din față';

  @override
  String get ceiBackTitle => 'Vedere din spate';

  @override
  String get ceiFront1 => 'Drapelele Uniunii Europene și României';

  @override
  String get ceiFront2 => 'Stema României';

  @override
  String get ceiFront3 => 'Datele personale ale titularului';

  @override
  String get ceiFront4 => 'Numărul actului de identitate';

  @override
  String get ceiFront5 => 'Data expirării actului de identitate';

  @override
  String get ceiFront6 => 'Numărul CAN';

  @override
  String get ceiFront7 => 'Semnătura olografă a titularului';

  @override
  String get ceiFront8 => 'Simbolul „document electronic”';

  @override
  String get ceiBack1 => 'Cip (mediu electronic de stocare)';

  @override
  String get ceiBack2 => 'Data emiterii și autoritatea emitentă';

  @override
  String get ceiBack3 => 'Fotografia titularului și textul „ROU”';

  @override
  String get ceiBack4 => 'MRZ (Machine Readable Zone), pentru citire optică';

  @override
  String get ceiSource =>
      'Sursă: carteadeidentitate.gov.ro — Direcția Generală pentru Evidența Persoanelor / Ministerul Afacerilor Interne';

  @override
  String get openOfficialPage => 'Deschideți pagina oficială';

  @override
  String get pinScreenTitle => 'PIN pentru semnare';

  @override
  String get enterSigningPin => 'Introduceți PIN-ul pentru semnare din 6 cifre';

  @override
  String get signingPinHint =>
      'Acesta este PIN-ul pentru semnare ales la activarea CEI — nu CAN-ul tipărit pe card și nu PIN-ul pentru autentificare din 4 cifre.';

  @override
  String get onboardingTitle => 'Semnați cu CEI-ul dumneavoastră';

  @override
  String get onboardingBody =>
      'SignBridge semnează documente din site-uri web folosind NFC și CEI-ul dumneavoastră. Nimic nu este semnat până confirmați cu PIN-ul pentru semnare.';

  @override
  String get onboardingStepCanTitle => 'Salvați CAN-ul o singură dată';

  @override
  String get onboardingStepCanBody =>
      'CAN-ul din 6 cifre este tipărit pe fața cardului. Deschide o sesiune NFC securizată și este separat de PIN-ul pentru semnare.';

  @override
  String get onboardingStepLinkTitle => 'Deschideți dintr-un site web';

  @override
  String get onboardingStepLinkBody =>
      'Când un site vă cere să semnați, SignBridge se deschide prin deep link. Dacă nu ați deschis aplicația înainte, puteți seta CAN-ul atunci.';

  @override
  String get onboardingStepHoldTitle => 'Țineți cardul nemișcat';

  @override
  String get onboardingStepHoldBody =>
      'Țineți CEI-ul pe telefon până se termină semnătura.';

  @override
  String get setCanNow => 'Setați CAN-ul acum';

  @override
  String get setCanLater => 'Îl setez când semnez';

  @override
  String get signingTitle => 'Semnare';

  @override
  String documentsCount(int count) {
    return '$count document(e)';
  }

  @override
  String get holdCardHint =>
      'Apropiați cartea de identitate de spatele telefonului\nși țineți-o nemișcată până se termină semnarea.';

  @override
  String get statusPreparing => 'Se pregătește…';

  @override
  String get statusCheckingCan => 'Se verifică CAN-ul…';

  @override
  String get statusEnterCan => 'Introduceți CAN-ul';

  @override
  String get statusEnterPin => 'Introduceți PIN-ul pentru semnare';

  @override
  String get statusTapCard => 'Apropiați CEI-ul…';

  @override
  String get statusAuthenticating => 'Autentificare…';

  @override
  String get statusReadingCertificate => 'Se citește certificatul…';

  @override
  String get statusPreparingDocument => 'Se pregătește documentul…';

  @override
  String get statusVerifyingPin => 'Se verifică PIN-ul…';

  @override
  String get statusSigningDocument => 'Se semnează documentul…';

  @override
  String statusSigningDocumentN(int index) {
    return 'Se semnează documentul $index…';
  }

  @override
  String get statusUploading => 'Se încarcă…';

  @override
  String get statusWritingSignedPdf => 'Se scrie PDF-ul semnat…';

  @override
  String get statusDone => 'Gata';

  @override
  String get successTitle => 'Succes';

  @override
  String get errorTitle => 'Eroare';

  @override
  String get done => 'Gata';

  @override
  String get signedSuccessfullyTitle => 'Semnat cu succes';

  @override
  String get signedSuccessfullyMessage =>
      'Toate documentele au fost semnate și încărcate.';

  @override
  String get sampleSignedTitle => 'PDF de probă semnat';

  @override
  String get sampleSignedMessage =>
      'Un document de probă a fost semnat cu CEI-ul dumneavoastră și salvat în spațiul privat al aplicației pe acest telefon.';

  @override
  String get signingFailedTitle => 'Semnarea a eșuat';

  @override
  String get requestErrorTitle => 'Eroare la cerere';

  @override
  String get errorCancelled => 'Anulat.';

  @override
  String get errorWrongPin =>
      'PIN pentru semnare greșit. Nu continuați să ghiciți — PIN-ul se va bloca.';

  @override
  String errorWrongPinRetries(int retries) {
    return 'PIN pentru semnare greșit. Mai aveți $retries încercare/încercări. Nu continuați să ghiciți — PIN-ul se va bloca.';
  }

  @override
  String get errorPinBlocked =>
      'PIN-ul pentru semnare este blocat după prea multe încercări greșite. Reactivați funcția de semnare la un serviciu public comunitar de evidență a persoanelor, apoi încercați din nou.';

  @override
  String get errorWrongCan =>
      'Nu s-a putut deschide o sesiune securizată cu cardul. Verificați CAN-ul din 6 cifre de pe fața CEI și încercați din nou. Un CAN greșit nu blochează PIN-ul pentru semnare.';

  @override
  String get errorNfcLost =>
      'Conexiunea NFC s-a întrerupt. Țineți cardul nemișcat pe spatele telefonului până se termină semnarea.';

  @override
  String get errorNfcUnavailable =>
      'NFC nu este disponibil. Activați NFC din setările sistemului și încercați din nou.';

  @override
  String get errorCertRead =>
      'Nu s-a putut citi certificatul de semnare de pe card. Asigurați-vă că este o carte electronică de identitate (CEI) cu certificat de semnare activ.';

  @override
  String get errorCertMismatch =>
      'Certificatul de semnare de pe acest card nu corespunde celui cerut de site. Folosiți CEI-ul corect.';

  @override
  String get errorDownload =>
      'Documentul nu a putut fi descărcat. Verificați conexiunea la internet și încercați din nou.';

  @override
  String get errorUpload =>
      'Semnătura a fost creată, dar încărcarea documentului semnat a eșuat. Verificați conexiunea la internet și încercați din nou de pe site.';

  @override
  String get errorSignFailed =>
      'Semnarea pe card a eșuat. Țineți cardul nemișcat și încercați din nou.';

  @override
  String get errorTimeout =>
      'Operațiunea a expirat. Țineți cardul nemișcat pe telefon și încercați din nou.';

  @override
  String get errorCertNotFound =>
      'Nu a fost găsit pe card un certificat de semnare potrivit.';

  @override
  String get errorUnsupportedType =>
      'Acest tip de document nu este încă suportat.';

  @override
  String get errorUnsupportedVersion =>
      'Această cerere de semnare folosește o versiune de protocol nesuportată.';

  @override
  String get errorGeneric =>
      'A apărut o eroare la semnare. Vă rugăm să încercați din nou.';
}
