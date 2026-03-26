// SignBridge — Signing screen (active signing flow with NFC)

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../../protocol/models.dart';
import '../../protocol/errors.dart';
import '../../processing/request_handler.dart';
import 'can_screen.dart';
import 'pin_screen.dart';
import 'result_screen.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

const _canStorageKey = 'signbridge_can';

class SigningScreen extends StatefulWidget {
  final SignRequest request;

  const SigningScreen({super.key, required this.request});

  @override
  State<SigningScreen> createState() => _SigningScreenState();
}

class _SigningScreenState extends State<SigningScreen> {
  final _handler = RequestHandler();
  final _storage = const FlutterSecureStorage();

  String _status = 'Preparing...';
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

    try {
      await _handler.processRequest(
        widget.request,
        requestCan: _requestCan,
        requestPin: _requestPin,
        onProgress: _onProgress,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ResultScreen(
            success: true,
            title: 'Signed Successfully',
            message: 'All documents have been signed and uploaded.',
          ),
        ),
      );
    } on SigningError catch (e) {
      _log.e('Signing failed: $e');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            success: false,
            title: 'Signing Failed',
            message: e.message,
          ),
        ),
      );
    } catch (e) {
      _log.e('Unexpected error: $e');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            success: false,
            title: 'Error',
            message: e.toString(),
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
      _status = status;
      _progress = percent / 100.0;
      _showNfcPrompt = status.contains('Tap') || status.contains('card');
    });
  }

  Future<String?> _requestCan() async {
    // Try stored CAN first
    final stored = await _storage.read(key: _canStorageKey);
    if (stored != null && stored.length == 6) return stored;

    // Ask user for CAN
    if (!mounted) return null;
    final can = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            CanScreen(onSubmit: (can) => Navigator.of(context).pop(can)),
      ),
    );
    return can;
  }

  Future<String?> _requestPin() async {
    if (!mounted) return null;
    setState(() {
      _status = 'Enter your eSign PIN';
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
        _status = 'Tap your eID card...';
        _showNfcPrompt = true;
      });
    }
    return pin;
  }

  @override
  Widget build(BuildContext context) {
    final objectCount =
        (widget.request.objects?.length ?? 0) +
        (widget.request.objectGroups?.fold<int>(
              0,
              (sum, g) => sum + g.objects.length,
            ) ??
            0);

    return Scaffold(
      appBar: AppBar(title: const Text('Signing')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // NFC icon — animated when waiting for tap
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
              _status,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '$objectCount document(s)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('${(_progress * 100).toInt()}%'),
            const SizedBox(height: 48),
            if (_showNfcPrompt)
              Text(
                'Hold your eID card to the back of the phone\n'
                'and keep it still until signing completes.',
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
