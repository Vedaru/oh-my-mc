import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// A vertical list of labelled Material radio buttons.
///
/// Built from [m3.Radio] inside [m3.RadioGroup] rather than from
/// `RadioListTile`: a tile paints its own background and ink on the nearest
/// `Material`, so placing one inside the setup panel's decorated card trips
/// Flutter's "ink splashes may be invisible" assertion. A plain [m3.InkWell] row
/// keeps the tap target without claiming a background.
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

  @override
  Widget build(BuildContext context) {
    return m3.RadioGroup<T>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.start,
        children: [
          for (final entry in options.entries)
            m3.InkWell(
              key: m3.ValueKey('$keyPrefix-${entry.key}'),
              borderRadius: m3.BorderRadius.circular(8),
              onTap: () => onChanged(entry.key),
              child: m3.Padding(
                padding: const m3.EdgeInsets.symmetric(vertical: 2),
                child: m3.Row(
                  children: [
                    m3.Radio<T>(value: entry.key),
                    const m3.SizedBox(width: 10),
                    m3.Flexible(child: m3.Text(entry.value)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
