import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The accent palette, as a row of swatches.
///
/// A swatch row rather than a dropdown: the choice is a colour, and a colour picker
/// that names colours in a list makes the user translate a word into a colour
/// before choosing. The name is still there for screen readers and tooltips, where
/// "Teal" is the only thing available.
class AppAccentPicker extends StatelessWidget {
  const AppAccentPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final AccentChoice value;
  final ValueChanged<AccentChoice> onChanged;

  /// 32 px is the MD3 swatch size: big enough for the check mark to read, small
  /// enough that the six-accent palette stays one line in the settings column.
  static const swatchSize = 32.0;

  @override
  Widget build(BuildContext context) {
    return m3.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final entry in AppTheme.accents.entries)
          _Swatch(
            choice: entry.key,
            color: entry.value,
            selected: entry.key == value,
            onTap: () => onChanged(entry.key),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.choice,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final AccentChoice choice;
  final m3.Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final label = accentName(context.l10n, choice);

    // The check mark has to survive both a near-white and a near-black swatch, so
    // its colour comes from the swatch's own luminance rather than the theme.
    final onSwatch = color.computeLuminance() > 0.5
        ? const m3.Color(0xFF1A1A1A)
        : const m3.Color(0xFFFFFFFF);

    return m3.Semantics(
      label: label,
      selected: selected,
      button: true,
      child: m3.Tooltip(
        message: label,
        child: m3.InkWell(
          key: m3.ValueKey('accent-${choice.name}'),
          onTap: onTap,
          customBorder: const m3.CircleBorder(),
          child: m3.Container(
            width: AppAccentPicker.swatchSize,
            height: AppAccentPicker.swatchSize,
            decoration: m3.BoxDecoration(
              color: color,
              shape: m3.BoxShape.circle,
              border: m3.Border.all(
                // The selected swatch gets the page's own foreground as a ring,
                // which reads on light and dark surfaces alike; unselected ones
                // keep a hairline so a pale accent does not vanish.
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: selected
                ? m3.Icon(m3.Icons.check, size: 16, color: onSwatch)
                : null,
          ),
        ),
      ),
    );
  }
}

/// The localized name of an accent, for tooltips and screen readers.
String accentName(AppLocalizations l10n, AccentChoice choice) =>
    switch (choice) {
      AccentChoice.blue => l10n.accentBlue,
      AccentChoice.teal => l10n.accentTeal,
      AccentChoice.green => l10n.accentGreen,
      AccentChoice.orange => l10n.accentOrange,
      AccentChoice.red => l10n.accentRed,
      AccentChoice.purple => l10n.accentPurple,
    };
