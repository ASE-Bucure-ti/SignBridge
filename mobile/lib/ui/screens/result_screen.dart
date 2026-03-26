// SignBridge — Result screen (success / error)

import 'package:flutter/material.dart';
import '../theme.dart';

class ResultScreen extends StatelessWidget {
  final bool success;
  final String title;
  final String message;
  final VoidCallback? onDone;

  const ResultScreen({
    super.key,
    required this.success,
    required this.title,
    required this.message,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? AppTheme.successColor : AppTheme.errorColor;
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    return Scaffold(
      appBar: AppBar(title: Text(success ? 'Success' : 'Error')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 96, color: color),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed:
                  onDone ??
                  () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
