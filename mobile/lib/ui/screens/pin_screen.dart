// SignBridge — PIN entry screen (eSign PIN, 6 digits)

import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

class PinScreen extends StatefulWidget {
  /// Called when the user submits a complete 6-digit PIN.
  final void Function(String pin) onSubmit;

  const PinScreen({super.key, required this.onSubmit});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter eSign PIN')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 24),
            Text(
              'Enter your 6-digit eSign PIN',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'This is the PIN you set when the card was issued.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            PinCodeTextField(
              appContext: context,
              length: 6,
              controller: _controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              animationType: AnimationType.fade,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(8),
                fieldHeight: 50,
                fieldWidth: 44,
                activeFillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                inactiveFillColor: Theme.of(context).colorScheme.surface,
                selectedFillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
              ),
              enableActiveFill: true,
              onCompleted: (value) {
                widget.onSubmit(value);
              },
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
