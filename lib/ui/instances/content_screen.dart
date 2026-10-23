import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/game/content.dart';
import '../../core/instance/instance.dart';
import '../../data/instance_providers.dart';
import '../../data/launch_factory.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/app_text_field.dart';
import '../components/list_row.dart';
import '../components/open_folder.dart';
import '../components/page_body.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 版本设置 → 资源包 / 光影 / 存档 / 服务器.
///
/// One screen for all four: they are the same list with a different folder and a
/// different verb (toggle, delete, connect), and four screens would have been four
/// copies of the same code with four sets of bugs.
class ContentScreen extends ConsumerStatefulWidget {
  const ContentScreen({required this.id, required this.kind, super.key});

  final String id;
  final ContentKind kind;

  @override
  ConsumerState<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends ConsumerState<ContentScreen> {
  List<ContentEntry>? _entries;
  String? _error;
  var _busy = false;

  /// The root the current list was read from.
  ///
  /// `initState` runs before the instance list is ready, so its first read lands on a
  /// null root; without this the screen stayed empty forever and only a manual
  /// reload fixed it.
  String? _loadedRoot;

  /// The instance this screen belongs to, or null while the list is loading and for
  /// an id that no longer exists.
  ///
  /// A plain `as InstanceListReady?` cast used to sit here and threw on the loading
  /// state: opening a content screen while the list was still being read crashed the
  /// page instead of showing a spinner.
  Instance? _instanceOf(WidgetRef ref) {
    final state = ref.read(instanceListProvider);
    if (state is! InstanceListReady) return null;
    return state.instances.where((i) => i.id == widget.id).firstOrNull;
  }

  String? get _root {
    final instance = _instanceOf(ref);
    if (instance == null) return null;
    return ref.read(launcherPathsProvider).gamePathsFor(instance).root;
  }

  GameContent get _content => ref.read(gameContentProvider)(_root ?? '');

  Future<void> _load() async {
    final root = _root;
    if (root == null) return;
    try {
      final entries = await ref
          .read(gameContentProvider)(root)
          .list(widget.kind);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _toggle(ContentEntry entry, bool enabled) async {
    setState(() => _busy = true);
    try {
      await _content.setResourcePackEnabled(entry.name, enabled);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ContentEntry entry) async {
    final l10n = context.l10n;
    // A world is not recoverable from the recycle bin on most systems, and a pack
    // the user deleted by accident is one download away - both are worth a question.
    final confirmed = await m3.showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.contentDeleteTitle(entry.name),
        content: m3.Text(l10n.contentDeleteBody),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.of(context).pop(false),
            style: AppButtonStyle.text,
            label: m3.Text(l10n.actionCancel),
          ),
          AppButton(
            key: const m3.ValueKey('content-confirm-delete'),
            onPressed: () => m3.Navigator.of(context).pop(true),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _content.delete(widget.kind, entry.path);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addServer() async {
    final l10n = context.l10n;
    final name = m3.TextEditingController();
    final address = m3.TextEditingController();
    final added = await m3.showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.contentAddServer,
        content: m3.Column(
          mainAxisSize: m3.MainAxisSize.min,
          children: [
            AppTextField(
              key: const m3.ValueKey('server-name'),
              controller: name,
              hint: l10n.contentServerName,
              autofocus: true,
            ),
            const m3.SizedBox(height: 8),
            AppTextField(
              key: const m3.ValueKey('server-address'),
              controller: address,
              hint: l10n.contentServerAddress,
            ),
          ],
        ),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.of(context).pop(false),
            style: AppButtonStyle.text,
            label: m3.Text(l10n.actionCancel),
          ),
          AppButton(
            key: const m3.ValueKey('server-save'),
            onPressed: () => m3.Navigator.of(context).pop(true),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.actionSave),
          ),
        ],
      ),
    );
    final ip = address.text.trim();
    if (added != true || ip.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _content.addServer(
        // An unnamed server shows its address in the game's own list, so the address
        // is a better default than an empty name.
        name: name.text.trim().isEmpty ? ip : name.text.trim(),
        ip: ip,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(instanceListProvider);
    final instance = state is InstanceListReady
        ? state.instances.where((i) => i.id == widget.id).firstOrNull
        : null;
    if (state is! InstanceListReady) {
      // Still reading the list: a spinner beats "this instance no longer exists",
      // which would be a lie that lasts a frame.
      return PageBody(
        scrollable: false,
        child: m3.Column(
          children: [
            PageTitle(l10n.contentTitle(widget.kind)),
            const m3.Expanded(
              child: m3.Center(child: m3.CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }
    if (instance == null) {
      return PageBody(
        scrollable: false,
        child: m3.Column(
          children: [
            PageTitle(l10n.contentTitle(widget.kind)),
            m3.Text(l10n.instanceMissing),
          ],
        ),
      );
    }

    // Read once the instance is known: `initState` cannot see it, and a content
    // screen that quietly shows nothing is worse than a spinner.
    final root = ref.read(launcherPathsProvider).gamePathsFor(instance).root;
    if (_loadedRoot != root) {
      _loadedRoot = root;
      Future<void>.microtask(_load);
    }

    final entries = _entries;
    return PageBody(
      // Not scrollable: the list inside expands to the page height, and an
      // `Expanded` inside a scrolling column has no height to expand into.
      scrollable: false,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          PageTitle(
            l10n.contentTitle(widget.kind),
            trailing: m3.Row(
              children: [
                if (widget.kind == ContentKind.servers)
                  AppButton(
                    key: const m3.ValueKey('content-add-server'),
                    onPressed: _busy ? null : _addServer,
                    style: AppButtonStyle.filled,
                    size: AppButtonSize.sm,
                    icon: const m3.Icon(ShellIcons.add, size: 14),
                    label: m3.Text(l10n.contentAddServer),
                  ),
                const m3.SizedBox(width: 8),
                AppButton(
                  key: const m3.ValueKey('content-open-folder'),
                  onPressed: () => _openFolder(context, instance),
                  style: AppButtonStyle.text,
                  size: AppButtonSize.sm,
                  icon: const m3.Icon(ShellIcons.folder, size: 14),
                  label: m3.Text(l10n.instanceOpenFolderTooltip),
                ),
              ],
            ),
          ),
          m3.Text(
            l10n.contentHint(widget.kind),
            style: AppTheme.caption(context).copyWith(
              color: m3.Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const m3.SizedBox(height: 12),
          if (_error != null)
            m3.SelectableText(_error!, style: AppTheme.mono(context)),
          m3.Expanded(
            child: entries == null
                ? const m3.Center(child: m3.CircularProgressIndicator())
                : entries.isEmpty
                ? m3.Center(
                    child: m3.Text(
                      l10n.contentEmpty(widget.kind),
                      style: AppTheme.body(context).copyWith(
                        color: m3.Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  )
                : m3.ListView(
                    padding: m3.EdgeInsets.zero,
                    children: [
                      for (final entry in entries)
                        ListRow(
                          key: m3.ValueKey('content-${entry.name}'),
                          leadingIcon: switch (widget.kind) {
                            ContentKind.resourcePacks =>
                              ShellIcons.resourcePacks,
                            ContentKind.shaderPacks => ShellIcons.shaderPacks,
                            ContentKind.saves => ShellIcons.saves,
                            ContentKind.servers => ShellIcons.network,
                          },
                          label: entry.name,
                          // The size always reads as the supporting line, never as
                          // the trailing text: on a pack row the trailing slot holds
                          // the switch, and a row that shows one or the other
                          // depending on its kind is two designs in one list.
                          supporting:
                              _supporting(entry) ??
                              formatContentSize(entry.sizeBytes),
                          trailingControl: m3.Row(
                            mainAxisSize: m3.MainAxisSize.min,
                            children: [
                              // Only resource packs have a state the launcher can
                              // write: Iris keeps its active shader in its own
                              // config, so a toggle there would be a lie.
                              if (widget.kind == ContentKind.resourcePacks)
                                m3.Switch(
                                  value: entry.enabled,
                                  onChanged: _busy
                                      ? null
                                      : (value) => _toggle(entry, value),
                                ),
                              m3.IconButton(
                                key: m3.ValueKey(
                                  'content-delete-${entry.name}',
                                ),
                                onPressed: _busy ? null : () => _delete(entry),
                                icon: const m3.Icon(ShellIcons.trash, size: 16),
                                tooltip: l10n.actionDelete,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// A second line worth reading: a world's age, a server's address. Size is the
  /// fallback, added by the row itself.
  String? _supporting(ContentEntry entry) {
    final parts = [
      if (entry.detail != null) entry.detail!,
      if (entry.sizeBytes > 0 && widget.kind != ContentKind.servers)
        formatContentSize(entry.sizeBytes),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _openFolder(BuildContext context, Instance instance) async {
    final paths = ref.read(launcherPathsProvider);
    final root = paths.gamePathsFor(instance).root;
    final target = widget.kind == ContentKind.servers
        ? root
        : '$root/${widget.kind.path}';
    await openFolder(context, target);
  }
}

/// Enum → words. The ARB files cannot hold an enum, and a `switch` here is the
/// single place the four kinds get their names.
extension ContentCopy on AppLocalizations {
  String contentTitle(ContentKind kind) => switch (kind) {
    ContentKind.resourcePacks => contentResourcePacks,
    ContentKind.shaderPacks => contentShaderPacks,
    ContentKind.saves => contentSaves,
    ContentKind.servers => contentServers,
  };

  String contentHint(ContentKind kind) => switch (kind) {
    ContentKind.resourcePacks => contentResourcePacksHint,
    ContentKind.shaderPacks => contentShaderPacksHint,
    ContentKind.saves => contentSavesHint,
    ContentKind.servers => contentServersHint,
  };

  String contentEmpty(ContentKind kind) => switch (kind) {
    ContentKind.resourcePacks => contentEmptyResourcePacks,
    ContentKind.shaderPacks => contentEmptyShaderPacks,
    ContentKind.saves => contentEmptySaves,
    ContentKind.servers => contentEmptyServers,
  };
}

/// Where a [GameContent] comes from.
///
/// A provider, not a direct constructor call, for one reason: the screen reads the
/// real disk, and real file I/O never completes inside a widget test's fake clock.
/// A test injects an in-memory implementation and asserts the *interaction*; the
/// disk behaviour is pinned by `test/core/game/content_test.dart`.
final gameContentProvider = Provider<GameContent Function(String root)>(
  (ref) => GameContent.new,
);
