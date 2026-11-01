// SignBridge — Home screen (idle state)

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../storage/app_storage.dart';
import '../theme.dart';
import 'can_screen.dart';
import 'onboarding_screen.dart';
import 'signing_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _canSaved;
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final can = await readStoredCan();
    final onboarded = await isOnboardingDone();
    if (!mounted) return;
    setState(() {
      _canSaved = can != null;
      _onboardingDone = onboarded;
    });
  }

  Future<void> _openCan({bool firstTime = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CanScreen(
          firstTimeHint: firstTime,
          onSubmit: (_) => Navigator.of(context).pop(),
        ),
      ),
    );
    await _refresh();
  }

  void _startSamplePdf() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SigningScreen.localPoc()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingDone == false) {
      return OnboardingScreen(onFinished: _refresh);
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final canReady = _canSaved == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: Icon(
              Icons.credit_card,
              color: canReady ? AppTheme.successColor : null,
            ),
            tooltip: canReady ? l10n.changeCan : l10n.setCan,
            onPressed: () => _openCan(firstTime: !canReady),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: _startSamplePdf,
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 96,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(l10n.appSubtitle, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                l10n.waitingForRequest,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _CanStatusChip(
                ready: canReady,
                loading: _canSaved == null,
                readyLabel: l10n.canSaved,
                missingLabel: l10n.canNotSet,
                onTap: () => _openCan(firstTime: !canReady),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.homeDeepLinkHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanStatusChip extends StatelessWidget {
  final bool ready;
  final bool loading;
  final String readyLabel;
  final String missingLabel;
  final VoidCallback onTap;

  const _CanStatusChip({
    required this.ready,
    required this.loading,
    required this.readyLabel,
    required this.missingLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 36,
        width: 36,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final theme = Theme.of(context);
    final bg = ready
        ? AppTheme.successColor.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest;
    final fg = ready
        ? AppTheme.successColor
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ready ? Icons.check_circle : Icons.credit_card_off_outlined,
                size: 20,
                color: fg,
              ),
              const SizedBox(width: 8),
              Text(
                ready ? readyLabel : missingLabel,
                style: theme.textTheme.labelLarge?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
