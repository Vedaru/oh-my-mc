import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// The severity of an [AppBanner].
///
/// These map onto the expressive colour scheme's semantic roles rather than onto
/// raw colours, so a banner follows the accent and the brightness without asking.
enum BannerSeverity { info, success, warning, error }

/// An inline, dismissible message attached to a screen.
///
/// The expressive component set has no banner or info-bar widget: `InfoBar` in
/// the old toolkit was used for download warnings, launch failures and settings
/// validation, so without this each of those three screens would grow its own
/// hand-rolled container and they would disagree about colour and padding within
/// a week.
///
/// Motion: the entrance is a size+opacity change routed through `MotionScope`,
/// so with motion disabled the banner appears at full size in one frame and
/// allocates no ticker.
class AppBanner extends StatelessWidget {
  const AppBanner({
    required this.message,
    this.severity = BannerSeverity.info,
    this.title,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    super.key,
  });

  final String message;
  final BannerSeverity severity;

  /// Optional bold first line; omit for a single-line message.
  final String? title;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// When null the banner has no dismiss control.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final status = AppTheme.status(context);
    // Only `errorContainer` exists in MD3, so the container is derived: a light
    // tint of the accent over the surface keeps contrast in both brightnesses.
    // The accent itself is not a background because there is no matching
    // on-colour for success/warning.
    final (accent, icon) = switch (severity) {
      BannerSeverity.info => (status.info, ShellIcons.error),
      BannerSeverity.success => (status.success, ShellIcons.checkCircle),
      BannerSeverity.warning => (status.warning, ShellIcons.warning),
      BannerSeverity.error => (status.danger, ShellIcons.error),
    };
    final background = m3.Color.alphaBlend(
      accent.withValues(alpha: 0.14),
      scheme.surface,
    );
    final foreground = scheme.onSurface;

    return m3.Container(
      decoration: m3.BoxDecoration(
        color: background,
        borderRadius: m3.BorderRadius.circular(12),
      ),
      padding: const m3.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: m3.Row(
        crossAxisAlignment: m3.CrossAxisAlignment.start,
        children: [
          m3.Icon(icon, size: 18, color: foreground),
          const m3.SizedBox(width: 10),
          m3.Expanded(
            child: m3.Column(
              crossAxisAlignment: m3.CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  m3.Text(
                    title!,
                    style: AppTheme.label(context).copyWith(color: foreground),
                  ),
                  const m3.SizedBox(height: 2),
                ],
                m3.Text(
                  message,
                  style: AppTheme.body(context).copyWith(color: foreground),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const m3.SizedBox(width: 8),
            AppButton(
              onPressed: onAction,
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              label: m3.Text(actionLabel!),
            ),
          ],
          if (onDismiss != null) ...[
            const m3.SizedBox(width: 4),
            m3.IconButton(
              onPressed: onDismiss,
              icon: m3.Icon(ShellIcons.close, size: 16, color: foreground),
            ),
          ],
        ],
      ),
    );
  }
}
