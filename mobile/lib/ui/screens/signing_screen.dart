// SignBridge — Signing screen (active signing flow with NFC)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/status_l10n.dart';
import '../../protocol/models.dart';
import '../../protocol/errors.dart';
import '../../protocol/user_messages.dart';
import '../../processing/engine.dart';
import '../../processing/request_handler.dart';
import '../../storage/app_storage.dart';
import '../../util/sb_log.dart';
import 'can_screen.dart';
import 'pin_screen.dart';
import 'result_screen.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

class SigningScreen extends StatefulWidget {
  final SignRequest? request;
  final bool localPoc;

  const SigningScreen({super.key, required SignRequest this.request})
    : localPoc = false;

  const SigningScreen.localPoc({super.key}) : request = null, localPoc = true;

  @override
  State<SigningScreen> createState() => _SigningScreenState();
}

class _SigningScreenState extends State<SigningScreen> {
  final _handler = RequestHandler();

  String _statusKey = 'Preparing...';
  double _progress = 0;
  bool _processing = false;
  bool _showNfcPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSigning());
  }

  Future<void> _startSigning() async {
    if (_processing) return;
    _processing = true;
    final l10n = AppLocalizations.of(context);

    try {
      if (widget.localPoc) {
        final raw = await rootBundle.load(
          'assets/poc/signbridge-poc-acroform.pdf',
        );
        final signed = await Engine().signLocalPdf(
          pdfBytes: raw.buffer.asUint8List(
            raw.offsetInBytes,
            raw.lengthInBytes,
          ),
          requestCan: _requestCan,
          requestPin: _requestPin,
          onProgress: _onProgress,
          fieldLabel: 'Signature1',
        );
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/signbridge-poc-signed.pdf');
        await file.writeAsBytes(signed, flush: true);
        sbLog('saved ${file.path}');

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              success: true,
              title: l10n.sampleSignedTitle,
              message: l10n.sampleSignedMessage,
            ),
          ),
        );
        return;
      }

      final request = widget.request;
      if (request == null) {
        throw StateError('Missing sign request');
      }
      await _handler.processRequest(
        request,
        requestCan: _requestCan,
        requestPin: _requestPin,
        onProgress: _onProgress,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            success: true,
            title: l10n.signedSuccessfullyTitle,
            message: l10n.signedSuccessfullyMessage,
          ),
        ),
      );
    } on SigningError catch (e, st) {
      _log.e('Signing failed: $e', error: e, stackTrace: st);
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            success: false,
            title: loc.signingFailedTitle,
            message: userFacingMessage(loc, e),
          ),
        ),
      );
    } catch (e, st) {
      _log.e('Unexpected error: $e', error: e, stackTrace: st);
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            success: false,
            title: loc.errorTitle,
            message: userFacingMessage(loc, e),
          ),
        ),
      );
    } finally {
      _processing = false;
    }
  }

  void _onProgress(String objectId, String status, int percent) {
    if (!mounted) return;
    setState(() {
      _statusKey = status;
      _progress = percent / 100.0;
      _showNfcPrompt = status.contains('Tap') ||
          status.contains('card') ||
          status.contains('Hold');
    });
  }

  Future<String?> _requestCan() async {
    if (!mounted) return null;
    setState(() {
      _statusKey = 'Checking CAN...';
      _showNfcPrompt = false;
    });

    final stored = await readStoredCan();
    if (stored != null) {
      sbLog('using stored CAN (length 6)');
      return stored;
    }

    if (!mounted) return null;
    final can = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CanScreen(
          firstTimeHint: true,
          onSubmit: (can) => Navigator.of(context).pop(can),
        ),
      ),
    );
    return can;
  }

  Future<String?> _requestPin() async {
    if (!mounted) return null;
    setState(() {
      _statusKey = 'Enter your signing PIN';
      _showNfcPrompt = false;
    });
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            PinScreen(onSubmit: (pin) => Navigator.of(context).pop(pin)),
      ),
    );
    if (pin != null) {
      setState(() {
        _statusKey = 'Tap your eID card...';
        _showNfcPrompt = true;
      });
    }
    return pin;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final objectCount = widget.localPoc
        ? 1
        : (widget.request!.objects?.length ?? 0) +
              (widget.request!.objectGroups?.fold<int>(
                    0,
                    (sum, g) => sum + g.objects.length,
                  ) ??
                  0);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.signingTitle)),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                _showNfcPrompt ? Icons.contactless_rounded : Icons.draw_rounded,
                key: ValueKey(_showNfcPrompt),
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              localizeStatus(l10n, _statusKey),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.documentsCount(objectCount),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toInt()}%'),
            const SizedBox(height: 48),
            if (_showNfcPrompt)
              Text(
                l10n.holdCardHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
