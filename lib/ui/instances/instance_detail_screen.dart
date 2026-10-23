import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../data/instance_cloner.dart';
import '../../core/instance/memory.dart';
import '../../data/instance_providers.dart';
import '../../data/launch_providers.dart';
import '../../data/pack_providers.dart';
import '../../data/java_providers.dart';
import '../../data/launch_factory.dart';
import '../../l10n/l10n.dart';
import '../components/app_banner.dart';
import '../components/list_row.dart';
import '../components/section_drawer.dart';
import '../components/section_page.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'args_field.dart';
import 'instance_content_page.dart';
import 'instance_card.dart';
import '../components/app_slider.dart';
import '../components/app_switch.dart';
import '../components/app_text_field.dart';
import '../components/app_dialog.dart';

/// One instance's settings.
///
/// Every field the launcher actually honours is here, and nothing else. The
/// instance is written back on each edit rather than on a "Save" button: a
/// settings page whose changes are lost when the window closes is a bug report,
/// and there is no multi-field invariant that would need a transaction.
class InstanceDetailScreen extends ConsumerStatefulWidget {
  const InstanceDetailScreen({
    required this.id,
    this.onClose,
    this.initialSection,
    super.key,
  });

  final String id;

  /// Opens the page on a section, for the `/instances/:id/mods` deep link.
  final String? initialSection;

  /// Leaves the page. Production replaces the route; tests pass a callback so
  /// the page can be asserted without a router.
  final VoidCallback? onClose;

  @override
  ConsumerState<InstanceDetailScreen> createState() =>
      _InstanceDetailScreenState();
}

/// The page's sections.
///
/// Same shape as Prism's instance window: one page per thing you can look at - the
/// version, the mods, the resource packs, the shaders, the worlds, the servers, the
/// data packs, the logs, the settings - because those lists behave differently and a
/// user looking for "my resource packs" should not have to find a filter first.
enum DetailSection {
  overview,
  mods,
  resourcePacks,
  shaderPacks,
  worlds,
  servers,
  dataPacks,
  settings,
}

class _InstanceDetailScreenState extends ConsumerState<InstanceDetailScreen> {
  late var _section = switch (widget.initialSection) {
    'mods' => DetailSection.mods,
    'resourcePacks' => DetailSection.resourcePacks,
    'shaderPacks' => DetailSection.shaderPacks,
    'worlds' => DetailSection.worlds,
    'servers' => DetailSection.servers,
    'dataPacks' => DetailSection.dataPacks,
    _ => DetailSection.overview,
  };

  /// Leaves the page.
  ///
  /// `pop` when the page was pushed (the normal path from a card), because the
  /// card has to still be mounted for the icon to fly back to it; `go` would
  /// rebuild the stack and the return flight would be a cut. The fallback keeps
  /// a deep link - which has no page under it - landing on the grid rather than
  /// on an empty navigator.
  void _close(BuildContext context) {
    final close = widget.onClose;
    if (close != null) {
      close();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.instances);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(instanceListProvider);

    return switch (state) {
      InstanceListLoading() => const m3.Center(
        child: m3.CircularProgressIndicator(),
      ),
      InstanceListFailed(:final message) => m3.Center(
        child: m3.SelectableText(message),
      ),
      InstanceListReady(:final instances) => _body(context, instances),
    };
  }

  Widget _body(BuildContext context, List<Instance> instances) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    Instance? instance;
    for (final candidate in instances) {
      if (candidate.id == widget.id) instance = candidate;
    }

    // A stale link (the instance was deleted in another window) is not a crash:
    // say so and offer the way back.
    if (instance == null) {
      return m3.Center(
        child: m3.Column(
          mainAxisSize: m3.MainAxisSize.min,
          children: [
            m3.Icon(
              ShellIcons.warning,
              size: 28,
              color: scheme.onSurfaceVariant,
            ),
            const m3.SizedBox(height: 8),
            m3.Text(l10n.instanceMissing, style: AppTheme.body(context)),
            const m3.SizedBox(height: 12),
            AppButton(
              onPressed: () => _close(context),
              style: AppButtonStyle.filled,
              label: m3.Text(l10n.actionBack),
            ),
          ],
        ),
      );
    }

    return SectionPage(
      // The heading is the instance itself: back, icon, name, and the loader/version
      // as a subtitle. Play is the page's one filled action, and clone / export /
      // delete stay in the menu.
      mark: m3.Hero(
        tag: instanceHeroTag(instance.id),
        child: m3.Icon(
          instance.loader.isModded ? ShellIcons.addon : ShellIcons.instance,
          size: 22,
          color: scheme.primary,
        ),
      ),
      title: instance.displayName,
      onBack: () => _close(context),
      backLabel: l10n.navInstances,
      subtitle: [
        instance.versionId,
        if (instance.loader.isModded) instance.loader.label,
      ].join(' · '),
      actions: m3.Row(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          AppButton(
            key: const m3.ValueKey('instance-play'),
            onPressed: () =>
                ref.read(launchControllerProvider.notifier).launch(instance!),
            style: AppButtonStyle.filled,
            icon: const m3.Icon(ShellIcons.play, size: 14),
            label: m3.Text(l10n.actionLaunch),
          ),
          const m3.SizedBox(width: 8),
          m3.PopupMenuButton<String>(
            key: const m3.ValueKey('instance-more'),
            tooltip: l10n.actionMore,
            onSelected: (choice) => switch (choice) {
              'clone' => _clone(context, ref, instance!),
              'export' => _exportPack(context, ref, instance!),
              'delete' => _delete(context, ref, instance!),
              _ => null,
            },
            itemBuilder: (context) => [
              m3.PopupMenuItem(
                value: 'clone',
                child: m3.Text(l10n.instanceClone),
              ),
              m3.PopupMenuItem(
                value: 'export',
                child: m3.Text(l10n.packExport),
              ),
              const m3.PopupMenuDivider(),
              m3.PopupMenuItem(
                value: 'delete',
                child: m3.Text(l10n.instanceDelete),
              ),
            ],
            child: const m3.Padding(
              padding: m3.EdgeInsets.all(8),
              child: m3.Icon(ShellIcons.more, size: 18),
            ),
          ),
        ],
      ),
      selectedIndex: _section.index,
      onSelected: (index) =>
          setState(() => _section = DetailSection.values[index]),
      destinations: [
        for (final section in DetailSection.values) _destination(l10n, section),
      ],
      // 概览 and 设置 are forms; the content sections are lists that fill the pane.
      bodyScrollable: _isFormSection,
      body: m3.KeyedSubtree(
        key: m3.ValueKey('detail-${_section.name}'),
        child: _sectionBody(context, instance),
      ),
    );
  }

  /// Whether the selected section is a form (scrolls) or a list (fills the pane).
  ///
  /// A list inside a scroll view gets unbounded height, and its own `Expanded` list
  /// cannot be laid out in one.
  bool get _isFormSection =>
      _section == DetailSection.overview || _section == DetailSection.settings;

  SectionDestination _destination(
    AppLocalizations l10n,
    DetailSection section,
  ) => switch (section) {
    DetailSection.overview => SectionDestination(
      key: 'detail-section-overview',
      label: l10n.detailTabOverview,
      icon: ShellIcons.info,
    ),
    DetailSection.mods => SectionDestination(
      key: 'detail-section-mods',
      label: l10n.catalogMods,
      icon: ShellIcons.mods,
    ),
    DetailSection.resourcePacks => SectionDestination(
      key: 'detail-section-resource-packs',
      label: l10n.catalogResourcePacks,
      icon: ShellIcons.resourcePacks,
    ),
    DetailSection.shaderPacks => SectionDestination(
      key: 'detail-section-shader-packs',
      label: l10n.catalogShaders,
      icon: ShellIcons.shaderPacks,
    ),
    DetailSection.worlds => SectionDestination(
      key: 'detail-section-worlds',
      label: l10n.contentSaves,
      icon: ShellIcons.saves,
    ),
    DetailSection.servers => SectionDestination(
      key: 'detail-section-servers',
      label: l10n.contentServers,
      icon: ShellIcons.network,
    ),
    DetailSection.dataPacks => SectionDestination(
      key: 'detail-section-data-packs',
      label: l10n.catalogDataPacks,
      icon: ShellIcons.addon,
    ),
    DetailSection.settings => SectionDestination(
      key: 'detail-section-settings',
      label: l10n.detailTabSettings,
      icon: ShellIcons.settings,
    ),
  };

  /// The body of the selected section.
  Widget _sectionBody(BuildContext context, Instance instance) =>
      switch (_section) {
        DetailSection.overview => _overview(context, instance),
        DetailSection.mods => InstanceContentPage(
          instance: instance,
          kind: InstanceContentKind.mods,
        ),
        DetailSection.resourcePacks => InstanceContentPage(
          instance: instance,
          kind: InstanceContentKind.resourcePacks,
        ),
        DetailSection.shaderPacks => InstanceContentPage(
          instance: instance,
          kind: InstanceContentKind.shaderPacks,
        ),
        DetailSection.worlds => InstanceContentPage(
          instance: instance,
          kind: InstanceContentKind.worlds,
        ),
        DetailSection.servers => InstanceContentPage(
          instance: instance,
          kind: InstanceContentKind.servers,
        ),
        DetailSection.dataPacks => InstanceContentPage(
          instance: instance,
          kind: InstanceContentKind.dataPacks,
        ),
        DetailSection.settings => _settings(context, instance),
      };

  /// 概览: what this instance *is*, and the state worth knowing before playing.
  Widget _overview(BuildContext context, Instance instance) {
    final l10n = context.l10n;
    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: l10n.instanceSectionGeneral,
          children: [
            _ReadOnlyRow(
              label: l10n.instanceVersionLabel,
              value: [
                instance.versionId,
                if (instance.loader.isModded)
                  '${instance.loader.name} ${instance.loaderVersion ?? ''}'
                      .trim(),
              ].join('  ·  '),
            ),
            _ReadOnlyRow(
              label: l10n.instanceMemoryLabel,
              value: instance.memoryMb == null
                  ? l10n.instanceMemoryUsingDefault(
                      ref.watch(appSettingsMemoryProvider),
                    )
                  : l10n.instanceMemoryMb(instance.memoryMb!),
            ),
            _ReadOnlyRow(
              label: l10n.instanceIsolationLabel,
              value: instance.isolation == IsolationKind.isolated
                  ? l10n.instanceIsolationOn
                  : l10n.instanceIsolationOff,
            ),
            ListRow(
              leadingIcon: ShellIcons.clock,
              label: l10n.instancePlaytimeLabel,
              trailingText: _playtimeLine(l10n, instance),
            ),
          ],
        ),
      ],
    );
  }

  /// 设置: the fields that change how it runs.
  Widget _settings(BuildContext context, Instance instance) {
    final l10n = context.l10n;
    final notifier = ref.read(instanceListProvider.notifier);
    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: l10n.instanceSectionGeneral,
          children: [
            _NameRow(
              instance: instance,
              onChanged: (name) =>
                  notifier.update(instance.copyWith(name: name)),
            ),
            _IsolationRow(
              instance: instance,
              onChanged: (isolation) =>
                  notifier.update(instance.copyWith(isolation: isolation)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: l10n.instanceSectionRuntime,
          children: [
            _MemoryRow(
              instance: instance,
              onChanged: (memoryMb) => notifier.update(
                instance.copyWith(
                  memoryMb: memoryMb,
                  clearMemoryMb: memoryMb == null,
                ),
              ),
            ),
            _JavaRow(
              instance: instance,
              onChanged: (path) => notifier.update(
                instance.copyWith(javaPath: path, clearJavaPath: path == null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: l10n.instanceSectionWindow,
          children: [
            _WindowRow(
              instance: instance,
              onSize: (width, height) => notifier.update(
                instance.copyWith(
                  windowWidth: width,
                  windowHeight: height,
                  clearWindowSize: width == null && height == null,
                ),
              ),
              onFullscreen: (value) =>
                  notifier.update(instance.copyWith(fullscreen: value)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: l10n.instanceSectionArguments,
          children: [
            ArgsField(
              fieldKey: const ValueKey('instance-jvm-args'),
              label: l10n.instanceJvmArgsLabel,
              hint: l10n.instanceJvmArgsHint,
              value: instance.jvmArgs,
              onChanged: (args) =>
                  notifier.update(instance.copyWith(jvmArgs: args)),
            ),
            ArgsField(
              fieldKey: const ValueKey('instance-game-args'),
              label: l10n.instanceGameArgsLabel,
              hint: l10n.instanceGameArgsHint,
              value: instance.gameArgs,
              onChanged: (args) =>
                  notifier.update(instance.copyWith(gameArgs: args)),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the directory in the OS file manager.
  ///
  /// The directory is created first: for a never-launched instance it does not
  /// exist yet, and "open folder" silently doing nothing is worse than making an
  /// empty one.
  /// 复制实例: a full copy of the game directory under a new instance.
  ///
  /// Large instances take a while (a modded world is a few GB), so the button stays
  /// busy and the result is reported: a copy that silently takes 20 seconds with no
  /// feedback reads as a broken button.
  Future<void> _clone(
    BuildContext context,
    WidgetRef ref,
    Instance instance,
  ) async {
    final l10n = context.l10n;
    final messenger = m3.ScaffoldMessenger.maybeOf(context);
    try {
      final created = await const InstanceCloner().clone(
        source: instance,
        instances: ref.read(instanceListProvider.notifier),
        paths: ref.read(launcherPathsProvider),
      );
      if (!context.mounted) return;
      await ref.read(instanceListProvider.notifier).select(created.id);
      if (!context.mounted) return;
      // The clone is now the selection, so the page has to follow it.
      context.go(Routes.instanceDetail(created.id));
    } on Object catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.instanceCloneFailed('$e')),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Writes the instance to a `.zip` the user chooses, then says where it went.
  ///
  /// The directory picker rather than a save dialog: a pack is hundreds of
  /// megabytes, and `saveFile` takes the bytes in memory.
  Future<void> _exportPack(
    BuildContext context,
    WidgetRef ref,
    Instance instance,
  ) async {
    final l10n = context.l10n;
    final messenger = m3.ScaffoldMessenger.maybeOf(context);
    final dir = await FilePicker.getDirectoryPath(dialogTitle: l10n.packExport);
    if (dir == null) return;

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final out = File(p.join(dir, '${instance.id}-$stamp.zip'));
    try {
      final count = await exportInstancePack(
        exporter: ref.read(packExporterProvider),
        instance: instance,
        paths: ref.read(launcherPathsProvider),
        out: out,
      );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.packExported(count, out.path)),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    } on Object catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.packExportFailed('$e')),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    }
  }

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
        // The prompt promises the folder goes, because it does: this is the one
        // destructive action in the app, and "delete" that leaves half a gigabyte
        // behind is how users end up with an unreadable data directory.
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

    final notifier = ref.read(instanceListProvider.notifier);
    final path = ref.read(launcherPathsProvider).instanceDir(instance.id).path;
    final deleted = await notifier.remove(instance.id, deleteFiles: true);
    if (!context.mounted) return;
    _close(context);
    if (deleted) return;

    // The list entry is already gone, so this is not a failed delete - it is a
    // leftover folder. Say where it is, so the user can finish the job.
    await m3.showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.instanceDelete,
        content: m3.SelectableText(l10n.instanceDeleteFilesFailed(path)),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.pop(context),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Container(
      padding: const m3.EdgeInsets.all(14),
      // A filled container, not an outlined one: M3 cards earn their grouping
      // from a tonal surface, and a hairline around every section draws a grid of
      // lines across the page that competes with the content.
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: m3.BorderRadius.circular(16),
      ),
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          m3.Text(title, style: AppTheme.label(context)),
          const m3.SizedBox(height: 10),
          for (final child in children) ...[
            child,
            const m3.SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Label on the left, control on the right, one line.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final hint = this.hint;
    return m3.Row(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.SizedBox(
          // 220 fits the longest label ("Separate game folder") on one line and lets
          // its hint wrap to two: at 180 the label itself wrapped, which made the row
          // taller than the control it describes.
          width: 220,
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            children: [
              m3.Padding(
                padding: const m3.EdgeInsets.only(top: 6),
                child: m3.Text(label, style: AppTheme.body(context)),
              ),
              if (hint != null)
                m3.Padding(
                  padding: const m3.EdgeInsets.only(top: 2),
                  child: m3.Text(
                    hint,
                    style: AppTheme.caption(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        m3.Expanded(child: child),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return _Row(
      label: label,
      child: m3.Padding(
        padding: const m3.EdgeInsets.only(top: 6),
        child: m3.SelectableText(
          value,
          style: AppTheme.body(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The name field. Writes on submit and on losing focus, not on every keystroke:
/// each keystroke would be a whole-file write.
class _NameRow extends StatefulWidget {
  const _NameRow({required this.instance, required this.onChanged});

  final Instance instance;
  final void Function(String name) onChanged;

  @override
  State<_NameRow> createState() => _NameRowState();
}

class _NameRowState extends State<_NameRow> {
  late final _controller = TextEditingController(text: widget.instance.name);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_commitOnBlur);
  }

  @override
  void dispose() {
    _focus.removeListener(_commitOnBlur);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commitOnBlur() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final name = _controller.text.trim();
    // A cleared name falls back to the version on the card, so there is nothing
    // to reject; an unchanged name is not a write.
    if (name == widget.instance.name) return;
    widget.onChanged(name);
  }

  @override
  Widget build(BuildContext context) {
    return _Row(
      label: context.l10n.instanceNameLabel,
      child: AppTextField(
        key: const m3.ValueKey('instance-name'),
        controller: _controller,
        focusNode: _focus,
        // The row's label already names this field: a floating label saying "Name"
        // again directly above it is the same word twice.
        hint: context.l10n.instanceNameHint,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _IsolationRow extends StatelessWidget {
  const _IsolationRow({required this.instance, required this.onChanged});

  final Instance instance;
  final void Function(IsolationKind kind) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isolated = instance.isolation == IsolationKind.isolated;
    return _Row(
      label: l10n.instanceIsolationLabel,
      hint: l10n.instanceIsolationHint,
      child: m3.Align(
        alignment: m3.AlignmentDirectional.centerStart,
        child: m3.Column(
          crossAxisAlignment: m3.CrossAxisAlignment.start,
          children: [
            m3.Row(
              children: [
                AppSwitch(
                  key: const m3.ValueKey('instance-isolation'),
                  value: isolated,
                  onChanged: (value) => onChanged(
                    value
                        ? IsolationKind.isolated
                        : IsolationKind.shareLibraries,
                  ),
                  label: l10n.instanceIsolationLabel,
                ),
                const m3.SizedBox(width: 10),
                m3.Text(
                  isolated
                      ? l10n.instanceIsolationOn
                      : l10n.instanceIsolationOff,
                  style: AppTheme.body(context),
                ),
              ],
            ),
            // Turning this on does not migrate anything: the instance simply
            // starts reading an empty directory. Saying so is the difference
            // between "where did my world go" and an informed choice.
            if (isolated)
              m3.Padding(
                padding: const m3.EdgeInsets.only(top: 8),
                child: AppBanner(
                  key: const m3.ValueKey('instance-isolation-empty'),
                  severity: BannerSeverity.warning,
                  message: l10n.instanceIsolationEmpty,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Memory override. `null` means "use the global default", which is a third
/// state the slider cannot express, so it is an explicit switch.
class _MemoryRow extends ConsumerWidget {
  const _MemoryRow({required this.instance, required this.onChanged});

  final Instance instance;
  final void Function(int? mb) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final global = ref.watch(appSettingsMemoryProvider);
    final value = instance.memoryMb;

    return _Row(
      label: l10n.instanceMemoryLabel,
      hint: l10n.instanceMemoryHint,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          m3.Row(
            children: [
              AppSwitch(
                key: const m3.ValueKey('instance-memory-override'),
                value: value != null,
                onChanged: (on) => onChanged(on ? global : null),
                label: l10n.instanceMemoryLabel,
              ),
              const m3.SizedBox(width: 10),
              m3.Text(
                value == null
                    ? l10n.instanceMemoryUsingDefault(global)
                    : l10n.instanceMemoryMb(value),
                style: AppTheme.body(context),
              ),
            ],
          ),
          if (value != null) ...[
            const m3.SizedBox(height: 6),
            AppSlider(
              value: clampMemoryMb(value).toDouble(),
              min: kMinMemoryMb.toDouble(),
              max: kMaxMemoryMb.toDouble(),
              // 1 GiB steps: the exact MiB is not a decision anyone makes, and a
              // continuous slider invites pointless precision.
              divisions: (kMaxMemoryMb - kMinMemoryMb) ~/ 1024,
              valueLabel: l10n.instanceMemoryMb(value),
              label: l10n.instanceMemoryLabel,
              onChanged: (v) => onChanged((v / 1024).round() * 1024),
            ),
            m3.Text(
              l10n.instanceMemoryBigger,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Per-instance JVM override: the detected runtimes, or the global default.
class _JavaRow extends ConsumerStatefulWidget {
  const _JavaRow({required this.instance, required this.onChanged});

  final Instance instance;
  final void Function(String? path) onChanged;

  @override
  ConsumerState<_JavaRow> createState() => _JavaRowState();
}

/// The probe result, as the row renders it.
sealed class _ProbeResult {
  const _ProbeResult();
}

class _ProbeRunning extends _ProbeResult {
  const _ProbeRunning();
}

class _ProbeOk extends _ProbeResult {
  const _ProbeOk(this.major, this.version, this.vendor);

  final int major;
  final String version;
  final String vendor;
}

class _ProbeFailed extends _ProbeResult {
  const _ProbeFailed();
}

class _JavaRowState extends ConsumerState<_JavaRow> {
  _ProbeResult? _result;

  /// Which executable [_result] describes. A result for the previous choice must
  /// not be shown against the new one: "Works: Java 17" next to a 8 runtime is
  /// worse than no answer.
  String? _resultFor;

  Future<void> _test(String executable) async {
    setState(() {
      _result = const _ProbeRunning();
      _resultFor = executable;
    });
    final runtime = await ref.read(javaProbeRunnerProvider)(executable);
    if (!mounted || _resultFor != executable) return;
    setState(() {
      _result = runtime == null
          ? const _ProbeFailed()
          : _ProbeOk(
              runtime.majorVersion,
              runtime.versionString,
              runtime.vendor,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final instance = widget.instance;
    final onChanged = widget.onChanged;
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final runtimes = ref.watch(javaRuntimesProvider).value ?? const [];

    // `null` is a real choice here ("use the launcher's automatic pick"), and
    // `DropdownButtonFormField` keys its items by value, so the sentinel string
    // carries that meaning through the widget and is mapped back on select.
    const automatic = '\u0000automatic';
    final selectedValue = instance.javaPath ?? automatic;

    return _Row(
      label: l10n.instanceJavaLabel,
      hint: l10n.instanceJavaHint,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          m3.DropdownButtonFormField<String>(
            key: const m3.ValueKey('instance-java'),
            initialValue: selectedValue,
            isExpanded: true,
            decoration: m3.InputDecoration(
              border: const m3.OutlineInputBorder(),
              contentPadding: const m3.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              m3.DropdownMenuItem(
                value: automatic,
                child: m3.Text(l10n.instanceJavaAutomatic),
              ),
              for (final runtime in runtimes)
                m3.DropdownMenuItem(
                  value: runtime.executable,
                  child: m3.Text(
                    runtime.majorVersion == null
                        ? runtime.versionName
                        : 'Java ${runtime.majorVersion!.majorVersion}'
                              ' (${runtime.versionName})',
                  ),
                ),
              // A hand-written path stays selectable: it is what the instance
              // is configured with, even if this launcher never scanned it.
              if (instance.javaPath != null &&
                  !runtimes.any((r) => r.executable == instance.javaPath))
                m3.DropdownMenuItem(
                  value: instance.javaPath,
                  child: m3.Text(instance.javaPath!),
                ),
            ],
            onChanged: (value) => onChanged(value == automatic ? null : value),
          ),
          const m3.SizedBox(height: 6),
          m3.Text(
            runtimes.isEmpty
                ? l10n.instanceJavaNoneDownloaded
                : l10n.instanceJavaHintDetail,
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          if (instance.javaPath != null) ...[
            const m3.SizedBox(height: 8),
            _javaTestRow(context, l10n, instance.javaPath!),
          ],
        ],
      ),
    );
  }

  Widget _javaTestRow(
    BuildContext context,
    AppLocalizations l10n,
    String executable,
  ) {
    final result = _resultFor == executable ? _result : null;
    final running = result is _ProbeRunning;
    final caption = AppTheme.caption(context)
        .copyWith(color: m3.Theme.of(context).colorScheme.onSurfaceVariant);

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.Align(
          alignment: m3.AlignmentDirectional.centerStart,
          child: AppButton(
            key: const m3.ValueKey('instance-java-test'),
            onPressed: running ? null : () => _test(executable),
            style: AppButtonStyle.outlined,
            size: AppButtonSize.sm,
            label: m3.Text(
              running ? l10n.instanceJavaTestRunning : l10n.instanceJavaTest,
            ),
          ),
        ),
        if (result != null && !running)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 6),
            child: AppBanner(
              key: const m3.ValueKey('instance-java-test-result'),
              severity: result is _ProbeOk
                  ? BannerSeverity.success
                  : BannerSeverity.error,
              message: switch (result) {
                _ProbeOk(:final major, :final version, :final vendor) =>
                  l10n.instanceJavaTestOk(
                    major,
                    version,
                    vendor.isEmpty ? l10n.instanceJavaTestNoVendor : vendor,
                  ),
                _ => l10n.instanceJavaTestFailed,
              },
            ),
          ),
        if (result == null && !running)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 6),
            child: m3.Text(l10n.instanceJavaTestHint, style: caption),
          ),
      ],
    );
  }
}

/// The Files section, assembled as one list.
///
/// M3's list guidance is that a list is *scanned*: the same slots in every row, one
/// action per row, supplementary actions trailing. The previous arrangement broke
/// all three - a key/value path row, four identical "open folder" buttons, a
/// floating count in the middle, and one more button underneath - so nothing lined
/// up and every row read as a control instead of an item. Here they share one
/// skeleton:
///
///   [icon] Game folder   /path/to/version          [copy]
///   [icon] Mods          mods/            2 items  [open]
///   [icon] Playtime      2h 14m

class _WindowRow extends StatefulWidget {
  const _WindowRow({
    required this.instance,
    required this.onSize,
    required this.onFullscreen,
  });

  final Instance instance;
  final void Function(int? width, int? height) onSize;
  final m3.ValueChanged<bool> onFullscreen;

  @override
  State<_WindowRow> createState() => _WindowRowState();
}

class _WindowRowState extends State<_WindowRow> {
  late final _width = m3.TextEditingController(
    text: widget.instance.windowWidth?.toString() ?? '',
  );
  late final _height = m3.TextEditingController(
    text: widget.instance.windowHeight?.toString() ?? '',
  );

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _commit() {
    final width = int.tryParse(_width.text.trim());
    final height = int.tryParse(_height.text.trim());
    final valid = width != null && height != null && width > 0 && height > 0;
    widget.onSize(valid ? width : null, valid ? height : null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      mainAxisSize: m3.MainAxisSize.min,
      children: [
        m3.Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: m3.WrapCrossAlignment.center,
          children: [
            m3.SizedBox(
              width: 130,
              child: AppTextField(
                key: const m3.ValueKey('instance-window-width'),
                controller: _width,
                label: l10n.instanceWindowWidth,
                onSubmitted: (_) => _commit(),
              ),
            ),
            m3.SizedBox(
              width: 130,
              child: AppTextField(
                key: const m3.ValueKey('instance-window-height'),
                controller: _height,
                label: l10n.instanceWindowHeight,
                onSubmitted: (_) => _commit(),
              ),
            ),
            m3.Row(
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                AppSwitch(
                  key: const m3.ValueKey('instance-fullscreen'),
                  value: widget.instance.fullscreen,
                  onChanged: widget.onFullscreen,
                  label: l10n.instanceFullscreen,
                ),
                const m3.SizedBox(width: 8),
                m3.Text(l10n.instanceFullscreen, style: AppTheme.body(context)),
              ],
            ),
          ],
        ),
        const m3.SizedBox(height: 8),
        m3.Text(
          l10n.instanceWindowHint,
          style: AppTheme.caption(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// "3 h 20 min · last played 2026-10-20", or the never-played sentence.
String _playtimeLine(AppLocalizations l10n, Instance instance) {
  final last = instance.lastPlayedAt;
  if (last == null) return l10n.instanceNeverPlayed;
  String two(int value) => value.toString().padLeft(2, '0');
  return l10n.instancePlaytimeValue(
    formatPlaytime(instance.totalPlaytime),
    '${last.year}-${two(last.month)}-${two(last.day)}',
  );
}
