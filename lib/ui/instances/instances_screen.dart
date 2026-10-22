import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../data/install_providers.dart';
import '../../data/instance_providers.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_banner.dart';
import '../components/page_body.dart';
import '../components/skeleton_block.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'instance_card.dart';
import '../components/app_text_field.dart';
import '../components/app_dialog.dart';

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

    return PageBody(
      maxWidth: 1200,
      scrollable: false,
      child: switch (state) {
        // A grid-shaped skeleton rather than a centred spinner: the shape is
        // known, so the placeholder can occupy the space the cards will
        // (PLAN-M11 §3.1).
        InstanceListLoading() => const _GridSkeleton(),
        InstanceListFailed(:final message) => _Failure(message: message),
        InstanceListReady(
          :final instances,
          :final selectedId,
          :final skipped,
        ) =>
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
      },
    );
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
    final confirmed = await m3.showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.instanceDelete,
        content: m3.Text(l10n.instanceDeleteConfirmFiles(instance.displayName)),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.pop(context, false),
            style: AppButtonStyle.text,
            label: m3.Text(l10n.actionCancel),
          ),
          AppButton(
            key: const m3.ValueKey('instance-delete-confirm'),
            onPressed: () => m3.Navigator.pop(context, true),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.instanceDelete),
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
    final l10n = context.l10n;
    final versions = versionsForPicker(ref.read(installedVersionsProvider));

    // PCL's flow cannot start without a version: there is nothing to launch. Say
    // so and point at the download page instead of creating an instance bound to
    // a version that is not on disk (which is what a hardcoded `1.20.1` did).
    if (versions.isEmpty) {
      await m3.showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: l10n.instanceNoVersions,
          content: m3.Text(l10n.instanceNoVersionsHint),
          actions: [
            AppButton(
              onPressed: () => m3.Navigator.pop(context),
              style: AppButtonStyle.text,
              label: m3.Text(l10n.actionCancel),
            ),
            AppButton(
              key: const m3.ValueKey('instance-create-download'),
              onPressed: () {
                m3.Navigator.pop(context);
                context.go(Routes.download);
              },
              style: AppButtonStyle.filled,
              label: m3.Text(l10n.navDownload),
            ),
          ],
        ),
      );
      return;
    }

    final result = await m3.showDialog<NewInstanceRequest>(
      context: context,
      builder: (context) => _NewInstanceDialog(versions: versions),
    );
    if (result == null) return;
    await ref
        .read(instanceListProvider.notifier)
        .create(name: result.name, versionId: result.versionId);
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
    final scheme = m3.Theme.of(context).colorScheme;

    if (instances.isEmpty) {
      return _Empty(onCreate: onCreate);
    }

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        if (skipped > 0) _SkippedBanner(count: skipped),
        PageTitle(
          l10n.navInstances,
          trailing: m3.Row(
            mainAxisSize: m3.MainAxisSize.min,
            children: [
              m3.Text(
                l10n.instanceCount(instances.length),
                style: AppTheme.caption(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              const m3.SizedBox(width: 12),
              AppButton(
                onPressed: onCreate,
                style: AppButtonStyle.filled,
                icon: const m3.Icon(ShellIcons.add, size: 15),
                label: m3.Text(l10n.instanceCreate),
              ),
            ],
          ),
        ),
        m3.Expanded(
          child: m3.LayoutBuilder(
            builder: (context, constraints) {
              // A fixed column count would waste space on a wide window and
              // squash cards on a narrow one. 280 logical pixels is the width at
              // which a card's name, version and play button still fit on one
              // line.
              const targetWidth = 280.0;
              final columns = (constraints.maxWidth / targetWidth)
                  .floor()
                  .clamp(1, 6);

              return m3.GridView.builder(
                padding: m3.EdgeInsets.zero,
                gridDelegate: m3.SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  // Tall enough for the card's tallest content at larger text
                  // scales; a tighter box clips the playtime row.
                  mainAxisExtent: 148,
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
                      key: m3.ValueKey(instance.id),
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
    final box = context.findRenderObject() as m3.RenderBox?;
    final overlay =
        m3.Overlay.of(context).context.findRenderObject()! as m3.RenderBox;
    final origin = box == null
        ? m3.Offset.zero
        : box.localToGlobal(m3.Offset.zero, ancestor: overlay);

    final selected = await m3.showMenu<int>(
      context: context,
      // `showMenu` wants the anchor in the overlay's coordinate space, which is
      // what `fromRect` expresses: a zero-size rect at the card's origin.
      position: m3.RelativeRect.fromRect(
        origin & m3.Size.zero,
        overlay.paintBounds,
      ),
      items: [
        m3.PopupMenuItem(
          value: 0,
          child: m3.Row(
            children: [
              const m3.Icon(ShellIcons.edit, size: 14),
              const m3.SizedBox(width: 10),
              m3.Text(l10n.instanceOpen),
            ],
          ),
        ),
        m3.PopupMenuItem(
          value: 1,
          enabled: !session.isBusy,
          child: m3.Row(
            children: [
              const m3.Icon(ShellIcons.play, size: 14),
              const m3.SizedBox(width: 10),
              m3.Text(l10n.playButton),
            ],
          ),
        ),
        const m3.PopupMenuDivider(),
        m3.PopupMenuItem(
          value: 2,
          child: m3.Row(
            children: [
              const m3.Icon(ShellIcons.trash, size: 14),
              const m3.SizedBox(width: 10),
              m3.Text(l10n.instanceDelete),
            ],
          ),
        ),
      ],
    );

    switch (selected) {
      case 0:
        onOpen(instance);
      case 1:
        onLaunch(instance);
      case 2:
        await onDelete(instance);
    }
  }
}

class _SkippedBanner extends StatelessWidget {
  const _SkippedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return m3.Padding(
      padding: const m3.EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppBanner(
        severity: BannerSeverity.warning,
        message: l10n.instancesSkipped(count),
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
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Center(
      child: m3.Column(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          m3.Icon(
            ShellIcons.instance,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const m3.SizedBox(height: 12),
          m3.Text(l10n.instancesEmpty, style: AppTheme.body(context)),
          const m3.SizedBox(height: 16),
          AppButton(
            onPressed: onCreate,
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.instanceCreate),
          ),
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
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Center(
      child: m3.Column(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          m3.Icon(ShellIcons.error, size: 32, color: scheme.error),
          const m3.SizedBox(height: 8),
          // The raw error, not a localized "something went wrong": this is a bug
          // report, and a generic message would make it unactionable.
          m3.SelectableText(message, style: AppTheme.caption(context)),
        ],
      ),
    );
  }
}

/// What the create dialog collects.
typedef NewInstanceRequest = ({String name, String versionId});

/// Installed versions, newest-looking first.
///
/// There is no release date on disk without opening every version JSON, so this is
/// a string sort with the numeric parts compared as numbers: `26.3` before
/// `1.20.1`, `1.20.1` before `1.20`. The picker only has to be predictable, and the
/// version the user just installed has to be near the top.
List<String> versionsForPicker(Set<String> installed) {
  final sorted = installed.toList()..sort((a, b) => _compareVersions(b, a));
  return sorted;
}

/// Compares two Minecraft version ids, numerically where both sides are numbers.
int _compareVersions(String a, String b) {
  final left = a.split(RegExp(r'[.-]'));
  final right = b.split(RegExp(r'[.-]'));
  for (var i = 0; i < left.length && i < right.length; i++) {
    final l = int.tryParse(left[i]);
    final r = int.tryParse(right[i]);
    final result = (l != null && r != null)
        ? l.compareTo(r)
        : left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}

/// Name plus version, which is what PCL asks for when a user adds a version.
///
/// The version list is the *installed* versions, not the full manifest: an
/// instance pointing at a version that is not on disk cannot launch, so the dialog
/// only offers what exists (and the caller sends the user to /download when the
/// list is empty).
class _NewInstanceDialog extends StatefulWidget {
  const _NewInstanceDialog({required this.versions});

  final List<String> versions;

  @override
  State<_NewInstanceDialog> createState() => _NewInstanceDialogState();
}

class _NewInstanceDialogState extends State<_NewInstanceDialog> {
  final _controller = m3.TextEditingController();
  late String _version = widget.versions.first;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    m3.Navigator.of(context).pop((name: name, versionId: _version));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canCreate = _controller.text.trim().isNotEmpty;

    return AppDialog(
      title: l10n.instanceCreate,
      content: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          AppTextField(
            key: const m3.ValueKey('instance-name'),
            controller: _controller,
            autofocus: true,
            hint: l10n.instanceNameHint,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const m3.SizedBox(height: 16),
          m3.DropdownMenu<String>(
            key: const m3.ValueKey('instance-version'),
            initialSelection: _version,
            expandedInsets: m3.EdgeInsets.zero,
            label: m3.Text(l10n.instanceVersionLabel),
            dropdownMenuEntries: [
              for (final version in widget.versions)
                m3.DropdownMenuEntry<String>(value: version, label: version),
            ],
            onSelected: (value) {
              if (value == null) return;
              setState(() => _version = value);
            },
          ),
        ],
      ),
      actions: [
        AppButton(
          onPressed: () => m3.Navigator.of(context).pop(),
          style: AppButtonStyle.text,
          label: m3.Text(l10n.actionCancel),
        ),
        AppButton(
          key: const m3.ValueKey('instance-create-confirm'),
          // An empty name is not an error worth a message: the create button is
          // simply unavailable until there is something to name.
          onPressed: canCreate ? _submit : null,
          style: AppButtonStyle.filled,
          label: m3.Text(l10n.instanceCreate),
        ),
      ],
    );
  }
}

/// The instance grid's loading state.
///
/// Same `mainAxisExtent: 148`, same column arithmetic and same spacing as the
/// real grid, so the cards land exactly where the skeletons stood instead of the
/// whole page reflowing when the list arrives (PLAN-M11 §3.1).
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  static const _cards = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;

    return m3.LayoutBuilder(
      builder: (context, constraints) {
        // Kept identical to _Grid's arithmetic: a skeleton that picks its own
        // column count would be a second layout to maintain, and would not
        // promise the layout that is actually coming.
        const targetWidth = 280.0;
        final columns = (constraints.maxWidth / targetWidth).floor().clamp(
          1,
          6,
        );

        return Skeleton(
          child: m3.GridView.builder(
            padding: const m3.EdgeInsets.all(16),
            physics: const m3.NeverScrollableScrollPhysics(),
            gridDelegate: m3.SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 148,
            ),
            itemCount: _cards,
            itemBuilder: (context, index) => m3.Container(
              padding: const m3.EdgeInsets.all(14),
              decoration: m3.BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: m3.BorderRadius.circular(14),
              ),
              child: const m3.Column(
                crossAxisAlignment: m3.CrossAxisAlignment.start,
                children: [
                  m3.Row(
                    children: [
                      SkeletonBlock(width: 22, height: 22, radius: 6),
                      m3.SizedBox(width: 10),
                      m3.Expanded(child: SkeletonBlock(height: 12)),
                    ],
                  ),
                  m3.SizedBox(height: 10),
                  SkeletonBlock(width: 96, height: 10),
                  m3.Spacer(),
                  m3.Row(
                    children: [
                      m3.Expanded(child: SkeletonBlock(height: 10)),
                      m3.SizedBox(width: 12),
                      SkeletonBlock(width: 40, height: 10),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
