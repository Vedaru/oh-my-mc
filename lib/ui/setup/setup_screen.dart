import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import 'java_panel.dart';

/// The setup screen.
///
/// Only what the launcher can actually manage today: the Java runtimes it
/// downloaded itself. A settings page that also listed toggles that do nothing
/// would be worse than a short one.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);

    return MotionEntrance(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(l10n.navSetup, style: theme.typography.title),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.resources.cardBackgroundFillColorSecondary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.resources.dividerStrokeColorDefault,
                ),
              ),
              child: const JavaRuntimeList(),
            ),
          ),
        ),
      ],
    );
  }
}
