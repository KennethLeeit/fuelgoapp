import 'package:flutter/material.dart';

/// Central color palette matching the FuelGo screen designs. These stay
/// `const` and unchanged — most of the app references them as plain
/// static field access (`AppColors.textGrey`) inside `const` widget
/// constructors (70+ places), so turning them into mutable/swappable
/// values would break compilation everywhere they're used. Dark mode is
/// implemented at the proper Flutter layer instead — see AppTheme.dark()
/// and ThemeService — which correctly darkens the app's chrome (Scaffold
/// background, AppBar, inputs, dialogs, snackbars, buttons, chips) since
/// those all resolve through Theme.of(context) already.
///
/// Individual screens/cards that hardcode AppColors.textDark, .textGrey,
/// .cardBorder, or Colors.white directly (rather than through the theme)
/// won't change on their own — that's a larger, screen-by-screen
/// migration to make them theme-aware, same as the earlier UI-consistency
/// pass. See DARK_MODE_NOTES.md for exactly what's covered today.
class AppColors {
  static const Color navy = Color(0xFF0E1F63);
  static const Color primaryBlue = Color(0xFF2F6FED);
  static const Color fuelOrange = Color(0xFFFF9800);
  static const Color evGreen = Color(0xFF27AE60);
  static const Color background = Color(0xFFEFF2F8);
  static const Color cardBorder = Color(0xFFD6DCE8);
  static const Color textDark = Color(0xFF1F2430);
  static const Color textGrey = Color(0xFF727B8C);
}

/// Dark-mode equivalents of the above, for the parts of the app that have
/// been made theme-aware (read via `Theme.of(context)` / `AppDarkColors`
/// directly rather than the fixed `AppColors` constants).
class AppDarkColors {
  static const Color background = Color(0xFF13151C);
  static const Color surface = Color(0xFF1D2029);
  static const Color cardBorder = Color(0xFF2E323F);
  static const Color textDark = Color(0xFFF1F2F6);
  static const Color textGrey = Color(0xFFA1A8B8);
}

class AppTheme {
  static ThemeData light() => _build(isDark: false);
  static ThemeData dark() => _build(isDark: true);

  static ThemeData _build({required bool isDark}) {
    final surface = isDark ? AppDarkColors.surface : Colors.white;
    final background = isDark ? AppDarkColors.background : AppColors.background;
    final cardBorder = isDark ? AppDarkColors.cardBorder : AppColors.cardBorder;
    final textDark = isDark ? AppDarkColors.textDark : AppColors.textDark;
    final textGrey = isDark ? AppDarkColors.textGrey : AppColors.textGrey;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: AppColors.primaryBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        primary: AppColors.primaryBlue,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: surface,
      ),
      cardColor: surface,
      textTheme: isDark
          ? Typography.whiteMountainView.apply(bodyColor: textDark, displayColor: textDark)
          : Typography.blackMountainView.apply(bodyColor: textDark, displayColor: textDark),
      iconTheme: IconThemeData(color: textDark),
      dividerColor: cardBorder,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textDark,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: textGrey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          shadowColor: AppColors.primaryBlue.withValues(alpha: .28),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: AppColors.navy.withValues(alpha: .22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: textGrey,
          fontSize: 14,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2E3A) : AppColors.navy,
        elevation: 10,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: const Color(0xFF9FC1FF),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF262A35) : const Color(0xFFF1F3F6),
        labelStyle: TextStyle(color: textDark, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: textGrey,
      ),
    );
  }
}
