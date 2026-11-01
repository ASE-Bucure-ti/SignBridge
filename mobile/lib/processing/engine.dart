// SignBridge — Processing engine
// Orchestrates: download → parse PDF → NFC (PACE + sign) → upload → callbacks

import 'dart:convert';
import 'dart:typed_data';
import 'package:logger/logger.dart';

import '../protocol/models.dart';
import '../protocol/errors.dart';
import '../protocol/user_messages.dart';
import '../network/downloader.dart';
import '../network/uploader.dart';
import '../network/callback.dart';

import '../crypto/certificate.dart';
import '../crypto/cms_builder.dart';
import '../crypto/hash.dart';

import '../pdf/parser.dart';
import '../pdf/acroform.dart';
import '../pdf/signer.dart';
import '../pdf/incremental_writer.dart';
import '../pdf/appearance.dart';
import '../pdf/appearance_assets.dart';

import '../nfc/card_reader.dart';
import '../util/sb_log.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

/// Callback for UI state updates during processing.
typedef EngineProgressCallback =
    void Function(String objectId, String status, int percent);

/// Callback to request CAN from the user.
typedef CanRequester = Future<String?> Function();

/// Callback to request eSign PIN from the user.
typedef PinRequester = Future<String?> Function();

/// A single work item flattened from objects / objectGroups.
class _WorkItem {
  final String id;
  final DataType dataType;
  final ContentDefinition content;
  final PdfOptions? pdfOptions;
  final UploadConfig upload;
  final CallbacksConfig callbacks;
  final String certId;

  _WorkItem({
    required this.id,
    required this.dataType,
    required this.content,
    this.pdfOptions,
    required this.upload,
    required this.callbacks,
    required this.certId,
  });
}

class Engine {
  final Downloader _downloader;
  final Uploader _uploader;
  final CallbackPoster _callbackPoster;

  Engine({
    Downloader? downloader,
    Uploader? uploader,
    CallbackPoster? callbackPoster,
  }) : _downloader = downloader ?? Downloader(),
       _uploader = uploader ?? Uploader(),
       _callbackPoster = callbackPoster ?? CallbackPoster();

  /// Process a validated [SignRequest].
  ///
  /// [requestCan] — called to get the CAN from the user (stored persistently).
  /// [requestPin] — called to get the eSign PIN from the user.
  /// [onProgress] — UI progress updates.
  Future<void> process(
    SignRequest request, {
    required CanRequester requestCan,
    required PinRequester requestPin,
    EngineProgressCallback? onProgress,
  }) async {
    _log.i('Engine: processing request ${request.requestId}');

    // Flatten all objects into a linear work list
    final workItems = _flattenRequest(request);
    if (workItems.isEmpty) {
      throw const SigningError(ErrorCode.badRequest, 'No objects to sign');
    }

    // ── Phase A: Download all content (before NFC) ──
    final downloadedContent = <String, Uint8List>{};
    for (final item in workItems) {
      try {
        onProgress?.call(item.id, 'Downloading...', 5);
        downloadedContent[item.id] = await _downloadContent(item);
      } catch (e) {
        _log.e('Download failed for ${item.id}: $e');
        await _postError(item, request.requestId, e);
        rethrow;
      }
    }

    // Non-PDF digests can be computed before the card session.
    final preparedPdfs = <String, PreparedPdf>{};
    final preparedData = <String, Uint8List>{};
    for (final item in workItems) {
      if (item.dataType != DataType.pdf) {
        preparedData[item.id] = sha384(downloadedContent[item.id]!);
      }
    }

    onProgress?.call(workItems.first.id, 'Enter CAN', 20);
    final can = await requestCan();
    if (can == null) {
      throw const SigningError(ErrorCode.cancelledByUser, 'Cancelled.');
    }

    onProgress?.call(workItems.first.id, 'Enter your eSign PIN', 25);
    final pin = await requestPin();
    if (pin == null) {
      throw const SigningError(ErrorCode.cancelledByUser, 'Cancelled.');
    }

    onProgress?.call(workItems.first.id, 'Tap your eID card...', 30);

    final cardReader = CardReader();
    late CertificateInfo certInfo;
    final signatures = <String, Uint8List>{};
    AppearanceLogo? logo;
    try {
      logo = await loadAppearanceLogo();
    } catch (e) {
      _log.w('Signature logo not loaded: $e');
    }

    try {
      await cardReader.connect(
        iosAlertMessage: 'Hold your eID card to the phone',
      );

      // CardAccess, applet select, then one PACE with the CAN.
      // The eSign PIN is not sent in this step.
      onProgress?.call(workItems.first.id, 'Authenticating...', 35);
      try {
        await cardReader.openSigningSession(can);
      } catch (e) {
        throw asSigningError(e, objectId: workItems.first.id);
      }

      // Certificate first. Failure here does not consume a PIN try.
      onProgress?.call(workItems.first.id, 'Reading certificate...', 45);
      final cardCert = await cardReader.readSigningCertificate();
      certInfo = parseCertificate(cardCert.derBytes);
      final cn = certInfo.subjectCn ?? request.cert.certId;
      sbLog('certificate CN=$cn');

      if (!certIdMatches(certInfo, request.cert.certId)) {
        throw SigningError(
          ErrorCode.badRequest,
          'Card certificate CN="$cn" does not match cert.certId='
          '"${request.cert.certId}"',
        );
      }

      // Appearance needs the real CN, so PDF prep happens after cert read.
      onProgress?.call(workItems.first.id, 'Preparing document...', 50);
      final signingTime = DateTime.now();
      for (final item in workItems) {
        if (item.dataType != DataType.pdf) continue;
        try {
          final pdf = parsePdf(downloadedContent[item.id]!);
          final sigField = findOrPlanSigField(pdf, item.pdfOptions?.label);
          if (sigField.isNew) {
            _log.w(
              'No existing AcroForm field for label='
              '"${item.pdfOptions?.label}"; creating "${sigField.fieldName}"',
            );
          } else {
            _log.i(
              'Reusing AcroForm field "${sigField.fieldName}" '
              'widget=${sigField.existingWidgetObjNum}',
            );
          }
          final update = buildIncremental(
            pdf: pdf,
            sigField: sigField,
            signerName: cn,
            signingTime: signingTime.toUtc(),
            appearanceTimeLabel: formatAppearanceDateTime(signingTime),
            logo: logo,
          );
          preparedPdfs[item.id] = prepareForSigning(
            update.bytes,
            useSha384: true,
          );
        } catch (e) {
          _log.e('Prepare failed for ${item.id}: $e');
          await _postError(item, request.requestId, e);
          rethrow;
        }
      }

      onProgress?.call(workItems.first.id, 'Verifying PIN...', 55);
      final pinResult = await cardReader.verifyEsignPin(pin);
      if (pinResult >= 0) {
        throw SigningError(
          ErrorCode.badRequest,
          'Wrong PIN ($pinResult retries remaining).',
        );
      }

      await cardReader.mseSetSigning();

      for (var i = 0; i < workItems.length; i++) {
        final item = workItems[i];
        final pct = 60 + ((i / workItems.length) * 20).round();
        onProgress?.call(item.id, 'Signing document ${i + 1}...', pct);

        final contentDigest = preparedPdfs.containsKey(item.id)
            ? preparedPdfs[item.id]!.digest
            : preparedData[item.id]!;

        final signedAttrs = buildSignedAttributes(
          contentDigest: contentDigest,
          cert: certInfo,
          signingTime: DateTime.now().toUtc(),
          digestAlgorithm: CmsDigestAlgorithm.sha384,
        );
        final attrHash = hashSignedAttributes(
          signedAttrs,
          CmsDigestAlgorithm.sha384,
        );
        final cardSig = await cardReader.signHash(attrHash);
        signatures[item.id] = buildCms(
          signedAttributesDer: signedAttrs,
          signature: cardSig.signatureBytes,
          cert: certInfo,
          digestAlgorithm: CmsDigestAlgorithm.sha384,
          signatureAlgorithm: CmsSignatureAlgorithm.ecdsaSha384,
        );
      }
    } catch (e) {
      if (e is SigningError) rethrow;
      throw asSigningError(e, objectId: workItems.first.id);
    } finally {
      await cardReader.disconnect();
    }

    // ── Embed signatures and upload ──
    for (final item in workItems) {
      try {
        final pct =
            80 + ((workItems.indexOf(item) / workItems.length) * 15).round();
        onProgress?.call(item.id, 'Uploading...', pct);

        await _callbackPoster.postProgress(
          item.callbacks,
          ProgressCallbackPayload(
            objectId: item.id,
            requestId: request.requestId,
            status: 'uploading',
            percentComplete: pct,
          ),
        );

        final signedContent = preparedPdfs.containsKey(item.id)
            ? embedSignature(preparedPdfs[item.id]!, signatures[item.id]!)
            : signatures[item.id]!;

        final (statusCode, responseBody) = await _uploader.upload(
          config: item.upload,
          data: signedContent,
        );

        onProgress?.call(item.id, 'Done', 100);
        await _callbackPoster.postSuccess(
          item.callbacks,
          SuccessCallbackPayload(
            objectId: item.id,
            requestId: request.requestId,
            statusCode: statusCode,
            responseBody: responseBody,
            timestamp: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      } catch (e) {
        _log.e('Upload/callback failed for ${item.id}: $e');
        await _postError(item, request.requestId, e);
        rethrow;
      }
    }

    _log.i('Engine: all ${workItems.length} object(s) processed');
  }

  /// Sign a local PDF on the card and return the signed bytes.
  ///
  /// Defaults to the bundled AcroForm PoC (`label` = Signature1).
  /// Nothing is downloaded or uploaded.
  Future<Uint8List> signLocalPdf({
    required Uint8List pdfBytes,
    required CanRequester requestCan,
    required PinRequester requestPin,
    EngineProgressCallback? onProgress,
    String fieldLabel = 'Signature1',
  }) async {
    const id = 'poc-pdf';
    _log.i('PoC: local PDF ${pdfBytes.length} bytes, label=$fieldLabel');
    sbLog('PoC local PDF ${pdfBytes.length} bytes label=$fieldLabel');

    onProgress?.call(id, 'Enter CAN', 20);
    final can = await requestCan();
    if (can == null) {
      throw const SigningError(ErrorCode.cancelledByUser, 'Cancelled.');
    }

    onProgress?.call(id, 'Enter your eSign PIN', 25);
    final pin = await requestPin();
    if (pin == null) {
      throw const SigningError(ErrorCode.cancelledByUser, 'Cancelled.');
    }

    onProgress?.call(id, 'Tap your eID card...', 30);
    final cardReader = CardReader();
    AppearanceLogo? logo;
    try {
      logo = await loadAppearanceLogo();
    } catch (e) {
      _log.w('Signature logo not loaded: $e');
    }

    late final PreparedPdf prepared;
    late final Uint8List cms;
    try {
      await cardReader.connect(
        iosAlertMessage: 'Hold your eID card to the phone',
      );
      onProgress?.call(id, 'Authenticating...', 35);
      try {
        await cardReader.openSigningSession(can);
      } catch (e) {
        throw asSigningError(e, objectId: id);
      }

      onProgress?.call(id, 'Reading certificate...', 45);
      final cardCert = await cardReader.readSigningCertificate();
      final certInfo = parseCertificate(cardCert.derBytes);
      final cn = certInfo.subjectCn ?? 'Unknown';
      sbLog('certificate CN=$cn');

      onProgress?.call(id, 'Preparing document...', 50);
      final signingTime = DateTime.now();
      final pdf = parsePdf(pdfBytes);
      final sigField = findOrPlanSigField(pdf, fieldLabel);
      sbLog(
        'AcroForm field="${sigField.fieldName}" '
        'existing=${!sigField.isNew} widget=${sigField.existingWidgetObjNum}',
      );
      final update = buildIncremental(
        pdf: pdf,
        sigField: sigField,
        signerName: cn,
        signingTime: signingTime.toUtc(),
        appearanceTimeLabel: formatAppearanceDateTime(signingTime),
        reason: 'SignBridge sample signature',
        logo: logo,
      );
      prepared = prepareForSigning(update.bytes, useSha384: true);

      onProgress?.call(id, 'Verifying PIN...', 55);
      final pinResult = await cardReader.verifyEsignPin(pin);
      if (pinResult >= 0) {
        throw SigningError(
          ErrorCode.badRequest,
          'Wrong PIN ($pinResult retries remaining).',
        );
      }

      await cardReader.mseSetSigning();
      onProgress?.call(id, 'Signing document...', 70);
      final signedAttrs = buildSignedAttributes(
        contentDigest: prepared.digest,
        cert: certInfo,
        signingTime: DateTime.now().toUtc(),
        digestAlgorithm: CmsDigestAlgorithm.sha384,
      );
      final attrHash = hashSignedAttributes(
        signedAttrs,
        CmsDigestAlgorithm.sha384,
      );
      final cardSig = await cardReader.signHash(attrHash);
      cms = buildCms(
        signedAttributesDer: signedAttrs,
        signature: cardSig.signatureBytes,
        cert: certInfo,
        digestAlgorithm: CmsDigestAlgorithm.sha384,
        signatureAlgorithm: CmsSignatureAlgorithm.ecdsaSha384,
      );
    } catch (e) {
      if (e is SigningError) rethrow;
      throw asSigningError(e, objectId: id);
    } finally {
      await cardReader.disconnect();
    }

    onProgress?.call(id, 'Writing signed PDF...', 90);
    final signed = embedSignature(prepared, cms);
    sbLog('signed PDF ${signed.length} bytes, CMS ${cms.length} bytes');
    return signed;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Flatten objects + objectGroups into a linear work list.
  List<_WorkItem> _flattenRequest(SignRequest request) {
    final items = <_WorkItem>[];

    // Standalone objects
    for (final obj in request.objects ?? <SignObject>[]) {
      items.add(
        _WorkItem(
          id: obj.id,
          dataType: obj.dataType,
          content: obj.content,
          pdfOptions: obj.pdfOptions,
          upload: obj.upload,
          callbacks: obj.callbacks,
          certId: request.cert.certId,
        ),
      );
    }

    // Object groups
    for (final group in request.objectGroups ?? <ObjectGroup>[]) {
      for (final gObj in group.objects) {
        // Build a ContentDefinition from group-level settings
        ContentDefinition content;
        if (group.mode == 'remote') {
          final template = group.downloadUrl ?? '';
          content = ContentDefinition.fromJson({
            'mode': 'remote',
            'downloadUrl': template.replaceAll('<objectId>', gObj.id),
            'headers': group.downloadHeaders,
          });
        } else {
          content = ContentDefinition.fromJson({
            'mode': 'inline',
            'encoding': gObj.inlineEncoding ?? 'utf8',
            'content': gObj.inlineValue ?? '',
          });
        }

        final upload = UploadConfig(
          uploadUrl: group.upload.uploadUrl.replaceAll('<objectId>', gObj.id),
          httpMethod: group.upload.httpMethod,
          headers: group.upload.headers,
          signedContentType: group.upload.signedContentType,
        );

        items.add(
          _WorkItem(
            id: gObj.id,
            dataType: group.dataType,
            content: content,
            pdfOptions: group.pdfOptions,
            upload: upload,
            callbacks: group.callbacks,
            certId: request.cert.certId,
          ),
        );
      }
    }

    return items;
  }

  /// Download or extract inline content.
  Future<Uint8List> _downloadContent(_WorkItem item) async {
    if (item.content.isInline) {
      final inline = item.content.inline!;
      return Uint8List.fromList(utf8.encode(inline.content));
    }

    final remote = item.content.remote!;
    return _downloader.download(
      url: remote.downloadUrl,
      httpMethod: remote.httpMethod ?? 'GET',
      headers: remote.headers,
    );
  }

  /// Post an error callback (fire-and-forget).
  Future<void> _postError(
    _WorkItem item,
    String requestId,
    Object error,
  ) async {
    final errorPayload = ErrorCallbackPayload(
      objectId: item.id,
      requestId: requestId,
      errorCode: error is SigningError ? error.code : ErrorCode.internalError,
      errorMessage: error.toString(),
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );
    await _callbackPoster.postError(item.callbacks, errorPayload);
  }
}
