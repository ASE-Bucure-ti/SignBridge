// SignBridge — first-launch onboarding (skipped if a deep link opens signing)

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../storage/app_storage.dart';
import 'can_screen.dart';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  Future<void> _finish(BuildContext context, {required bool setCan}) async {
    if (setCan) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CanScreen(
            firstTimeHint: true,
            onSubmit: (_) => Navigator.of(context).pop(),
          ),
        ),
      );
    }
    await markOnboardingDone();
    onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.onboardingTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.onboardingBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              _Step(
                icon: Icons.credit_card,
                title: l10n.onboardingStepCanTitle,
                body: l10n.onboardingStepCanBody,
              ),
              const SizedBox(height: 14),
              _Step(
                icon: Icons.link,
                title: l10n.onboardingStepLinkTitle,
                body: l10n.onboardingStepLinkBody,
              ),
              const SizedBox(height: 14),
              _Step(
                icon: Icons.contactless,
                title: l10n.onboardingStepHoldTitle,
                body: l10n.onboardingStepHoldBody,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _finish(context, setCan: true),
                child: Text(l10n.setCanNow),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _finish(context, setCan: false),
                child: Text(l10n.setCanLater),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Step({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
