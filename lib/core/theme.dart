import 'package:flutter/material.dart';

import '../data/models.dart';

/// One identity, tuned per stage: warmer and slightly larger for the young
/// grades, calmer for older students.
class AppTheme {
  const AppTheme._();

  static Color seedFor(Stage? stage) => switch (stage) {
    Stage.lowerBasic => const Color(0xFFEA580C),
    Stage.upperBasic || null => const Color(0xFF0F766E),
    Stage.secondary => const Color(0xFF4338CA),
  };

  /// Young pupils get slightly larger text (applied on top of the device's
  /// own text size setting).
  static double textScaleFor(Stage? stage) => stage == Stage.lowerBasic ? 1.1 : 1.0;

  static ThemeData light(Stage? stage) => _build(ColorScheme.fromSeed(seedColor: seedFor(stage)));

  static ThemeData dark(Stage? stage) =>
      _build(ColorScheme.fromSeed(seedColor: seedFor(stage), brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }
}

const _subjectIcons = <String, IconData>{
  'menu_book': Icons.menu_book,
  'calculate': Icons.calculate,
  'science': Icons.science,
  'mosque': Icons.mosque,
  'translate': Icons.translate,
  'flag': Icons.flag,
  'public': Icons.public,
  'computer': Icons.computer,
  'bolt': Icons.bolt,
  'biotech': Icons.biotech,
  'eco': Icons.eco,
  'map': Icons.map,
  'history_edu': Icons.history_edu,
};

IconData subjectIcon(String name) => _subjectIcons[name] ?? Icons.school;
