import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// A Material switch with a screen-reader label.
///
/// `m3.Switch` has no `semanticLabel`, so a bare switch beside a piece of text
/// is announced as an unlabelled toggle. The label is attached to the switch's
/// own node rather than put in front of it: the switch reports its toggled state
/// and its tap action, and those have to stay on the node the user activates.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    this.label,
    super.key,
  });

  final bool value;

  /// Null disables the switch, matching [m3.Switch].
  final m3.ValueChanged<bool>? onChanged;

  final String? label;

  @override
  Widget build(BuildContext context) {
    final toggle = m3.Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: m3.MaterialTapTargetSize.shrinkWrap,
    );

    final label = this.label;
    if (label == null) return toggle;
    return m3.MergeSemantics(
      child: m3.Semantics(label: label, child: toggle),
    );
  }
}
