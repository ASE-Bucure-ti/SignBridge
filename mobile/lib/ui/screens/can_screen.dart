// SignBridge — CAN entry screen (Card Access Number, 6 digits)

import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../storage/app_storage.dart';

const _ceiSourceUrl = 'https://carteadeidentitate.gov.ro/despre/';

class CanScreen extends StatefulWidget {
  final void Function(String can) onSubmit;
  final bool firstTimeHint;

  const CanScreen({
    super.key,
    required this.onSubmit,
    this.firstTimeHint = false,
  });

  @override
  State<CanScreen> createState() => _CanScreenState();
}

class _CanScreenState extends State<CanScreen> {
  final _controller = TextEditingController();
  final _pageController = PageController();
  var _page = 0;
  var _value = '';
  String? _originalCan;
  var _alreadySaved = false;
  var _saving = false;
  var _hydrating = false;

  bool get _changed =>
      _alreadySaved ? _value != _originalCan : _value.length == 6;

  bool get _canSave =>
      _value.length == 6 && !_saving && (!_alreadySaved || _changed);

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final saved = await readStoredCan();
    if (!mounted) return;
    if (saved != null) {
      _hydrating = true;
      _controller.text = saved;
      setState(() {
        _alreadySaved = true;
        _originalCan = saved;
        _value = saved;
      });
      // pin_code_fields may fire onChanged/onCompleted when text is set;
      // ignore those until the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hydrating = false;
      });
    } else {
      setState(() => _alreadySaved = false);
    }
  }

  Future<void> _onPrimaryPressed() async {
    if (!_canSave) return;

    if (_alreadySaved) {
      final l10n = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.replaceCanConfirmTitle),
          content: Text(l10n.replaceCanConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await saveCan(_value);
      if (!mounted) return;
      widget.onSubmit(_value);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSource() async {
    await launchUrl(
      Uri.parse(_ceiSourceUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final legend = _page == 0
        ? [
            l10n.ceiFront1,
            l10n.ceiFront2,
            l10n.ceiFront3,
            l10n.ceiFront4,
            l10n.ceiFront5,
            l10n.ceiFront6,
            l10n.ceiFront7,
            l10n.ceiFront8,
          ]
        : [
            l10n.ceiBack1,
            l10n.ceiBack2,
            l10n.ceiBack3,
            l10n.ceiBack4,
          ];
    // Official site: front 1–8, back continues 9–12.
    final legendStart = _page == 0 ? 1 : 9;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.canScreenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            if (widget.firstTimeHint) ...[
              Text(l10n.canFirstTimeHint, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            if (_alreadySaved) ...[
              Text(
                l10n.canAlreadySaved,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              l10n.enterSixDigitCan,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.canLocationHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            PinCodeTextField(
              appContext: context,
              length: 6,
              autoDisposeControllers: false,
              controller: _controller,
              keyboardType: TextInputType.number,
              animationType: AnimationType.fade,
              autoFocus: false,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(8),
                fieldHeight: 50,
                fieldWidth: 44,
                activeFillColor: theme.colorScheme.surfaceContainerHighest,
                inactiveFillColor: theme.colorScheme.surface,
                selectedFillColor: theme.colorScheme.surfaceContainerHigh,
              ),
              enableActiveFill: true,
              onCompleted: (_) {},
              onChanged: (v) {
                if (_hydrating) return;
                setState(() => _value = v);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canSave ? _onPrimaryPressed : null,
              child: Text(_alreadySaved ? l10n.replaceCan : l10n.saveCan),
            ),
            const SizedBox(height: 28),
            Text(l10n.whereToFindOnCei, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 2058 / 1304,
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/cei-front.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/cei-back.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 2; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _page == 0 ? l10n.ceiFrontTitle : l10n.ceiBackTitle,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < legend.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${legendStart + i}. ${legend[i]}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              l10n.ceiSource,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _openSource,
                child: Text(l10n.openOfficialPage),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
