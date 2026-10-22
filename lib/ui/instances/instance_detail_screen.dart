import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../data/instance_providers.dart';
import '../../data/java_providers.dart';
import '../../data/launch_factory.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import 'instance_card.dart';

/// One instance's settings.
///
/// Every field the launcher actually honours is here, and nothing else. The
/// instance is written back on each edit rather than on a "Save" button: a
/// settings page whose changes are lost when the window closes is a bug report,
/// and there is no multi-field invariant that would need a transaction.
class InstanceDetailScreen extends ConsumerWidget {
  const InstanceDetailScreen({required this.id, this.onClose, super.key});

  final String id;

  /// Leaves the page. Production replaces the route; tests pass a callback so
  /// the page can be asserted without a router.
  final VoidCallback? onClose;

  void _close(BuildContext context) =>
      (onClose ?? () => context.go(Routes.instances))();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(instanceListProvider);

    return switch (state) {
      InstanceListLoading() => const Center(child: ProgressRing()),
      InstanceListFailed(:final message) => Center(
        child: SelectableText(message),
      ),
      InstanceListReady(:final instances) => _body(context, ref, instances),
    };
  }

  Widget _body(BuildContext context, WidgetRef ref, List<Instance> instances) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);

    Instance? instance;
    for (final candidate in instances) {
      if (candidate.id == id) instance = candidate;
    }

    // A stale link (the instance was deleted in another window) is not a crash:
    // say so and offer the way back.
    if (instance == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ShellIcons.warning, size: 28, color: theme.inactiveColor),
            const SizedBox(height: 8),
            Text(l10n.instanceMissing, style: theme.typography.body),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _close(context),
              child: Text(l10n.actionBack),
            ),
          ],
        ),
      );
    }

    final notifier = ref.read(instanceListProvider.notifier);

    return MotionEntrance(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _close(context),
                icon: const Icon(FluentIcons.back),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  instance.displayName,
                  style: theme.typography.title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Button(
                onPressed: () => _delete(context, ref, instance!),
                child: Text(l10n.instanceDelete),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _Section(
                title: l10n.instanceSectionGeneral,
                children: [
                  _NameRow(
                    instance: instance,
                    onChanged: (name) =>
                        notifier.update(instance!.copyWith(name: name)),
                  ),
                  _ReadOnlyRow(
                    label: l10n.instanceVersionLabel,
                    value: [
                      instance.versionId,
                      if (instance.loader.isModded)
                        '${instance.loader.name} '
                                '${instance.loaderVersion ?? ''}'
                            .trim(),
                    ].join('  ·  '),
                  ),
                  _IsolationRow(
                    instance: instance,
                    onChanged: (isolation) => notifier.update(
                      instance!.copyWith(isolation: isolation),
                    ),
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
                      instance!.copyWith(
                        memoryMb: memoryMb,
                        clearMemoryMb: memoryMb == null,
                      ),
                    ),
                  ),
                  _JavaRow(
                    instance: instance,
                    onChanged: (path) => notifier.update(
                      instance!.copyWith(
                        javaPath: path,
                        clearJavaPath: path == null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: l10n.instanceSectionFiles,
                children: [
                  _ReadOnlyRow(
                    label: l10n.instancePathLabel,
                    value: ref
                        .read(launcherPathsProvider)
                        .gamePathsFor(instance)
                        .root,
                    monospace: true,
                  ),
                  _PlaytimeRow(instance: instance),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Button(
                      key: const ValueKey('instance-open-folder'),
                      onPressed: () => _openFolder(context, ref, instance!),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(ShellIcons.folder, size: 14),
                          const SizedBox(width: 6),
                          Text(l10n.instanceOpenFolder),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the directory in the OS file manager.
  ///
  /// The directory is created first: for a never-launched instance it does not
  /// exist yet, and "open folder" silently doing nothing is worse than making an
  /// empty one.
  Future<void> _openFolder(
    BuildContext context,
    WidgetRef ref,
    Instance instance,
  ) async {
    final root = ref.read(launcherPathsProvider).gamePathsFor(instance).root;
    await Directory(root).create(recursive: true);

    final (exe, args) = switch (Platform.operatingSystem) {
      'windows' => ('explorer', [root]),
      'macos' => ('open', [root]),
      _ => ('xdg-open', [root]),
    };
    try {
      await Process.start(exe, args, mode: ProcessStartMode.detached);
    } on ProcessException {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(context.l10n.instanceOpenFolderFailed),
          content: SelectableText(root),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.actionClose),
            ),
          ],
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(l10n.instanceDelete),
        content: Text(l10n.instanceDeleteConfirm(instance.displayName)),
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
    await ref.read(instanceListProvider.notifier).remove(instance.id);
    if (!context.mounted) return;
    _close(context);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.resources.dividerStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.typography.bodyStrong),
          const SizedBox(height: 10),
          for (final child in children) ...[child, const SizedBox(height: 8)],
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
    final theme = FluentTheme.of(context);
    final hint = this.hint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(label, style: theme.typography.body),
              ),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hint,
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return _Row(
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SelectableText(
          value,
          style: theme.typography.body?.copyWith(
            fontFamily: monospace ? 'Consolas' : null,
            color: theme.inactiveColor,
          ),
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
      child: TextBox(
        key: const ValueKey('instance-name'),
        controller: _controller,
        focusNode: _focus,
        placeholder: context.l10n.instanceNameHint,
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
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ToggleSwitch(
          key: const ValueKey('instance-isolation'),
          checked: isolated,
          onChanged: (value) => onChanged(
            value ? IsolationKind.isolated : IsolationKind.shareLibraries,
          ),
          content: Text(
            isolated ? l10n.instanceIsolationOn : l10n.instanceIsolationOff,
          ),
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
    final theme = FluentTheme.of(context);
    final global = ref.watch(appSettingsMemoryProvider);
    final value = instance.memoryMb;

    return _Row(
      label: l10n.instanceMemoryLabel,
      hint: l10n.instanceMemoryHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleSwitch(
            key: const ValueKey('instance-memory-override'),
            checked: value != null,
            onChanged: (on) => onChanged(on ? global : null),
            content: Text(
              value == null
                  ? l10n.instanceMemoryUsingDefault(global)
                  : l10n.instanceMemoryMb(value),
            ),
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Slider(
              value: value.clamp(_minMb, _maxMb).toDouble(),
              min: _minMb.toDouble(),
              max: _maxMb.toDouble(),
              // 1 GiB steps: the exact MiB is not a decision anyone makes, and a
              // continuous slider invites pointless precision.
              divisions: (_maxMb - _minMb) ~/ 1024,
              label: l10n.instanceMemoryMb(value),
              onChanged: (v) => onChanged((v / 1024).round() * 1024),
            ),
            Text(
              l10n.instanceMemoryBigger,
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _minMb = 512;
  static const _maxMb = 16384;
}

/// Per-instance JVM override: the detected runtimes, or the global default.
class _JavaRow extends ConsumerWidget {
  const _JavaRow({required this.instance, required this.onChanged});

  final Instance instance;
  final void Function(String? path) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);
    final runtimes = ref.watch(javaRuntimesProvider).value ?? const [];

    return _Row(
      label: l10n.instanceJavaLabel,
      hint: l10n.instanceJavaHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ComboBox<String?>(
            key: const ValueKey('instance-java'),
            isExpanded: true,
            value: instance.javaPath,
            onChanged: (value) => onChanged(value),
            items: [
              ComboBoxItem(
                value: null,
                child: Text(l10n.instanceJavaAutomatic),
              ),
              for (final runtime in runtimes)
                ComboBoxItem(
                  value: runtime.executable,
                  child: Text(
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
                ComboBoxItem(
                  value: instance.javaPath,
                  child: Text(instance.javaPath!),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            runtimes.isEmpty
                ? l10n.instanceJavaNoneDownloaded
                : l10n.instanceJavaHintDetail,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaytimeRow extends StatelessWidget {
  const _PlaytimeRow({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final last = instance.lastPlayedAt;
    return _ReadOnlyRow(
      label: l10n.instancePlaytimeLabel,
      value: last == null
          ? l10n.instanceNeverPlayed
          : l10n.instancePlaytimeValue(
              formatPlaytime(instance.totalPlaytime),
              '${last.year}-${_two(last.month)}-${_two(last.day)}',
            ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
