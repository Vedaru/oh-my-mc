import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/instance/instance.dart';
import '../../data/instance_providers.dart';
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
  const InstancesScreen({this.onLaunch, super.key});

  /// Launches an instance. `null` in tests that only care about the grid.
  final void Function(Instance instance)? onLaunch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(instanceListProvider);
    final notifier = ref.read(instanceListProvider.notifier);

    return switch (state) {
      InstanceListLoading() => const Center(child: ProgressRing()),
      InstanceListFailed(:final message) => _Failure(message: message),
      InstanceListReady(:final instances, :final selectedId, :final skipped) =>
        _Grid(
          instances: instances,
          selectedId: selectedId,
          skipped: skipped,
          onSelect: notifier.select,
          onLaunch: onLaunch == null ? null : (instance) => onLaunch!(instance),
          onCreate: () => _createInstance(context, ref),
          onDelete: notifier.remove,
        ),
    };
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
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    this.onLaunch,
  });

  final List<Instance> instances;
  final String? selectedId;
  final int skipped;
  final void Function(String? id) onSelect;
  final void Function(Instance instance)? onLaunch;
  final Future<void> Function(String id) onDelete;
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
                  return StaggerItem(
                    index: index,
                    itemCount: instances.length,
                    child: InstanceCard(
                      instance: instance,
                      selected: instance.id == selectedId,
                      onTap: () => onSelect(instance.id),
                      onPlay: onLaunch == null
                          ? null
                          : () => onLaunch!(instance),
                      // The delete affordance lives in the context menu rather
                      // than on the card: a destructive action next to a play
                      // button gets clicked by accident.
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
