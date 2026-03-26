// SignBridge — App widget with routing and deep link handling

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:logger/logger.dart';
import 'protocol/models.dart';
import 'processing/request_handler.dart';
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
        _startSigningFlow(request);
      } else {
        _showError(response.errors?.first.message ?? 'Request rejected');
      }
    } catch (e) {
      _log.e('Deep link handling failed: $e');
      _showError(e.toString());
    }
  }

  void _startSigningFlow(SignRequest request) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => SigningScreen(request: request)),
    );
  }

  void _showError(String message) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          success: false,
          title: 'Request Error',
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
      title: 'SignBridge',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      navigatorKey: _navigatorKey,
      home: const HomeScreen(),
    );
  }
}
