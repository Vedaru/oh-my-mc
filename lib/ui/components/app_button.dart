import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';

/// Which Material button role a call site wants.
///
/// Named here rather than using `m3.*Button` types directly so a screen never
/// names a button class: the style decision lives in one file, and the next
/// restyle is a change to this file instead of to 36 call sites.
enum AppButtonStyle {
  /// The one primary action on a surface.
  filled,

  /// A secondary action that still needs a boundary.
  outlined,

  /// A tertiary action, or one of several in a row.
  text,
}

/// Height and padding for an [AppButton].
///
/// MD3's default button height is 40 px, which is what [sm] is, so the dense
/// launcher rows keep their existing rhythm. [lg] is MD3's large role (56 px)
/// rather than a reproduction of the expressive 96 px pill: MD3 has no 96 px
/// button, so keeping it would make the Play button the one control that is
/// visibly not Material.
enum AppButtonSize {
  /// 40 px - the launcher's default density.
  sm,

  /// 56 px - the hero action.
  lg,
}

/// A Material button whose label is always visible.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.style = AppButtonStyle.filled,
    this.size = AppButtonSize.sm,
    this.semanticLabel,
    this.tooltip,
    super.key,
  });

  final Widget label;

  /// Null disables the button, which is what a pending install relies on.
  final VoidCallback? onPressed;

  final Widget? icon;
  final AppButtonStyle style;
  final AppButtonSize size;

  /// A label for screen readers when [label] alone does not read well, e.g. an
  /// icon-only button.
  final String? semanticLabel;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final style = _buttonStyle(context);
    final content = _content();
    final onPressed = this.onPressed;

    m3.Widget button = switch (this.style) {
      AppButtonStyle.filled => m3.FilledButton(
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      AppButtonStyle.outlined => m3.OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      AppButtonStyle.text => m3.TextButton(
        onPressed: onPressed,
        style: style,
        child: content,
      ),
    };

    final semanticLabel = this.semanticLabel;
    if (semanticLabel != null) {
      button = m3.Semantics(
        container: true,
        button: true,
        enabled: onPressed != null,
        label: semanticLabel,
        child: m3.ExcludeSemantics(child: button),
      );
    }

    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = m3.Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _content() {
    final icon = this.icon;
    // The label is left unstyled so it inherits the button's own text style,
    // which is where [_buttonStyle] applies the size's typography.
    if (icon == null) return label;
    return m3.Row(
      mainAxisSize: m3.MainAxisSize.min,
      children: [
        icon,
        const m3.SizedBox(width: 8),
        m3.Flexible(child: label),
      ],
    );
  }

  m3.ButtonStyle _buttonStyle(BuildContext context) {
    final (height, horizontalPadding) = switch (size) {
      AppButtonSize.sm => (40.0, 16.0),
      AppButtonSize.lg => (56.0, 24.0),
    };
    return m3.ButtonStyle(
      minimumSize: m3.WidgetStateProperty.all(m3.Size(64, height)),
      padding: m3.WidgetStateProperty.all(
        m3.EdgeInsets.symmetric(horizontal: horizontalPadding),
      ),
      textStyle: m3.WidgetStateProperty.all(AppTheme.label(context)),
    );
  }
}
