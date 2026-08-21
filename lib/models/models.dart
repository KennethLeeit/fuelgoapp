import 'package:flutter/material.dart';

/// Deterministic color per brand/operator name, so real-world brands still
/// get a stable, distinct color without needing a hand-curated lookup table.
Color colorForName(String? name) {
  const palette = [
    Color(0xFF00A99D),
    Color(0xFFED1C24),
    Color(0xFF1B3F94),
    Color(0xFFEE7623),
    Color(0xFFE0102A),
    Color(0xFF27AE60),
    Color(0xFF00AEEF),
    Color(0xFF2ECC71),
    Color(0xFF8E44AD),
    Color(0xFF2F6FED),
  ];
  if (name == null || name.isEmpty) return palette[0];
  final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
  return palette[hash % palette.length];
}
