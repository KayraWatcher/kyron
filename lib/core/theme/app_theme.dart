import 'package:flutter/material.dart';

/// GOLD renk paleti - modern, profesyonel finans uygulamasi.
///
/// Renkler "iyilesme/kotulesme" anlam tasir:
///   * yesil  -> yukselis / kari
///   * kirmizi-> dusus / zarar
///   * sari   -> altin vurgusu
abstract final class AppPalette {
  // Marka
  static const Color gold = Color(0xFFD4A017);
  static const Color goldDeep = Color(0xFFB8860B);

  // Yon renkleri (Kadin/Dusuk renk kisaltmalari kullanilmaz)
  static const Color gain = Color(0xFF12A150);
  static const Color gainSoft = Color(0xFFE6F6EE);
  static const Color loss = Color(0xFFE53935);
  static const Color lossSoft = Color(0xFFFDECEA);
  static const Color neutral = Color(0xFF8A94A6);

  // Acik tema
  static const Color lightBg = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF1F3F6);
  static const Color lightBorder = Color(0xFFE3E6EC);
  static const Color lightText = Color(0xFF101828);
  static const Color lightTextSecondary = Color(0xFF667085);
  static const Color lightTextMuted = Color(0xFF98A2B3);

  // Koyu tema
  static const Color darkBg = Color(0xFF0B0F16);
  static const Color darkSurface = Color(0xFF131924);
  static const Color darkSurfaceAlt = Color(0xFF1B2331);
  static const Color darkBorder = Color(0xFF273041);
  static const Color darkText = Color(0xFFF2F4F7);
  static const Color darkTextSecondary = Color(0xFF9AA4B8);
  static const Color darkTextMuted = Color(0xFF6B7488);

  /// Yuzde degisimine gore renk.
  static Color direction(double? value) {
    if (value == null || !value.isFinite || value == 0) return neutral;
    return value > 0 ? gain : loss;
  }

  static Color directionForChange(double? change, double? percent) {
    final v = percent ?? change;
    return direction(v);
  }
}

/// Tema olusturucu.
///
/// Kolay okunabilirlik, mobil optimizasyon ve gereksiz animasyondan
/// kacinma ilkesine gore ayarlanmistir.
abstract final class AppTheme {
  static const String _fontFamily = 'Roboto';

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: AppPalette.lightBg,
        surface: AppPalette.lightSurface,
        surfaceAlt: AppPalette.lightSurfaceAlt,
        border: AppPalette.lightBorder,
        text: AppPalette.lightText,
        textSecondary: AppPalette.lightTextSecondary,
        textMuted: AppPalette.lightTextMuted,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: AppPalette.darkBg,
        surface: AppPalette.darkSurface,
        surfaceAlt: AppPalette.darkSurfaceAlt,
        border: AppPalette.darkBorder,
        text: AppPalette.darkText,
        textSecondary: AppPalette.darkTextSecondary,
        textMuted: AppPalette.darkTextMuted,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfaceAlt,
    required Color border,
    required Color text,
    required Color textSecondary,
    required Color textMuted,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppPalette.gold : AppPalette.goldDeep,
      onPrimary: isDark ? const Color(0xFF1A1200) : Colors.white,
      secondary: AppPalette.gold,
      onSecondary: const Color(0xFF1A1200),
      error: AppPalette.loss,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? AppPalette.lightSurface : AppPalette.darkSurface,
      onInverseSurface: isDark ? AppPalette.lightText : AppPalette.darkText,
      inversePrimary: AppPalette.gold,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: bg,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: AppPalette.gold,
        labelStyle: TextStyle(fontSize: 13, color: text),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? AppPalette.gold : AppPalette.goldDeep,
        unselectedLabelColor: textSecondary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        indicatorColor: isDark ? AppPalette.gold : AppPalette.goldDeep,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: (isDark ? AppPalette.gold : AppPalette.goldDeep)
            .withValues(alpha: 0.14),
        height: 64,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? (isDark ? AppPalette.gold : AppPalette.goldDeep)
                : textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? (isDark ? AppPalette.gold : AppPalette.goldDeep)
                : textSecondary,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppPalette.gold : AppPalette.goldDeep,
            width: 1.6,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? AppPalette.gold : AppPalette.goldDeep,
          foregroundColor: isDark ? const Color(0xFF1A1200) : Colors.white,
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppPalette.gold : AppPalette.goldDeep,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppPalette.darkSurfaceAlt : AppPalette.lightText,
        contentTextStyle: TextStyle(
          color: isDark ? AppPalette.darkText : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: textSecondary,
        textColor: text,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? AppPalette.gold : AppPalette.goldDeep,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? AppPalette.gold : AppPalette.goldDeep)
              : textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isDark ? AppPalette.gold : AppPalette.goldDeep)
                  .withValues(alpha: 0.35)
              : surfaceAlt,
        ),
      ),
    );
  }
}

/// Tema tercihi (dark/light/system) icin anahtarlar.
abstract final class ThemeKeys {
  static const String themeMode = 'settings.themeMode';
}
