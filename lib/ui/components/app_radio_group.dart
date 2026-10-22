import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';

/// A vertical list of labelled Material radio buttons.
///
/// Built from [m3.Radio] inside [m3.RadioGroup] rather than from
/// `RadioListTile`: a tile paints its own background and ink on the nearest
/// `Material`, so placing one inside a decorated card used to trip Flutter's "ink
/// splashes may be invisible" assertion. A plain [m3.InkWell] row keeps the tap
/// target without claiming a background.
///
/// `Radio.groupValue` is deprecated in favour of an ancestor [m3.RadioGroup],
/// which is why group state is owned there rather than passed to each radio.
class AppRadioGroup<T> extends StatelessWidget {
  const AppRadioGroup({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.keyPrefix,
    super.key,
  });

  final T value;
  final Map<T, String> options;
  final m3.ValueChanged<T> onChanged;

  /// Prefix for each row's `ValueKey`, so tests can address one option.
  final String keyPrefix;

  /// A row is 40 px tall, which is MD3's control height for a single-line choice
  /// and what keeps a two-option group from reading like a paragraph of text.
  static const _rowHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    return m3.RadioGroup<T>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.start,
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          for (final entry in options.entries)
            m3.InkWell(
              key: m3.ValueKey('$keyPrefix-${entry.key}'),
              borderRadius: m3.BorderRadius.circular(8),
              onTap: () => onChanged(entry.key),
              child: m3.ConstrainedBox(
                constraints: const m3.BoxConstraints(minHeight: _rowHeight),
                child: m3.Padding(
                  padding: const m3.EdgeInsets.symmetric(horizontal: 4),
                  child: m3.Row(
                    children: [
                      // Default density: MD3's 20 px radio is the control this
                      // list should look like, and compact density shrinks the
                      // circle along with its tap target.
                      m3.Radio<T>(value: entry.key),
                      const m3.SizedBox(width: 8),
                      // The label carries the app's body style explicitly: an
                      // unstyled `Text` inherits whatever the nearest
                      // `DefaultTextStyle` happens to be, which is how this list
                      // once rendered as 48 px red error text.
                      m3.Expanded(
                        child: m3.Text(
                          entry.value,
                          style: AppTheme.body(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
