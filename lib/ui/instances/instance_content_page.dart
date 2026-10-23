import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:path/path.dart' as p;

import '../../core/game/content.dart';
import '../../core/instance/instance.dart';
import '../../core/mods/mod_scanner.dart';
import '../../data/game_content_provider.dart';
import '../../data/launch_factory.dart';
import '../../data/mods_providers.dart';
import '../../data/modrinth_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/list_row.dart';
import '../components/open_folder.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'content_search_dialog.dart';

/// The six content pages.
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
/// **One page per kind**, the way Prism, MultiMC and PCL all do it
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
  /// Bumped after an install, so the list re-reads the folder the install wrote into.
  var _generation = 0;

  String get _root =>
      ref.read(launcherPathsProvider).gamePathsFor(widget.instance).root;

  Future<void> _install() async {
    final catalog = widget.kind.catalog;
    if (catalog == null) return;
    await showContentSearch(
      context: context,
      ref: ref,
      instance: widget.instance,
      kind: catalog,
    );
    if (mounted) setState(() => _generation++);
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

  Future<void> _openFolder() async {
    final target = widget.kind == InstanceContentKind.servers
        ? _root
        : p.join(_root, widget.kind.folderName);
    await openFolder(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasInstall = widget.kind.catalog != null;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Padding(
          // Same left inset as a `ListRow`, so the hint starts where the rows' text
          // starts instead of 8 px to its left.
          padding: const m3.EdgeInsets.only(bottom: 8, left: 8),
          child: m3.Row(
            children: [
              m3.Expanded(
                child: m3.Text(
                  _hint(l10n),
                  style: AppTheme.caption(context).copyWith(
                    color: m3.Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const m3.SizedBox(width: 12),
              AppButton(
                key: const m3.ValueKey('content-open-folder'),
                onPressed: _openFolder,
                style: AppButtonStyle.text,
                size: AppButtonSize.sm,
                icon: const m3.Icon(ShellIcons.folder, size: 14),
                label: m3.Text(l10n.instanceOpenFolderTooltip),
              ),
              if (widget.kind == InstanceContentKind.servers) ...[
                const m3.SizedBox(width: 8),
                AppButton(
                  key: const m3.ValueKey('content-add-server'),
                  onPressed: () => _addServer(),
                  style: AppButtonStyle.filled,
                  size: AppButtonSize.sm,
                  icon: const m3.Icon(ShellIcons.add, size: 14),
                  label: m3.Text(l10n.contentAddServer),
                ),
              ],
              if (hasInstall) ...[
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
        ),
        m3.Expanded(
          child: switch (widget.kind) {
            InstanceContentKind.mods => _ModList(
              key: m3.ValueKey('mods-$_generation'),
              instance: widget.instance,
            ),
            _ => _GameContentPage(
              key: m3.ValueKey('${widget.kind.name}-$_generation'),
              root: _root,
              kind: widget.kind,
            ),
          },
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
class _ModList extends ConsumerWidget {
  const _ModList({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mods = ref.watch(instanceModsProvider(instance.id));

    return mods.when(
      loading: () => const m3.Center(child: m3.CircularProgressIndicator()),
      error: (error, _) => m3.SelectableText('$error'),
      data: (entries) {
        if (entries.isEmpty) {
          return _Empty(message: l10n.contentEmptyMods);
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
                trailingControl: m3.Row(
                  mainAxisSize: m3.MainAxisSize.min,
                  children: [
                    m3.Switch(
                      value: mod.enabled,
                      onChanged: (value) async {
                        await ref
                            .read(modsRepositoryProvider)
                            .setEnabled(mod, value);
                        ref.invalidate(instanceModsProvider(instance.id));
                      },
                    ),
                    m3.IconButton(
                      onPressed: () async {
                        await ref.read(modsRepositoryProvider).delete(mod);
                        ref.invalidate(instanceModsProvider(instance.id));
                      },
                      icon: const m3.Icon(ShellIcons.trash, size: 16),
                      tooltip: l10n.actionDelete,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static String _supporting(ModEntry mod) => [
    if (mod.version != null) mod.version!,
    mod.loader.label,
    formatContentSize(mod.sizeBytes),
  ].join(' · ');
}

/// Resource packs, shaders, worlds and servers, read through `GameContent`.
///
/// Stateful, not a `FutureBuilder` over a fresh future per build: after a toggle or a
/// delete the list must be re-read from disk, and a rebuilt `FutureBuilder` would
/// either show the stale result or flash a spinner on every frame.
class _GameContentPage extends ConsumerStatefulWidget {
  const _GameContentPage({required this.root, required this.kind, super.key});

  final String root;
  final InstanceContentKind kind;

  @override
  ConsumerState<_GameContentPage> createState() => _GameContentPageState();
}

class _GameContentPageState extends ConsumerState<_GameContentPage> {
  List<ContentEntry>? _entries;

  /// The world a data pack page is pointed at. Empty until the worlds are read.
  var _world = '';

  ContentKind get _contentKind => widget.kind.contentKind!;

  /// `GameContent` takes the root the folder lives under: the game root for
  /// `resourcepacks/` and friends, the world directory for `datapacks/`.
  GameContent get _content => ref.read(gameContentProvider)(
    widget.kind == InstanceContentKind.dataPacks
        ? p.join(widget.root, 'saves', _world)
        : widget.root,
  );

  @override
  void initState() {
    super.initState();
    if (widget.kind == InstanceContentKind.dataPacks) _pickInitialWorld();
    _load();
  }

  Future<void> _pickInitialWorld() async {
    final saves = await ref
        .read(gameContentProvider)(widget.root)
        .list(ContentKind.saves);
    if (!mounted || saves.isEmpty) return;
    setState(() => _world = saves.first.name);
    await _load();
  }

  Future<void> _load() async {
    if (widget.kind == InstanceContentKind.dataPacks && _world.isEmpty) {
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
      return _Empty(message: _emptyMessage(context.l10n));
    }

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        if (widget.kind == InstanceContentKind.dataPacks)
          _WorldPicker(
            root: widget.root,
            world: _world,
            onChanged: (world) async {
              setState(() {
                _world = world;
                _entries = null;
              });
              await _load();
            },
          ),
        m3.Expanded(
          child: m3.ListView(
            padding: m3.EdgeInsets.zero,
            children: [
              for (final entry in entries)
                ListRow(
                  key: m3.ValueKey('content-${entry.name}'),
                  leadingIcon: _iconFor(widget.kind),
                  label: entry.name,
                  supporting: [
                    entry.detail,
                    formatContentSize(entry.sizeBytes),
                  ].whereType<String>().join(' · '),
                  trailingControl: m3.Row(
                    mainAxisSize: m3.MainAxisSize.min,
                    children: [
                      // Only a resource pack has a state the launcher can write: Iris
                      // keeps the active shader in its own config, and a world or a
                      // server has no "off".
                      if (widget.kind == InstanceContentKind.resourcePacks)
                        m3.Switch(
                          value: entry.enabled,
                          onChanged: (value) => _toggle(entry, value),
                        ),
                      m3.IconButton(
                        onPressed: () => _delete(entry),
                        icon: const m3.Icon(ShellIcons.trash, size: 16),
                        tooltip: context.l10n.actionDelete,
                      ),
                    ],
                  ),
                ),
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
          padding: const m3.EdgeInsets.only(bottom: 8),
          child: m3.Row(
            children: [
              m3.Text(l10n.catalogPickWorld, style: AppTheme.label(context)),
              const m3.SizedBox(width: 12),
              m3.DropdownButton<String>(
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

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return m3.Padding(
      padding: const m3.EdgeInsets.symmetric(vertical: 32),
      child: m3.Text(
        message,
        style: AppTheme.body(context)
            .copyWith(color: m3.Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The kind → folder/catalogue mapping, kept in the page file's header so the enum
/// reads as data rather than as a second switch statement.
extension InstanceContentKindData on InstanceContentKind {
  String get folder => folderName;

  String get folderName => switch (this) {
    InstanceContentKind.mods => 'mods',
    InstanceContentKind.resourcePacks => 'resourcepacks',
    InstanceContentKind.shaderPacks => 'shaderpacks',
    InstanceContentKind.worlds => 'saves',
    InstanceContentKind.dataPacks => 'datapacks',
    InstanceContentKind.servers => '',
  };

  ContentKind? get contentKind => switch (this) {
    InstanceContentKind.mods => null,
    InstanceContentKind.resourcePacks => ContentKind.resourcePacks,
    InstanceContentKind.shaderPacks => ContentKind.shaderPacks,
    InstanceContentKind.worlds => ContentKind.saves,
    InstanceContentKind.servers => ContentKind.servers,
    InstanceContentKind.dataPacks => ContentKind.datapacks,
  };

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
