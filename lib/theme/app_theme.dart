import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class OsColors {
  static const bg = Color(0xFF100D1F);
  static const surface = Color(0xFF1B1730);
  static const surface2 = Color(0xFF26203D);
  static const border = Color(0xFF332C4F);
  static const purple = Color(0xFF9B7BFF);
  static const purpleDeep = Color(0xFF7C3AED);
  static const coral = Color(0xFFFF7185);
  static const amber = Color(0xFFFFC857);
  static const text = Color(0xFFF7F4FF);
  static const muted = Color(0xFFAAA3C0);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFFFF6B7A)],
  );
}

ThemeData buildOsTheme() {
  final base = ThemeData.dark();
  final textTheme = GoogleFonts.manropeTextTheme(base.textTheme)
      .apply(bodyColor: OsColors.text, displayColor: OsColors.text);

  OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: w),
      );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
  final buttonText = GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: OsColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: OsColors.purple,
      onPrimary: Color(0xFF140E2B),
      secondary: OsColors.coral,
      surface: OsColors.surface,
      onSurface: OsColors.text,
      error: OsColors.coral,
    ),
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OsColors.surface,
      border: outline(OsColors.border),
      enabledBorder: outline(OsColors.border),
      focusedBorder: outline(OsColors.purple, 1.6),
      errorBorder: outline(OsColors.coral),
      focusedErrorBorder: outline(OsColors.coral, 1.6),
      hintStyle: const TextStyle(color: OsColors.muted),
      labelStyle: const TextStyle(color: OsColors.muted),
      floatingLabelStyle: const TextStyle(color: OsColors.purple, fontWeight: FontWeight.w700),
      helperStyle: const TextStyle(color: OsColors.muted, fontSize: 11),
      prefixIconColor: OsColors.muted,
      suffixIconColor: OsColors.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: buttonText,
        backgroundColor: OsColors.purpleDeep,
        foregroundColor: Colors.white,
        disabledBackgroundColor: OsColors.surface2,
        disabledForegroundColor: OsColors.muted,
        elevation: 0,
        shadowColor: OsColors.purpleDeep,
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: buttonText,
        backgroundColor: OsColors.purpleDeep,
        foregroundColor: Colors.white,
        elevation: 6,
        shadowColor: OsColors.purpleDeep.withValues(alpha: .5),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        highlightColor: OsColors.purple.withValues(alpha: .14),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : OsColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? OsColors.purpleDeep : OsColors.surface2),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.transparent : OsColors.border),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: OsColors.purple,
      inactiveTrackColor: OsColors.surface2,
      thumbColor: OsColors.coral,
      overlayColor: OsColors.coral.withValues(alpha: .18),
      trackHeight: 5,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? OsColors.purpleDeep : Colors.transparent),
      side: const BorderSide(color: OsColors.muted, width: 1.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: OsColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: OsColors.border.withValues(alpha: .8)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: OsColors.purpleDeep,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        foregroundColor: OsColors.text,
        side: const BorderSide(color: OsColors.border),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OsColors.purple,
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: OsColors.bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: OsColors.text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: OsColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: OsColors.purple.withValues(alpha: .22),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? OsColors.text : OsColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? OsColors.purple : OsColors.muted);
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OsColors.surface,
      selectedColor: OsColors.purple.withValues(alpha: .22),
      side: const BorderSide(color: OsColors.border),
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: const TextStyle(color: OsColors.text, fontWeight: FontWeight.w700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: OsColors.surface2,
      contentTextStyle: const TextStyle(color: OsColors.text, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OsColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    // Every AlertDialog in the app (admin, chat, profile…) gets the OS look.
    dialogTheme: DialogThemeData(
      backgroundColor: OsColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: OsColors.border.withValues(alpha: .8)),
      ),
      titleTextStyle: GoogleFonts.manrope(fontSize: 19, fontWeight: FontWeight.w900, color: OsColors.text),
      contentTextStyle: GoogleFonts.manrope(fontSize: 14, height: 1.45, color: OsColors.muted),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
    ),
    dividerTheme: const DividerThemeData(color: OsColors.border, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: OsColors.purple),
  );
}