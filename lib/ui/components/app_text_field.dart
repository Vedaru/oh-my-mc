import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// A single-line or multi-line text input with Material's outlined shape.
///
/// Exists for the same reason as `AppButton`: a screen should not have to know
/// which text field class the design system names this week. It also owns the
/// two translation decisions the expressive field forced on every call site -
/// `placeholder` and `leading` - so those do not need repeating six times.
class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.leading,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final m3.TextEditingController? controller;
  final m3.FocusNode? focusNode;

  /// A floating label. Omit it for a search-style field that only needs a hint.
  final String? label;

  /// Placeholder text, shown while the field is empty.
  final String? hint;

  final Widget? leading;
  final int maxLines;
  final bool autofocus;
  final m3.ValueChanged<String>? onChanged;
  final m3.ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return m3.TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      // A hint without a label would otherwise be read as a label by Material,
      // which floats it and leaves the field looking permanently filled.
      decoration: m3.InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: leading,
        isDense: true,
        border: const m3.OutlineInputBorder(),
      ),
    );
  }
}
