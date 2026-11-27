import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';

void main() {
  test('palette uses the Mission Control hex values', () {
    expect(Palette.background, const Color(0xFF0B1020));
    expect(Palette.panel, const Color(0xFF111A30));
    expect(Palette.border, const Color(0xFF1F2D4D));
    expect(Palette.cyan, const Color(0xFF5FE1FF));
    expect(Palette.amber, const Color(0xFFFFB547));
    expect(Palette.red, const Color(0xFFFF6470));
    expect(Palette.green, const Color(0xFF63E6A4));
    expect(Palette.text, const Color(0xFFCFE3FF));
    expect(Palette.muted, const Color(0xFF8EA3C9));
  });

  test('buildTheme paints the scaffold with the background color', () {
    expect(buildTheme().scaffoldBackgroundColor, Palette.background);
  });

  test('buildTheme is a dark scheme with cyan as the interactive color', () {
    final theme = buildTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, Palette.cyan);
    expect(theme.colorScheme.surface, Palette.panel);
    expect(theme.colorScheme.onSurface, Palette.text);
    expect(theme.colorScheme.error, Palette.red);
    expect(theme.colorScheme.outline, Palette.border);
  });

  test('monoText sets the monospace face with fallbacks, no fetching', () {
    final style = monoText(const TextStyle(fontSize: 13, color: Palette.text));
    expect(style.fontFamily, 'monospace');
    expect(style.fontFamilyFallback, ['RobotoMono', 'Courier New']);
    expect(style.fontSize, 13);
    expect(style.color, Palette.text);
    expect(monoText(null).fontFamily, monoFontFamily);
  });

  test('body text uses the text color', () {
    expect(buildTheme().textTheme.bodyMedium?.color, Palette.text);
  });
}
