// SignBridge — Processing engine
// Orchestrates: download → parse PDF → NFC (PACE + sign) → upload → callbacks

import 'dart:convert';
import 'dart:typed_data';
import 'package:logger/logger.dart';

import '../protocol/models.dart';
import '../protocol/errors.dart';
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

import '../nfc/card_reader.dart';
import '../nfc/nfc_manager.dart';

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
  /// [requestCan] — called to get the CAN from the user (shown once, cached).
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

    // ── Phase A: Download all content (before NFC, to minimize card time) ──
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

    // ── Phase B: Pre-parse PDFs and compute digests (before NFC) ──
    final preparedPdfs = <String, PreparedPdf>{};
    final preparedData = <String, Uint8List>{};
    for (final item in workItems) {
      try {
        onProgress?.call(item.id, 'Preparing document...', 15);
        final raw = downloadedContent[item.id]!;

        if (item.dataType == DataType.pdf) {
          final pdf = parsePdf(raw);
          final sigField = findOrPlanSigField(pdf, item.pdfOptions?.label);
          final now = DateTime.now().toUtc();

          // Build incremental update with sig dict placeholders
          final update = buildIncremental(
            pdf: pdf,
            sigField: sigField,
            signerName: item.certId, // placeholder; replaced with cert CN later
            signingTime: now,
          );

          // Compute byte-range digest (this is what the card will sign)
          final prepared = prepareForSigning(update.bytes, useSha384: true);
          preparedPdfs[item.id] = prepared;
        } else {
          // Non-PDF: hash the raw content directly
          preparedData[item.id] = sha384(raw);
        }
      } catch (e) {
        _log.e('Prepare failed for ${item.id}: $e');
        await _postError(item, request.requestId, e);
        rethrow;
      }
    }

    // ── Phase C: NFC interaction (PACE + read cert + sign all hashes) ──
    onProgress?.call(workItems.first.id, 'Tap your eID card...', 25);

    final can = await requestCan();
    if (can == null) {
      throw const SigningError(
        ErrorCode.cancelledByUser,
        'CAN entry cancelled',
      );
    }

    final pin = await requestPin();
    if (pin == null) {
      throw const SigningError(
        ErrorCode.cancelledByUser,
        'PIN entry cancelled',
      );
    }

    // Start NFC session and perform card operations
    final nfc = NfcManager();
    late CertificateInfo certInfo;
    final signatures = <String, Uint8List>{};

    try {
      await nfc.startSession(alertMessage: 'Hold your eID card to the phone');

      final cardReader = CardReader(nfc);

      // 1. Read PACE info from card
      onProgress?.call(workItems.first.id, 'Reading card...', 30);
      final paceInfo = await cardReader.readPaceInfo();

      // 2. PACE authentication with CAN
      onProgress?.call(workItems.first.id, 'Authenticating...', 40);
      await cardReader.authenticate(can, paceInfo);

      // 3. Select PKI applet
      await cardReader.selectPkiApplet();

      // 4. Verify eSign PIN
      onProgress?.call(workItems.first.id, 'Verifying PIN...', 50);
      final pinResult = await cardReader.verifyEsignPin(pin);
      if (pinResult >= 0) {
        throw SigningError(
          ErrorCode.signFailed,
          'Wrong PIN ($pinResult retries remaining)',
        );
      }

      // 5. Read signing certificate
      onProgress?.call(workItems.first.id, 'Reading certificate...', 55);
      final cardCert = await cardReader.readSigningCertificate();
      certInfo = parseCertificate(cardCert.derBytes);

      // 6. Configure signing algorithm
      await cardReader.mseSetSigning();

      // 7. Sign each document's hash
      for (var i = 0; i < workItems.length; i++) {
        final item = workItems[i];
        final pct = 60 + ((i / workItems.length) * 20).round();
        onProgress?.call(item.id, 'Signing document ${i + 1}...', pct);

        Uint8List contentDigest;
        if (preparedPdfs.containsKey(item.id)) {
          contentDigest = preparedPdfs[item.id]!.digest;
        } else {
          contentDigest = preparedData[item.id]!;
        }

        // Build CMS signed attributes
        final signedAttrs = buildSignedAttributes(
          contentDigest: contentDigest,
          cert: certInfo,
          signingTime: DateTime.now().toUtc(),
          digestAlgorithm: CmsDigestAlgorithm.sha384,
        );

        // Hash the signed attributes (this is what the card actually signs)
        final attrHash = hashSignedAttributes(
          signedAttrs,
          CmsDigestAlgorithm.sha384,
        );

        // Card signs the hash
        final cardSig = await cardReader.signHash(attrHash);

        // Build complete CMS envelope
        final cms = buildCms(
          signedAttributesDer: signedAttrs,
          signature: cardSig.signatureBytes,
          cert: certInfo,
          digestAlgorithm: CmsDigestAlgorithm.sha384,
          signatureAlgorithm: CmsSignatureAlgorithm.ecdsaSha384,
        );

        signatures[item.id] = cms;
      }
    } finally {
      await nfc.endSession();
    }

    // ── Phase D: Embed signatures and upload ──
    for (final item in workItems) {
      try {
        final pct =
            80 + ((workItems.indexOf(item) / workItems.length) * 15).round();
        onProgress?.call(item.id, 'Uploading...', pct);

        // Post progress callback
        await _callbackPoster.postProgress(
          item.callbacks,
          ProgressCallbackPayload(
            objectId: item.id,
            requestId: request.requestId,
            status: 'uploading',
            percentComplete: pct,
          ),
        );

        Uint8List signedContent;
        if (preparedPdfs.containsKey(item.id)) {
          // Embed CMS into the PDF
          signedContent = embedSignature(
            preparedPdfs[item.id]!,
            signatures[item.id]!,
          );
        } else {
          // For non-PDF: the signed content IS the CMS envelope
          signedContent = signatures[item.id]!;
        }

        // Upload
        final (statusCode, responseBody) = await _uploader.upload(
          config: item.upload,
          data: signedContent,
        );

        // Success callback
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
          content = ContentDefinition.fromJson({
            'mode': 'remote',
            'downloadUrl': group.downloadUrl ?? '',
            'headers': group.downloadHeaders,
          });
        } else {
          content = ContentDefinition.fromJson({
            'mode': 'inline',
            'encoding': gObj.inlineEncoding ?? 'utf8',
            'content': gObj.inlineValue ?? '',
          });
        }

        items.add(
          _WorkItem(
            id: gObj.id,
            dataType: group.dataType,
            content: content,
            pdfOptions: group.pdfOptions,
            upload: group.upload,
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
