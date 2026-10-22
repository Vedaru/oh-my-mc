import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// A Material slider with a screen-reader label.
///
/// `m3.Slider` has no `semanticLabel`; it announces the numeric value only. A
/// memory slider that says "2048" without saying "Memory" is not usable with a
/// screen reader. The label is merged into the slider's own node so its value
/// and increase/decrease actions are not split off into a separate stop.
class AppSlider extends StatelessWidget {
  const AppSlider({
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.divisions,
    this.label,
    this.valueLabel,
    this.onChangeEnd,
    super.key,
  });

  final double value;
  final m3.ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;

  /// What the slider controls, e.g. "Memory".
  final String? label;

  /// A human-readable rendering of the current value for the value indicator.
  final String? valueLabel;

  final m3.ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final slider = m3.Slider(
      value: value,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: divisions,
      label: valueLabel,
    );

    final label = this.label;
    if (label == null) return slider;
    return m3.MergeSemantics(
      child: m3.Semantics(label: label, child: slider),
    );
  }
}
