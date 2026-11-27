import 'package:material_ui/material_ui.dart';

/// The Mission Control palette; the only place the app spells a color.
///
/// Color never carries state on its own: widgets pair it with an icon and
/// text (see the accessibility constraint in the stage 2 plan).
abstract final class Palette {
  /// App and map background.
  static const Color background = Color(0xFF0B1020);

  /// Panels, sheets, cards and bars.
  static const Color panel = Color(0xFF111A30);

  /// Hairlines and panel borders.
  static const Color border = Color(0xFF1F2D4D);

  /// Anything the player can tap.
  static const Color cyan = Color(0xFF5FE1FF);

  /// Warnings: storage nearly full, an input running low.
  static const Color amber = Color(0xFFFFB547);

  /// Deficits and failures.
  static const Color red = Color(0xFFFF6470);

  /// Surpluses and successes.
  static const Color green = Color(0xFF63E6A4);

  /// Body text.
  static const Color text = Color(0xFFCFE3FF);

  /// Secondary text and labels.
  static const Color muted = Color(0xFF8EA3C9);
}

/// The app's single dark theme, built from [Palette].
ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Palette.cyan,
    onPrimary: Palette.background,
    secondary: Palette.cyan,
    onSecondary: Palette.background,
    tertiary: Palette.green,
    onTertiary: Palette.background,
    error: Palette.red,
    onError: Palette.background,
    surface: Palette.panel,
    onSurface: Palette.text,
    onSurfaceVariant: Palette.muted,
    surfaceContainerLowest: Palette.background,
    surfaceContainerLow: Palette.panel,
    surfaceContainer: Palette.panel,
    surfaceContainerHigh: Palette.panel,
    surfaceContainerHighest: Palette.border,
    outline: Palette.border,
    outlineVariant: Palette.border,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.background,
    canvasColor: Palette.background,
    dividerColor: Palette.border,
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
  );
}
