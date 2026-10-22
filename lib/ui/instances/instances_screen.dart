import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../data/instance_providers.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import 'instance_card.dart';

/// The instance grid.
///
/// Entering items are staggered through [StaggerList], which caps the cascade so
/// a 200-instance grid does not take twelve seconds to appear. The cap is in
/// `StaggerConfig`, not here, so the budget is one number for the whole app.
class InstancesScreen extends ConsumerWidget {
  const InstancesScreen({this.onLaunch, this.onOpen, super.key});

  /// Launches an instance instead of the real launch controller. Only tests
  /// pass this: production wants the launch screen to show the session, so the
  /// default path starts the launch *and* navigates there.
  final void Function(Instance instance)? onLaunch;

  /// Opens the detail page. Overridden by tests that have no router.
  final void Function(Instance instance)? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(instanceListProvider);
    final notifier = ref.read(instanceListProvider.notifier);
    final session = ref.watch(launchControllerProvider);

    return switch (state) {
      InstanceListLoading() => const Center(child: ProgressRing()),
      InstanceListFailed(:final message) => _Failure(message: message),
      InstanceListReady(:final instances, :final selectedId, :final skipped) =>
        _Grid(
          instances: instances,
          selectedId: selectedId,
          skipped: skipped,
          session: session,
          onSelect: notifier.select,
          onLaunch: (instance) => _launch(context, ref, instance),
          onOpen: (instance) => (onOpen ?? _defaultOpen(context))(instance),
          onCreate: () => _createInstance(context, ref),
          onDelete: (instance) => _delete(context, ref, instance),
        ),
    };
  }

  /// Starts [instance] and goes to the launch screen.
  ///
  /// Navigating *before* the launch completes is deliberate: the log and the
  /// stop button are there, and staying on the grid would show a spinner on a
  /// card while the interesting output is on another page.
  Future<void> _launch(
    BuildContext context,
    WidgetRef ref,
    Instance instance,
  ) async {
    final override = onLaunch;
    if (override != null) return override(instance);
    final controller = ref.read(launchControllerProvider.notifier);
    await ref.read(instanceListProvider.notifier).select(instance.id);
    if (!context.mounted) return;
    context.go(Routes.launch);
    await controller.launch(instance);
  }

  void Function(Instance) _defaultOpen(BuildContext context) =>
      (instance) => context.go(Routes.instanceDetail(instance.id));

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Instance instance,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(l10n.instanceDelete),
        content: Text(l10n.instanceDeleteConfirmFiles(instance.displayName)),
        actions: [
          Button(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const ValueKey('instance-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.instanceDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(instanceListProvider.notifier)
        .remove(instance.id, deleteFiles: true);
  }

  /// Creating an instance is a name and a version. Deliberately a dialog rather
  /// than a wizard: the download screen already owns version choice, so the
  /// common flow is "pick a version there, then name it".
  Future<void> _createInstance(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewInstanceDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(instanceListProvider.notifier)
        .create(name: name, versionId: '1.20.1');
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.instances,
    required this.selectedId,
    required this.skipped,
    required this.session,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    required this.onOpen,
    required this.onLaunch,
  });

  final List<Instance> instances;
  final String? selectedId;
  final int skipped;
  final LaunchSession session;
  final void Function(String? id) onSelect;
  final void Function(Instance instance) onLaunch;
  final void Function(Instance instance) onOpen;
  final Future<void> Function(Instance instance) onDelete;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);

    if (instances.isEmpty) {
      return _Empty(onCreate: onCreate);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (skipped > 0) _SkippedBanner(count: skipped),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(l10n.navInstances, style: theme.typography.title),
              const SizedBox(width: 8),
              Text(
                l10n.instanceCount(instances.length),
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onCreate,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(ShellIcons.add, size: 14),
                    const SizedBox(width: 6),
                    Text(l10n.instanceCreate),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A fixed column count would waste space on a wide window and
              // squash cards on a narrow one. 280 logical pixels is the width at
              // which a card's name, version and play button still fit on one
              // line.
              const targetWidth = 280.0;
              final columns = (constraints.maxWidth / targetWidth)
                  .floor()
                  .clamp(1, 6);

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 128,
                ),
                itemCount: instances.length,
                itemBuilder: (context, index) {
                  final instance = instances[index];
                  final busy = session.isBusy;
                  return StaggerItem(
                    index: index,
                    itemCount: instances.length,
                    child: InstanceCard(
                      instance: instance,
                      selected: instance.id == selectedId,
                      // Tapping selects *and* opens: selection alone is
                      // invisible feedback on a screen with no other action, and
                      // the launch screen is reachable from the play button.
                      onTap: () => onOpen(instance),
                      // Every play button is disabled while any instance runs:
                      // a second JVM would fight over the same files.
                      onPlay: busy ? null : () => onLaunch(instance),
                      busy: busy && session.instanceId == instance.id,
                      // Delete lives behind an explicit menu rather than on the
                      // card: a destructive action next to a play button gets
                      // clicked by accident.
                      onMenu: () => _showMenu(context, instance),
                      key: ValueKey(instance.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

extension on _Grid {
  /// The per-card context menu, anchored on the card that was right-clicked.
  ///
  /// A menu rather than a dialog because a grid can hold several instances and
  /// the menu is the only thing that says *which* one is about to be deleted.
  Future<void> _showMenu(BuildContext context, Instance instance) async {
    final l10n = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box == null
        ? Offset.zero
        : box.localToGlobal(Offset.zero, ancestor: overlay);

    // A fresh controller per opening: one kept in the state would stay attached
    // to a card that the grid may have already disposed.
    final controller = FlyoutController();
    await controller.showFlyout<void>(
      position: origin,
      placementMode: FlyoutPlacementMode.bottomLeft,
      builder: (context) => MenuFlyout(
        items: [
          MenuFlyoutItem(
            text: Text(l10n.instanceOpen),
            leading: const Icon(ShellIcons.edit, size: 14),
            onPressed: () => onOpen(instance),
          ),
          MenuFlyoutItem(
            text: Text(l10n.playButton),
            leading: const Icon(ShellIcons.play, size: 14),
            onPressed: session.isBusy ? null : () => onLaunch(instance),
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            text: Text(l10n.instanceDelete),
            leading: const Icon(ShellIcons.trash, size: 14),
            onPressed: () => onDelete(instance),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}

class _SkippedBanner extends StatelessWidget {
  const _SkippedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.resources.systemFillColorCautionBackground,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            ShellIcons.warning,
            size: 16,
            color: theme.resources.systemFillColorCaution,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.instancesSkipped(count))),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ShellIcons.instance, size: 48, color: theme.inactiveColor),
          const SizedBox(height: 12),
          Text(l10n.instancesEmpty, style: theme.typography.body),
          const SizedBox(height: 16),
          FilledButton(onPressed: onCreate, child: Text(l10n.instanceCreate)),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ShellIcons.error,
            size: 32,
            color: theme.resources.systemFillColorCritical,
          ),
          const SizedBox(height: 8),
          // The raw error, not a localized "something went wrong": this is a bug
          // report, and a generic message would make it unactionable.
          SelectableText(message, style: theme.typography.caption),
        ],
      ),
    );
  }
}

class _NewInstanceDialog extends StatefulWidget {
  const _NewInstanceDialog();

  @override
  State<_NewInstanceDialog> createState() => _NewInstanceDialogState();
}

class _NewInstanceDialogState extends State<_NewInstanceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ContentDialog(
      title: Text(l10n.instanceCreate),
      content: TextBox(
        controller: _controller,
        autofocus: true,
        placeholder: l10n.instanceNameHint,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          // An empty name is not an error worth a message: the create button is
          // simply unavailable until there is something to name.
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.instanceCreate),
        ),
      ],
    );
  }
}
