import 'dart:io';

import 'package:go_router/go_router.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:path/path.dart' as p;

import '../../core/game/content.dart';
import '../../core/instance/instance.dart';
import '../../core/launch/join_target.dart';
import '../../core/mods/mod_scanner.dart';
import '../../core/mods/modrinth.dart';
import '../../core/mods/update_checker.dart';
import '../../app/router.dart';
import '../../data/backup_providers.dart';
import '../../data/game_content_provider.dart';
import '../../data/launch_factory.dart';
import '../../data/launch_providers.dart';
import '../../data/mods_providers.dart';
import '../../data/server_providers.dart';
import '../../data/modrinth_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/empty_state.dart';
import '../components/list_row.dart';
import '../components/open_folder.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'content_search_dialog.dart';

/// The six content pages of an instance.
///
/// Bare values; the folder and catalogue mappings are an extension at the bottom of
/// this file, so the enum reads as a list of pages rather than a switch table.
enum InstanceContentKind {
  mods,
  resourcePacks,
  shaderPacks,
  worlds,
  servers,
  dataPacks,
}

/// One content folder of one instance: mods, resource packs, shaders, worlds,
/// servers or data packs.
///
/// **One page per kind**, the way Prism, MultiMC and PCL all arrange a version
/// (`ModFolderPage`, `ResourcePackPage`, `ShaderPackPage`, `WorldListPage`,
/// `ServersPage`, `DataPackPage`). A single list with a kind filter reads as one
/// undifferentiated pile, and the kinds genuinely differ: a mod is switched off by
/// renaming the jar, a resource pack by editing `options.txt`, a world only has
/// "delete", and a data pack belongs to one world.
class InstanceContentPage extends ConsumerStatefulWidget {
  const InstanceContentPage({
    required this.instance,
    required this.kind,
    super.key,
  });

  final Instance instance;
  final InstanceContentKind kind;

  @override
  ConsumerState<InstanceContentPage> createState() =>
      _InstanceContentPageState();
}

class _InstanceContentPageState extends ConsumerState<InstanceContentPage> {
  /// Bumped after a write, so the list re-reads the folder the write landed in.
  var _generation = 0;

  /// Mods with a newer version on Modrinth, once the user asked.
  List<ModUpdate>? _updates;
  var _checking = false;

  /// The world the data pack page is pointed at.
  ///
  /// It lives on the page, not in the list, because the install action is here: asking
  /// for the world twice - once for the list, once for the download - is the dialog
  /// equivalent of walking back to the door.
  var _world = '';

  String get _root =>
      ref.read(launcherPathsProvider).gamePathsFor(widget.instance).root;

  @override
  void initState() {
    super.initState();
    _initWorld();
  }

  /// A data pack page opens on the newest world: that is the one someone is playing.
  Future<void> _initWorld() async {
    if (widget.kind != InstanceContentKind.dataPacks || _world.isNotEmpty) {
      return;
    }
    final saves = await ref
        .read(gameContentProvider)(_root)
        .list(ContentKind.saves);
    if (!mounted || saves.isEmpty) return;
    setState(() => _world = saves.first.name);
  }

  Future<void> _install() async {
    final catalog = widget.kind.catalog;
    if (catalog == null) return;
    await showContentSearch(
      context: context,
      ref: ref,
      instance: widget.instance,
      kind: catalog,
      world: widget.kind == InstanceContentKind.dataPacks && _world.isNotEmpty
          ? _world
          : null,
    );
    if (mounted) setState(() => _generation++);
  }

  Future<void> _checkUpdates() async {
    final instance = widget.instance;
    if (!instance.loader.isModded) return;
    setState(() => _checking = true);
    try {
      final mods = await ref.read(instanceModsProvider(instance.id).future);
      final updates = await ref
          .read(modUpdateCheckerProvider)
          .check(
            mods,
            gameVersion: instance.versionId,
            loader: instance.loader.modrinthTag,
          );
      if (mounted) setState(() => _updates = updates);
    } on Object {
      // A check that cannot reach Modrinth is not an error state for the list: the
      // mods are still there and the button can be pressed again.
      if (mounted) setState(() => _updates = const []);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Installs the newer file over the old one.
  Future<void> _applyUpdate(ModUpdate update) async {
    await ref
        .read(modInstallerProvider)
        .install(
          plans: [
            ModInstallPlan(
              projectId: update.latest.projectId,
              title: update.mod.name ?? update.latest.name,
              file: update.latest.primaryFile!,
            ),
          ],
          directory: modsDirFor(
            ref.read(launcherPathsProvider),
            widget.instance,
          ),
        );
    // The old jar goes: two versions of the same mod is a crash the launcher caused.
    await ref.read(modsRepositoryProvider).delete(update.mod);
    ref.invalidate(instanceModsProvider(widget.instance.id));
    if (mounted) {
      setState(() {
        _updates = [
          for (final entry in _updates ?? const <ModUpdate>[])
            if (entry.mod.path != update.mod.path) entry,
        ];
      });
    }
  }

  /// A server is a name and an address in `servers.dat`; there is nothing to download.
  Future<void> _addServer() async {
    final server = await m3.showDialog<({String name, String ip})>(
      context: context,
      builder: (context) => const _AddServerDialog(),
    );
    if (server == null) return;
    await ref
        .read(gameContentProvider)(_root)
        .addServer(name: server.name, ip: server.ip);
    if (mounted) setState(() => _generation++);
  }

  /// Starts this instance and goes straight to the server's address.
  ///
  /// The multiplayer screen is a step the launcher can skip: the address is already in
  /// `servers.dat`, so joining is two launch flags.
  void _joinServer(ContentEntry entry) {
    ref
        .read(launchControllerProvider.notifier)
        .launch(widget.instance, join: JoinTarget.parse(entry.path));
    context.go(Routes.launch);
  }

  /// Puts a backup zip back as a save folder, beside the original.
  ///
  /// The restore never overwrites: `WorldBackupService` names the copy
  /// `<world> (restored <stamp>)`, because a restore that silently replaces hours of
  /// play is a data-loss feature wearing a helpful label.
  Future<void> _restoreWorld() async {
    final l10n = context.l10n;
    final messenger = m3.ScaffoldMessenger.maybeOf(context);
    final picked = await FilePicker.pickFiles(
      dialogTitle: l10n.worldRestore,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null || !mounted) return;
    try {
      final restored = await ref
          .read(worldBackupServiceProvider)
          .restore(File(path), savesDir: Directory(p.join(_root, 'saves')));
      if (!mounted) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.worldRestoreDone(p.basename(restored.path))),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
      setState(() => _generation++);
    } on Object catch (e) {
      if (!mounted) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.worldRestoreFailed('$e')),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openFolder() async {
    final target = widget.kind == InstanceContentKind.servers
        ? _root
        : p.join(_root, widget.kind.folderName);
    await openFolder(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDataPacks = widget.kind == InstanceContentKind.dataPacks;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Padding(
          // Same left inset as a `ListRow`, so the hint starts where the rows' text
          // starts instead of 8 px to its left.
          padding: const m3.EdgeInsets.only(bottom: 8, left: 8),
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.stretch,
            children: [
              m3.Text(
                _hint(l10n),
                style: AppTheme.caption(context).copyWith(
                  color: m3.Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const m3.SizedBox(height: 8),
              // `Wrap`, not a `Row`: three buttons and a count have to fit at 824 px
              // of pane on a 1400 px window, and a Row that overflows paints a yellow
              // stripe instead of moving the last button down.
              m3.Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: m3.WrapCrossAlignment.center,
                children: [
                  if (_updates case final updates? when updates.isNotEmpty)
                    m3.Text(
                      l10n.modsUpdatesFound(updates.length),
                      style: AppTheme.caption(context).copyWith(
                        color: m3.Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  AppButton(
                    key: const m3.ValueKey('content-open-folder'),
                    onPressed: _openFolder,
                    style: AppButtonStyle.text,
                    size: AppButtonSize.sm,
                    icon: const m3.Icon(ShellIcons.folder, size: 14),
                    label: m3.Text(l10n.instanceOpenFolderTooltip),
                  ),
                  if (widget.kind == InstanceContentKind.worlds) ...[
                    const m3.SizedBox(width: 8),
                    AppButton(
                      key: const m3.ValueKey('world-restore'),
                      onPressed: _restoreWorld,
                      style: AppButtonStyle.text,
                      size: AppButtonSize.sm,
                      icon: const m3.Icon(ShellIcons.backup, size: 14),
                      label: m3.Text(l10n.worldRestore),
                    ),
                  ],
                  if (widget.kind == InstanceContentKind.servers) ...[
                    m3.IconButton(
                      key: const m3.ValueKey('servers-refresh'),
                      onPressed: () => ref.invalidate(serverPingProvider),
                      icon: const m3.Icon(ShellIcons.refresh, size: 18),
                      tooltip: l10n.actionRefresh,
                    ),
                  ],
                  if (widget.kind == InstanceContentKind.mods &&
                      widget.instance.loader.isModded) ...[
                    const m3.SizedBox(width: 8),
                    AppButton(
                      key: const m3.ValueKey('mods-check-updates'),
                      onPressed: _checking ? null : _checkUpdates,
                      style: AppButtonStyle.text,
                      size: AppButtonSize.sm,
                      icon: const m3.Icon(ShellIcons.refresh, size: 14),
                      label: m3.Text(
                        _checking ? l10n.modsChecking : l10n.modsCheckUpdates,
                      ),
                    ),
                  ],
                  if (widget.kind == InstanceContentKind.servers) ...[
                    const m3.SizedBox(width: 8),
                    AppButton(
                      key: const m3.ValueKey('content-add-server'),
                      onPressed: _addServer,
                      style: AppButtonStyle.filled,
                      size: AppButtonSize.sm,
                      icon: const m3.Icon(ShellIcons.add, size: 14),
                      label: m3.Text(l10n.contentAddServer),
                    ),
                  ],
                  if (widget.kind.catalog != null) ...[
                    const m3.SizedBox(width: 8),
                    AppButton(
                      key: const m3.ValueKey('content-install'),
                      onPressed: _install,
                      style: AppButtonStyle.filled,
                      size: AppButtonSize.sm,
                      icon: const m3.Icon(ShellIcons.add, size: 14),
                      label: m3.Text(l10n.contentInstall),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (isDataPacks)
          _WorldPicker(
            root: _root,
            world: _world,
            onChanged: (world) => setState(() => _world = world),
          ),
        m3.Expanded(
          child: widget.kind == InstanceContentKind.mods
              ? _ModList(
                  key: m3.ValueKey('mods-$_generation'),
                  instance: widget.instance,
                  updates: _updates ?? const [],
                  onApply: _applyUpdate,
                )
              : _GameContentPage(
                  key: m3.ValueKey('${widget.kind.name}-$_generation-$_world'),
                  root: _root,
                  kind: widget.kind,
                  world: _world,
                  onJoinServer: _joinServer,
                ),
        ),
      ],
    );
  }

  String _hint(AppLocalizations l10n) => switch (widget.kind) {
    InstanceContentKind.mods => l10n.contentModsHint,
    InstanceContentKind.resourcePacks => l10n.contentResourcePacksHint,
    InstanceContentKind.shaderPacks => l10n.contentShaderPacksHint,
    InstanceContentKind.worlds => l10n.contentSavesHint,
    InstanceContentKind.servers => l10n.contentServersHint,
    InstanceContentKind.dataPacks => l10n.contentDataPacksHint,
  };
}

/// Mods: switched off by renaming the jar, so this is the one list with a switch.
///
/// Also the one list that can check for updates: a mod has a Modrinth identity (found by
/// the jar's sha1), a pack usually does not.
/// Mods: switched off by renaming the jar, so this is the one list with a switch.
///
/// The update state lives on the page (one toolbar for the section), so this is a
/// plain widget: it draws rows and reports what the user pressed.
class _ModList extends ConsumerWidget {
  const _ModList({
    required this.instance,
    required this.updates,
    required this.onApply,
    super.key,
  });

  final Instance instance;

  /// Mods with a newer version, once the check has run.
  final List<ModUpdate> updates;

  final Future<void> Function(ModUpdate update) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mods = ref.watch(instanceModsProvider(instance.id));

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Expanded(
          child: mods.when(
            loading: () =>
                const m3.Center(child: m3.CircularProgressIndicator()),
            error: (error, _) => m3.SelectableText('$error'),
            data: (entries) {
              if (entries.isEmpty) {
                return EmptyState(
                  icon: ShellIcons.mods,
                  message: l10n.contentEmptyMods,
                  hint: l10n.contentEmptyModsHint,
                );
              }
              return m3.ListView(
                padding: m3.EdgeInsets.zero,
                children: [
                  for (final mod in entries)
                    ListRow(
                      key: m3.ValueKey('mod-${mod.fileName}'),
                      leadingIcon: mod.problem == null
                          ? ShellIcons.mods
                          : ShellIcons.warning,
                      label: mod.displayName,
                      supporting: mod.problem ?? _supporting(mod),
                      errorText: mod.problem,
                      trailingText: _updateLabel(l10n, updates, mod),
                      trailingControl: m3.Row(
                        mainAxisSize: m3.MainAxisSize.min,
                        children: [
                          if (_updateFor(updates, mod) case final update?)
                            m3.IconButton(
                              key: m3.ValueKey('mod-update-${mod.fileName}'),
                              onPressed: () => onApply(update),
                              icon: m3.Icon(
                                ShellIcons.download,
                                size: 18,
                                color: m3.Theme.of(context).colorScheme.primary,
                              ),
                              visualDensity: m3.VisualDensity.compact,
                              tooltip: l10n.modsUpdateAction,
                            ),
                          m3.IconButton(
                            onPressed: () async {
                              await ref
                                  .read(modsRepositoryProvider)
                                  .delete(mod);
                              ref.invalidate(instanceModsProvider(instance.id));
                            },
                            icon: const m3.Icon(ShellIcons.trash, size: 18),
                            visualDensity: m3.VisualDensity.compact,
                            tooltip: l10n.actionDelete,
                          ),
                          const m3.SizedBox(width: 4),
                          // The row's state is the last thing at the edge.
                          m3.Switch(
                            value: mod.enabled,
                            onChanged: (value) async {
                              await ref
                                  .read(modsRepositoryProvider)
                                  .setEnabled(mod, value);
                              ref.invalidate(instanceModsProvider(instance.id));
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String? _updateLabel(
    AppLocalizations l10n,
    List<ModUpdate> updates,
    ModEntry mod,
  ) {
    final update = _updateFor(updates, mod);
    if (update == null) return null;
    return l10n.modsUpdateTo(update.to);
  }

  static ModUpdate? _updateFor(List<ModUpdate> updates, ModEntry mod) {
    for (final update in updates) {
      if (update.mod.path == mod.path) return update;
    }
    return null;
  }

  static String _supporting(ModEntry mod) => [
    if (mod.version != null) mod.version!,
    mod.loader.label,
    formatContentSize(mod.sizeBytes),
  ].join(' · ');
}

class _GameContentPage extends ConsumerStatefulWidget {
  const _GameContentPage({
    required this.root,
    required this.kind,
    required this.world,
    this.onJoinServer,
    super.key,
  });

  final String root;
  final InstanceContentKind kind;

  /// The world a data pack page is pointed at; empty for every other kind.
  final String world;

  /// Present on the servers page: start the game into that row's address.
  final void Function(ContentEntry entry)? onJoinServer;

  @override
  ConsumerState<_GameContentPage> createState() => _GameContentPageState();
}

class _GameContentPageState extends ConsumerState<_GameContentPage> {
  List<ContentEntry>? _entries;

  ContentKind get _contentKind => widget.kind.contentKind!;

  /// `GameContent` takes the root the folder lives under: the game root for
  /// `resourcepacks/` and friends, the world directory for `datapacks/`.
  GameContent get _content => ref.read(gameContentProvider)(
    widget.kind == InstanceContentKind.dataPacks
        ? p.join(widget.root, 'saves', widget.world)
        : widget.root,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_GameContentPage old) {
    super.didUpdateWidget(old);
    // A different world is a different folder: re-read it.
    if (old.world != widget.world) _load();
  }

  Future<void> _load() async {
    if (widget.kind == InstanceContentKind.dataPacks && widget.world.isEmpty) {
      setState(() => _entries = const []);
      return;
    }
    final entries = await _content.list(_contentKind);
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _toggle(ContentEntry entry, bool enabled) async {
    // `options.txt` lives in the instance root, not in the pack folder.
    await ref
        .read(gameContentProvider)(widget.root)
        .setResourcePackEnabled(entry.name, enabled);
    await _load();
  }

  /// A world is the one thing here that cannot be downloaded again, so it gets a
  /// copy before it gets a delete.
  Future<void> _backUpWorld(ContentEntry entry) async {
    final l10n = context.l10n;
    final messenger = m3.ScaffoldMessenger.maybeOf(context);
    try {
      final backup = await ref
          .read(worldBackupServiceProvider)
          .backUp(
            Directory(entry.path),
            backupsDir: Directory(p.join(widget.root, 'backups')),
          );
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.worldBackupDone(backup.fileName)),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    } on Object catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.worldBackupFailed('$e')),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _delete(ContentEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await m3.showDialog<bool>(
      context: context,
      builder: (context) => m3.AlertDialog(
        title: m3.Text(l10n.contentDeleteTitle(entry.name)),
        content: m3.Text(l10n.contentDeleteBody),
        actions: [
          m3.TextButton(
            onPressed: () => m3.Navigator.of(context).pop(false),
            child: m3.Text(l10n.actionCancel),
          ),
          m3.TextButton(
            key: const m3.ValueKey('content-confirm-delete'),
            onPressed: () => m3.Navigator.of(context).pop(true),
            child: m3.Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _content.delete(_contentKind, entry.path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null) {
      return const m3.Center(child: m3.CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: _iconFor(widget.kind),
        message: _emptyMessage(context.l10n),
        hint: context.l10n.contentEmptyHint,
      );
    }

    return m3.ListView(
      padding: m3.EdgeInsets.zero,
      children: [
        for (final entry in entries)
          ListRow(
            key: m3.ValueKey('content-${entry.name}'),
            leadingIcon: _iconFor(widget.kind),
            leadingImage: ref
                .watch(
                  contentIconProvider((
                    path: entry.path,
                    isDirectory: entry.isDirectory,
                  )),
                )
                .value,
            label: entry.name,
            // A server row's second line is the server's own answer; everything
            // else gets the data the file system has.
            supporting: widget.kind == InstanceContentKind.servers
                ? ''
                : [
                    entry.detail,
                    formatContentSize(entry.sizeBytes),
                  ].whereType<String>().join(' · '),
            supportingWidget: widget.kind == InstanceContentKind.servers
                ? _ServerStatus(address: entry.path)
                : null,
            trailingControl: m3.Row(
              mainAxisSize: m3.MainAxisSize.min,
              children: [
                // Only a resource pack has a state the launcher can write: Iris keeps
                // the active shader in its own config, and a world or a server has no
                // "off".
                if (widget.kind == InstanceContentKind.worlds)
                  m3.IconButton(
                    key: m3.ValueKey('world-backup-${entry.name}'),
                    onPressed: () => _backUpWorld(entry),
                    icon: const m3.Icon(ShellIcons.backup, size: 18),
                    visualDensity: m3.VisualDensity.compact,
                    tooltip: context.l10n.worldBackup,
                  ),
                if (widget.kind == InstanceContentKind.servers &&
                    widget.onJoinServer != null)
                  m3.IconButton(
                    key: m3.ValueKey('server-join-${entry.name}'),
                    onPressed: () => widget.onJoinServer!(entry),
                    icon: const m3.Icon(ShellIcons.play, size: 18),
                    visualDensity: m3.VisualDensity.compact,
                    tooltip: context.l10n.serverJoin,
                  ),
                m3.IconButton(
                  onPressed: () => _delete(entry),
                  icon: const m3.Icon(ShellIcons.trash, size: 18),
                  visualDensity: m3.VisualDensity.compact,
                  tooltip: context.l10n.actionDelete,
                ),
                if (widget.kind == InstanceContentKind.resourcePacks) ...[
                  const m3.SizedBox(width: 4),
                  m3.Switch(
                    value: entry.enabled,
                    onChanged: (value) => _toggle(entry, value),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _emptyMessage(AppLocalizations l10n) => switch (widget.kind) {
    InstanceContentKind.resourcePacks => l10n.contentEmptyResourcePacks,
    InstanceContentKind.shaderPacks => l10n.contentEmptyShaderPacks,
    InstanceContentKind.worlds => l10n.contentEmptySaves,
    InstanceContentKind.servers => l10n.contentEmptyServers,
    _ => l10n.contentEmptyDataPacks,
  };

  static m3.IconData _iconFor(InstanceContentKind kind) => switch (kind) {
    InstanceContentKind.resourcePacks => ShellIcons.resourcePacks,
    InstanceContentKind.shaderPacks => ShellIcons.shaderPacks,
    InstanceContentKind.worlds => ShellIcons.saves,
    InstanceContentKind.servers => ShellIcons.network,
    _ => ShellIcons.folder,
  };
}

/// A data pack page needs a world before it can list anything.
class _WorldPicker extends ConsumerWidget {
  const _WorldPicker({
    required this.root,
    required this.world,
    required this.onChanged,
  });

  final String root;
  final String world;
  final void Function(String world) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saves = ref.read(gameContentProvider)(root).list(ContentKind.saves);

    return FutureBuilder<List<ContentEntry>>(
      future: saves,
      builder: (context, snapshot) {
        final worlds = snapshot.data ?? const <ContentEntry>[];
        return m3.Padding(
          padding: const m3.EdgeInsets.only(bottom: 8, left: 8),
          child: m3.Row(
            children: [
              m3.Text(l10n.catalogPickWorld, style: AppTheme.label(context)),
              const m3.SizedBox(width: 12),
              m3.DropdownButton<String>(
                key: const m3.ValueKey('datapack-world'),
                value: worlds.any((w) => w.name == world) ? world : null,
                hint: m3.Text(l10n.contentEmptySaves),
                items: [
                  for (final save in worlds)
                    m3.DropdownMenuItem(
                      value: save.name,
                      child: m3.Text(save.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The one form on the servers page: a name and an address.
///
/// A stateful dialog rather than two controllers beside the caller, so the fields are
/// disposed when the route is gone instead of while it is still animating out.
class _AddServerDialog extends StatefulWidget {
  const _AddServerDialog();

  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  final _name = m3.TextEditingController();
  final _address = m3.TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final ip = _address.text.trim();
    if (name.isEmpty || ip.isEmpty) return;
    m3.Navigator.of(context).pop((name: name, ip: ip));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return m3.AlertDialog(
      title: m3.Text(l10n.contentAddServer),
      content: m3.Column(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          m3.TextField(
            key: const m3.ValueKey('server-name'),
            controller: _name,
            autofocus: true,
            decoration: m3.InputDecoration(labelText: l10n.contentServerName),
          ),
          const m3.SizedBox(height: 8),
          m3.TextField(
            key: const m3.ValueKey('server-address'),
            controller: _address,
            decoration: m3.InputDecoration(
              labelText: l10n.contentServerAddress,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        m3.TextButton(
          onPressed: () => m3.Navigator.of(context).pop(),
          child: m3.Text(l10n.actionCancel),
        ),
        m3.TextButton(onPressed: _save, child: m3.Text(l10n.actionSave)),
      ],
    );
  }
}

/// Folder and catalogue mappings, kept as an extension so the enum above reads as a
/// list of pages rather than a switch table.
extension InstanceContentKindData on InstanceContentKind {
  /// The on-disk folder, except for servers (`servers.dat` sits in the game root).
  String get folderName => switch (this) {
    InstanceContentKind.mods => 'mods',
    InstanceContentKind.resourcePacks => 'resourcepacks',
    InstanceContentKind.shaderPacks => 'shaderpacks',
    InstanceContentKind.worlds => 'saves',
    InstanceContentKind.dataPacks => 'datapacks',
    InstanceContentKind.servers => '',
  };

  /// The same kind in the game-content layer; mods are scanned separately.
  ContentKind? get contentKind => switch (this) {
    InstanceContentKind.mods => null,
    InstanceContentKind.resourcePacks => ContentKind.resourcePacks,
    InstanceContentKind.shaderPacks => ContentKind.shaderPacks,
    InstanceContentKind.worlds => ContentKind.saves,
    InstanceContentKind.servers => ContentKind.servers,
    InstanceContentKind.dataPacks => ContentKind.datapacks,
  };

  /// The Modrinth catalogue this page installs from, when it has one.
  CatalogKind? get catalog => switch (this) {
    InstanceContentKind.mods => CatalogKind.mod,
    InstanceContentKind.resourcePacks => CatalogKind.resourcePack,
    InstanceContentKind.shaderPacks => CatalogKind.shader,
    InstanceContentKind.dataPacks => CatalogKind.datapack,
    // Worlds and servers are not catalogues: Modrinth has neither, and a server is
    // something you name, not download.
    InstanceContentKind.worlds || InstanceContentKind.servers => null,
  };
}

/// A server's answer, on the row it belongs to: a status dot, the MOTD, the players
/// and the round trip.
///
/// The row is a launcher's only chance to say "this server is up" - a name and an IP
/// without an answer is a bookmark, not a server list. A pending ping shows nothing
/// rather than a spinner per row: five rows of spinners is five things moving on a
/// page that has nothing to say yet.
class _ServerStatus extends ConsumerWidget {
  const _ServerStatus({required this.address});

  final String address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = m3.Theme.of(context).colorScheme;
    final ping = ref.watch(serverPingProvider(address));

    return ping.when(
      loading: () => m3.Text(
        address,
        style: AppTheme.caption(context)
            .copyWith(color: scheme.onSurfaceVariant),
        maxLines: 1,
        overflow: m3.TextOverflow.ellipsis,
      ),
      error: (error, _) => _line(context, scheme.error, '$error'),
      data: (result) {
        final status = result.status;
        final latency = status?.latencyMs;
        if (status == null) {
          return _line(
            context,
            scheme.onSurfaceVariant,
            [
              address,
              result.error ?? '',
            ].where((s) => s.isNotEmpty).join(' · '),
            dot: scheme.outline,
          );
        }
        return _line(
          context,
          scheme.onSurfaceVariant,
          [
            if (status.motd.isNotEmpty) status.motd,
            status.players,
            if (latency != null) '$latency ms',
            if (status.version != null) status.version!,
          ].join(' · '),
          dot: scheme.primary,
        );
      },
    );
  }

  Widget _line(
    BuildContext context,
    m3.Color color,
    String text, {
    m3.Color? dot,
  }) {
    return m3.Row(
      children: [
        if (dot != null) ...[
          // A 6 px dot, the way every server list marks reachability: small enough to
          // be a marker, present enough to answer "is it up" before reading the text.
          m3.Container(
            width: 6,
            height: 6,
            decoration: m3.BoxDecoration(color: dot, shape: m3.BoxShape.circle),
          ),
          const m3.SizedBox(width: 6),
        ],
        m3.Expanded(
          child: m3.Text(
            text,
            style: AppTheme.caption(context).copyWith(color: color),
            maxLines: 1,
            overflow: m3.TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
