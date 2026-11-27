import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/view/view_models.dart';

/// The always-visible bar: credits and what they earn a second, crew free
/// of supported, and the three resources held most, ticking live.
///
/// Each figure is an icon plus text (never color alone), its numbers in
/// the monospace face. The figures wrap onto more lines rather than
/// overflow, at any text size or number length.
class TopBar extends StatelessWidget {
  /// Creates the bar; [onSettings] opens the settings sheet.
  const TopBar({super.key, required this.onSettings});

  /// Opens the settings sheet.
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final view = topBar(ControllerScope.of(context));
    return Material(
      color: Palette.panel,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _Figure(
                        icon: Icons.paid_outlined,
                        value: view.credits,
                        detail: view.creditsRate,
                        semantics:
                            'Credits ${view.credits}, ${view.creditsRate}',
                      ),
                      _Figure(
                        icon: Icons.groups_outlined,
                        value: '${view.crewFree}/${view.crewTotal}',
                        detail: 'crew',
                        semantics:
                            'Crew: ${view.crewFree} free of ${view.crewTotal}',
                      ),
                      for (final p in view.pinned)
                        _Figure(
                          icon: Icons.inventory_2_outlined,
                          label: p.name,
                          value: p.value,
                          semantics: '${p.name}: ${p.value}',
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One figure: an icon, an optional label, a monospace value and an
/// optional muted detail, as one wrapping line of text.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.value,
    required this.semantics,
    this.label,
    this.detail,
  });

  final IconData icon;
  final String? label;
  final String value;
  final String? detail;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 18, color: Palette.cyan),
            ),
            if (label case final l?) TextSpan(text: ' $l'),
            TextSpan(text: ' $value', style: monoText(style)),
            if (detail case final d?)
              TextSpan(
                text: ' $d',
                style: monoText(style).copyWith(color: Palette.muted),
              ),
          ],
        ),
      ),
    );
  }
}
