import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';

/// What a page shows when it has nothing to list yet.
///
/// An empty list used to be one grey sentence floating at the top of the pane, which
/// reads as a page that failed to load. This is the M3 empty pattern instead: a quiet
/// mark, the same sentence, and - when the page has one - the action that fixes it.
///
/// The mark is a `surfaceContainerLow` disc with no shadow: on a dark theme it is the
/// tone step that makes it read as a container, not a shadow.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.message,
    this.hint,
    this.action,
    super.key,
  });

  final m3.IconData icon;

  /// What is missing, in one sentence.
  final String message;

  /// Why, or what would put something here.
  final String? hint;

  /// The action that fixes the emptiness (install, add, import). Null when the page
  /// already offers that action in its header.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final hint = this.hint;
    final action = this.action;

    return m3.Center(
      child: m3.Padding(
        padding: const m3.EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: m3.Column(
          mainAxisSize: m3.MainAxisSize.min,
          children: [
            m3.Container(
              width: 56,
              height: 56,
              decoration: m3.BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: m3.BoxShape.circle,
              ),
              child: m3.Icon(icon, size: 24, color: scheme.onSurfaceVariant),
            ),
            const m3.SizedBox(height: 14),
            m3.Text(
              message,
              textAlign: m3.TextAlign.center,
              style: AppTheme.label(context).copyWith(color: scheme.onSurface),
            ),
            if (hint != null) ...[
              const m3.SizedBox(height: 4),
              m3.ConstrainedBox(
                constraints: const m3.BoxConstraints(maxWidth: 360),
                child: m3.Text(
                  hint,
                  textAlign: m3.TextAlign.center,
                  style: AppTheme.caption(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            if (action != null) ...[const m3.SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}
