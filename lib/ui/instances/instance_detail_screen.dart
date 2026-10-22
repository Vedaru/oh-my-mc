import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../core/instance/memory.dart';
import '../../core/mc/game_folders.dart';
import '../../data/instance_providers.dart';
import '../../data/java_providers.dart';
import '../../data/launch_factory.dart';
import '../../l10n/l10n.dart';
import '../components/app_banner.dart';
import '../components/list_row.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'args_field.dart';
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
class InstanceDetailScreen extends ConsumerWidget {
  const InstanceDetailScreen({required this.id, this.onClose, super.key});

  final String id;

  /// Leaves the page. Production replaces the route; tests pass a callback so
  /// the page can be asserted without a router.
  final VoidCallback? onClose;

  /// Leaves the page.
  ///
  /// `pop` when the page was pushed (the normal path from a card), because the
  /// card has to still be mounted for the icon to fly back to it; `go` would
  /// rebuild the stack and the return flight would be a cut. The fallback keeps
  /// a deep link - which has no page under it - landing on the grid rather than
  /// on an empty navigator.
  void _close(BuildContext context) {
    final close = onClose;
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
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(instanceListProvider);

    return switch (state) {
      InstanceListLoading() => const m3.Center(
        child: m3.CircularProgressIndicator(),
      ),
      InstanceListFailed(:final message) => m3.Center(
        child: m3.SelectableText(message),
      ),
      InstanceListReady(:final instances) => _body(context, ref, instances),
    };
  }

  Widget _body(BuildContext context, WidgetRef ref, List<Instance> instances) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    Instance? instance;
    for (final candidate in instances) {
      if (candidate.id == id) instance = candidate;
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

    final notifier = ref.read(instanceListProvider.notifier);

    return MotionEntrance(
      children: [
        m3.Padding(
          padding: const m3.EdgeInsets.fromLTRB(8, 12, 16, 8),
          child: m3.Row(
            children: [
              m3.IconButton(
                onPressed: () => _close(context),
                icon: const m3.Icon(ShellIcons.back),
                tooltip: l10n.actionBack,
              ),
              const m3.SizedBox(width: 4),
              m3.Hero(
                tag: instanceHeroTag(instance.id),
                child: m3.Icon(
                  instance.loader.isModded
                      ? ShellIcons.addon
                      : ShellIcons.instance,
                  size: 22,
                  color: scheme.primary,
                ),
              ),
              const m3.SizedBox(width: 10),
              m3.Expanded(
                child: m3.Text(
                  instance.displayName,
                  style: AppTheme.title(context),
                  overflow: m3.TextOverflow.ellipsis,
                ),
              ),
              AppButton(
                onPressed: () => _delete(context, ref, instance!),
                style: AppButtonStyle.text,
                label: m3.Text(l10n.instanceDelete),
              ),
            ],
          ),
        ),
        m3.Expanded(
          child: m3.ListView(
            padding: const m3.EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                title: l10n.instanceSectionWindow,
                children: [
                  _WindowRow(
                    instance: instance,
                    onSize: (width, height) => notifier.update(
                      instance!.copyWith(
                        windowWidth: width,
                        windowHeight: height,
                        clearWindowSize: width == null && height == null,
                      ),
                    ),
                    onFullscreen: (value) =>
                        notifier.update(instance!.copyWith(fullscreen: value)),
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
                        notifier.update(instance!.copyWith(jvmArgs: args)),
                  ),
                  ArgsField(
                    fieldKey: const ValueKey('instance-game-args'),
                    label: l10n.instanceGameArgsLabel,
                    hint: l10n.instanceGameArgsHint,
                    value: instance.gameArgs,
                    onChanged: (args) =>
                        notifier.update(instance!.copyWith(gameArgs: args)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Section(
                title: l10n.instanceSectionFiles,
                description: l10n.instanceFilesHint,
                children: [
                  _FilesList(
                    instance: instance,
                    onOpenFolder: (folder) =>
                        _openFolder(context, ref, instance!, folder: folder),
                    onOpenRoot: () => _openFolder(context, ref, instance!),
                    onCopyPath: (path) => _copyPath(context, path),
                    onManageMods: () =>
                        context.go(Routes.instanceMods(instance!.id)),
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
  Future<void> _copyPath(BuildContext context, String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    m3.ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        m3.SnackBar(
          content: m3.Text(context.l10n.instancePathCopied),
          behavior: m3.SnackBarBehavior.floating,
          width: 200,
        ),
      );
  }

  Future<void> _openFolder(
    BuildContext context,
    WidgetRef ref,
    Instance instance, {
    GameFolderKind? folder,
  }) async {
    final gameRoot = ref
        .read(launcherPathsProvider)
        .gamePathsFor(instance)
        .root;
    final root = folder == null
        ? gameRoot
        : '$gameRoot/${folder.directoryName}';
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
      await m3.showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: context.l10n.instanceOpenFolderFailed,
          content: m3.SelectableText(root),
          actions: [
            AppButton(
              onPressed: () => m3.Navigator.pop(context),
              style: AppButtonStyle.filled,
              label: m3.Text(context.l10n.actionClose),
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
  const _Section({
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final List<Widget> children;

  /// One line under the heading saying what the section is for. M3 puts an
  /// optional description in the header block, not in a tooltip or a footnote:
  /// the reader meets it before the content.
  final String? description;

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
          if (description != null) ...[
            const m3.SizedBox(height: 2),
            m3.Text(
              description!,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
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
          width: 180,
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
        label: context.l10n.instanceNameLabel,
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
class _FilesList extends StatefulWidget {
  const _FilesList({
    required this.instance,
    required this.onOpenFolder,
    required this.onOpenRoot,
    required this.onCopyPath,
    required this.onManageMods,
  });

  final Instance instance;
  final void Function(GameFolderKind folder) onOpenFolder;
  final VoidCallback onOpenRoot;
  final void Function(String path) onCopyPath;

  /// The mods row is the one content folder with a screen behind it: PCL's
  /// 版本设置 → Mod 管理 is where enabling and deleting happens, so the row opens
  /// that instead of a file manager (the trailing icon still opens the folder).
  final VoidCallback onManageMods;

  @override
  State<_FilesList> createState() => _FilesListState();
}

class _FilesListState extends State<_FilesList> {
  Future<List<GameFolder>>? _folders;
  String? _root;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final container = ProviderScope.containerOf(context);
    final root = container
        .read(launcherPathsProvider)
        .gamePathsFor(widget.instance)
        .root;
    if (_root != root) {
      _root = root;
      _folders = container.read(gameFolderScannerProvider)(root);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final root = _root ?? '';

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      mainAxisSize: m3.MainAxisSize.min,
      children: [
        ListRow(
          leadingIcon: ShellIcons.folder,
          label: l10n.instancePathLabel,
          supporting: root,
          trailingIcon: ShellIcons.copy,
          trailingTooltip: l10n.instanceCopyPath,
          onPressed: widget.onOpenRoot,
          onTrailingPressed: () => widget.onCopyPath(root),
        ),
        FutureBuilder<List<GameFolder>>(
          future: _folders,
          builder: (context, snapshot) {
            final folders = snapshot.data ?? const <GameFolder>[];
            return m3.Column(
              crossAxisAlignment: m3.CrossAxisAlignment.stretch,
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                for (final folder in folders)
                  ListRow(
                    key: m3.ValueKey(
                      'instance-folder-${folder.kind.directoryName}',
                    ),
                    leadingIcon: _folderIcon(folder.kind),
                    label: _folderLabel(l10n, folder.kind),
                    supporting: folder.kind == GameFolderKind.mods
                        ? l10n.modsManageHint
                        : '${folder.kind.directoryName}/',
                    trailingText: l10n.instanceFolderItems(folder.entries),
                    trailingTextKey: m3.ValueKey(
                      'instance-folder-count-${folder.kind.name}',
                    ),
                    trailingIcon: ShellIcons.openExternal,
                    trailingTooltip: l10n.instanceOpenFolderTooltip,
                    onPressed: folder.kind == GameFolderKind.mods
                        ? widget.onManageMods
                        : () => widget.onOpenFolder(folder.kind),
                    onTrailingPressed: () => widget.onOpenFolder(folder.kind),
                  ),
              ],
            );
          },
        ),
        ListRow(
          leadingIcon: ShellIcons.clock,
          label: l10n.instancePlaytimeLabel,
          trailingText: _playtime(l10n, widget.instance),
        ),
      ],
    );
  }

  static String _playtime(AppLocalizations l10n, Instance instance) {
    final last = instance.lastPlayedAt;
    if (last == null) return l10n.instanceNeverPlayed;
    return l10n.instancePlaytimeValue(
      formatPlaytime(instance.totalPlaytime),
      '${last.year}-${_two(last.month)}-${_two(last.day)}',
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// A different cue per folder. M3 asks the leading icon to relate to the label;
  /// four identical puzzle pieces would be decoration, not a cue.
  static m3.IconData _folderIcon(GameFolderKind kind) => switch (kind) {
    GameFolderKind.mods => ShellIcons.mods,
    GameFolderKind.resourcePacks => ShellIcons.resourcePacks,
    GameFolderKind.shaderPacks => ShellIcons.shaderPacks,
    GameFolderKind.saves => ShellIcons.saves,
  };

  static String _folderLabel(AppLocalizations l10n, GameFolderKind kind) =>
      switch (kind) {
        GameFolderKind.mods => l10n.instanceFolderMods,
        GameFolderKind.resourcePacks => l10n.instanceFolderResourcePacks,
        GameFolderKind.shaderPacks => l10n.instanceFolderShaderPacks,
        GameFolderKind.saves => l10n.instanceFolderSaves,
      };
}

/// Window width/height and the fullscreen switch.
///
/// Text fields rather than a slider: users copy a size out of a screenshot or a
/// config, and 854x480 is a real answer. Both dimensions or neither - half a pair
/// is a typo the game rejects.
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
