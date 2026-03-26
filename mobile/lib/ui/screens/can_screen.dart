// SignBridge — CAN entry screen (Card Access Number, 6 digits)

import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _canStorageKey = 'signbridge_can';

class CanScreen extends StatefulWidget {
  /// Called when CAN is submitted and saved.
  final void Function(String can) onSubmit;

  const CanScreen({super.key, required this.onSubmit});

  @override
  State<CanScreen> createState() => _CanScreenState();
}

class _CanScreenState extends State<CanScreen> {
  final _controller = TextEditingController();
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _storage.read(key: _canStorageKey);
    if (saved != null && mounted) {
      _controller.text = saved;
    }
  }

  Future<void> _save(String can) async {
    await _storage.write(key: _canStorageKey, value: can);
    widget.onSubmit(can);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Card Access Number')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.credit_card, size: 64),
            const SizedBox(height: 24),
            Text(
              'Enter the 6-digit CAN',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'The CAN is printed on the front of your eID card,\n'
              'in the bottom-right area.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            PinCodeTextField(
              appContext: context,
              length: 6,
              controller: _controller,
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
              onCompleted: _save,
              onChanged: (_) {},
            ),
            const SizedBox(height: 16),
            // TODO: Add image showing CAN location on card
          ],
        ),
      ),
    );
  }
}
