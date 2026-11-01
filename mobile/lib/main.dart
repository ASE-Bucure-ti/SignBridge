// SignBridge Mobile — Entry point

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.level = kReleaseMode ? Level.warning : Level.trace;
  runApp(const SignBridgeApp());
}
