// SignBridge — App widget with routing and deep link handling

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_links/app_links.dart';
import 'package:logger/logger.dart';
import 'l10n/app_localizations.dart';
import 'protocol/models.dart';
import 'protocol/user_messages.dart';
import 'processing/request_handler.dart';
import 'storage/app_storage.dart';
import 'ui/theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/signing_screen.dart';
import 'ui/screens/result_screen.dart';

final _log = Logger(printer: PrettyPrinter(methodCount: 0));

class SignBridgeApp extends StatefulWidget {
  const SignBridgeApp({super.key});

  @override
  State<SignBridgeApp> createState() => _SignBridgeAppState();
}

class _SignBridgeAppState extends State<SignBridgeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _requestHandler = RequestHandler();
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle link that launched the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      _log.e('Failed to get initial link: $e');
    }

    // Handle links while app is running (warm start)
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (e) => _log.e('Deep link stream error: $e'),
    );
  }

  void _handleDeepLink(Uri uri) {
    _log.i('Received deep link: $uri');

    if (uri.host != 'sign') {
      _log.w('Unknown deep link host: ${uri.host}');
      return;
    }

    try {
      final request = _requestHandler.parseDeepLink(uri);
      final response = _requestHandler.validateAndAck(request);

      if (response.status == 'accepted') {
        // Don't block deep-link signing behind onboarding; CAN is collected
        // inside the signing flow if missing.
        markOnboardingDone();
        _startSigningFlow(request);
      } else {
        final ctx = _navigatorKey.currentContext;
        final fallback = ctx != null
            ? AppLocalizations.of(ctx).requestErrorTitle
            : 'Request rejected';
        _showError(response.errors?.first.message ?? fallback);
      }
    } catch (e) {
      _log.e('Deep link handling failed: $e');
      final ctx = _navigatorKey.currentContext;
      _showError(
        ctx != null
            ? userFacingMessage(AppLocalizations.of(ctx), e)
            : e.toString(),
      );
    }
  }

  void _startSigningFlow(SignRequest request) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => SigningScreen(request: request)),
    );
  }

  void _showError(String message) {
    final ctx = _navigatorKey.currentContext;
    final title = ctx != null
        ? AppLocalizations.of(ctx).requestErrorTitle
        : 'Request error';
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          success: false,
          title: title,
          message: message,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      navigatorKey: _navigatorKey,
      localeListResolutionCallback: (locales, supported) {
        for (final locale in locales ?? const <Locale>[]) {
          for (final s in supported) {
            if (s.languageCode == locale.languageCode) return s;
          }
        }
        return const Locale('en');
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    );
  }
}
