// SignBridge — App theme

import 'package:flutter/material.dart';

class AppTheme {
  static const _primary = Color(0xFF1A73E8); // Google Blue
  static const _error = Color(0xFFD93025);
  static const _success = Color(0xFF34A853);

  static Color get successColor => _success;
  static Color get errorColor => _error;

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _primary,
    brightness: Brightness.light,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: _primary,
    brightness: Brightness.dark,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
