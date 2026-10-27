// SignBridge — Home screen (idle state)

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'can_screen.dart';
import 'signing_screen.dart';

const _canStorageKey = 'signbridge_can';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SignBridge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.credit_card),
            tooltip: 'Change CAN',
            onPressed: () => _changeCan(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 96,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'SignBridge Mobile',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Waiting for signing request...',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SigningScreen.localPoc(),
                    ),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Sign test PDF'),
              ),
              const SizedBox(height: 12),
              Text(
                'Signs the bundled PDF that already has an AcroForm\n'
                'field named Signature1. No server required.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Open a document from your browser to start signing.\n'
                'The app will receive the request via deep link.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeCan(BuildContext context) {
    // Clear stored CAN so the screen starts fresh
    const FlutterSecureStorage().delete(key: _canStorageKey);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanScreen(onSubmit: (_) => Navigator.of(context).pop()),
      ),
    );
  }
}
