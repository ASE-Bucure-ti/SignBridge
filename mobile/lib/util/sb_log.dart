// SignBridge — debug-only console logging

import 'package:flutter/foundation.dart';

/// Prints `SB …` only in debug / profile builds. Silent in release.
void sbLog(String message) {
  if (kReleaseMode) return;
  // ignore: avoid_print
  print('SB $message');
}
