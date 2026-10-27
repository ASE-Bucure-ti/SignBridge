// SignBridge Mobile — Entry point

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Logger.level = Level.trace;
  runApp(const SignBridgeApp());
}
