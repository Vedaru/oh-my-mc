import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/game/content.dart';
import '../../core/instance/instance.dart';
import '../../core/mods/mod_scanner.dart';
import '../../data/launch_factory.dart';
import '../../data/mods_providers.dart';
import '../../data/modrinth_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'content_search_dialog.dart';
import 'content_screen.dart' show gameContentProvider;

/// 内容: everything installed in one instance, one kind at a time.
///
/// A single list with a kind filter rather than four separate screens: "what is in
/// this instance" is one question, and the answer differs only by the folder it comes
/// from. Each kind keeps its own verb (a mod and a resource pack can be turned off, a
/// world cannot), which is what the trailing slot shows.
class ContentBrowser extends ConsumerStatefulWidget {
  const ContentBrowser({
    required this.instance,
    this.initialKind = ContentKind.resourcePacks,
    super.key,
  });

  final Instance instance;
  final ContentKind initialKind;

  @override
  ConsumerState<ContentBrowser> createState() => _ContentBrowserState();
}

/// The kinds this browser lists. Datapacks are not here: they belong to a world, so
/// they are installed through a flow that asks which one, not browsed per instance.
enum BrowserKind { mods, resourcePacks, shaderPacks, datapacks }

class _ContentBrowserState extends ConsumerState<ContentBrowser> {
  late var _kind = switch (widget.initialKind) {
    ContentKind.resourcePacks => BrowserKind.mods,
    ContentKind.shaderPacks => BrowserKind.mods,
    ContentKind.saves => BrowserKind.mods,
    ContentKind.servers => BrowserKind.mods,
  };
  var _scanGeneration = 0;

  String get _root =>
      ref.read(launcherPathsProvider).gamePathsFor(widget.instance).root;

  CatalogKind get _catalog => switch (_kind) {
    BrowserKind.mods => CatalogKind.mod,
    BrowserKind.resourcePacks => CatalogKind.resourcePack,
    BrowserKind.shaderPacks => CatalogKind.shader,
    BrowserKind.datapacks => CatalogKind.datapack,
  };

  ContentKind get _contentKind => switch (_kind) {
    BrowserKind.mods => ContentKind.resourcePacks,
    BrowserKind.resourcePacks => ContentKind.resourcePacks,
    BrowserKind.shaderPacks => ContentKind.shaderPacks,
    // Unused: the datapack branch renders a hint, not a list. Kept total so the
    // switch cannot silently fall through if that changes.
    BrowserKind.datapacks => ContentKind.saves,
  };

  Future<void> _install() => showContentSearch(
    context: context,
    ref: ref,
    instance: widget.instance,
    kind: _catalog,
  );

  Future<void> _togglePack(ContentEntry entry, bool enabled) async {
    await ref
        .read(gameContentProvider)(_root)
        .setResourcePackEnabled(entry.name, enabled);
    if (mounted) setState(() => _scanGeneration++);
  }

  Future<void> _deletePack(ContentEntry entry) async {
    await ref.read(gameContentProvider)(_root).delete(_contentKind, entry.path);
    // The mod list is invalidated so switching back to it re-reads the folder.
    ref.invalidate(instanceModsProvider(widget.instance.id));
    if (mounted) setState(() => _scanGeneration++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Row(
          children: [
            m3.Expanded(
              child: m3.SingleChildScrollView(
                scrollDirection: m3.Axis.horizontal,
                child: m3.Row(
                  children: [
                    for (final kind in BrowserKind.values) ...[
                      _KindChip(
                        kind: kind,
                        selected: kind == _kind,
                        onPressed: () => setState(() => _kind = kind),
                      ),
                      const m3.SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
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
        ),
        const m3.SizedBox(height: 12),
        if (_kind == BrowserKind.mods)
          _ModList(instance: widget.instance)
        else if (_kind == BrowserKind.datapacks)
          _DataPacksHint(onInstall: _install)
        else
          _PackList(
            key: m3.ValueKey('packs-${_kind.name}-$_scanGeneration'),
            root: _root,
            kind: _contentKind,
            onToggle: _togglePack,
            onDelete: _deletePack,
          ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onPressed,
  });

  final BrowserKind kind;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final label = switch (kind) {
      BrowserKind.mods => l10n.catalogMods,
      BrowserKind.resourcePacks => l10n.catalogResourcePacks,
      BrowserKind.shaderPacks => l10n.catalogShaders,
      BrowserKind.datapacks => l10n.catalogDataPacks,
    };

    return m3.Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      borderRadius: m3.BorderRadius.circular(20),
      child: m3.InkWell(
        key: m3.ValueKey('content-kind-${kind.name}'),
        borderRadius: m3.BorderRadius.circular(20),
        onTap: onPressed,
        child: m3.Padding(
          padding: const m3.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: m3.Text(
            label,
            style: AppTheme.label(context).copyWith(
              color: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mods: the one kind with enable/disable, because a mod that is present but off is
/// still installed, and the game only reads `.jar`.
class _ModList extends ConsumerWidget {
  const _ModList({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mods = ref.watch(instanceModsProvider(instance.id));

    return mods.when(
      loading: () => const m3.Padding(
        padding: m3.EdgeInsets.symmetric(vertical: 24),
        child: m3.Center(child: m3.CircularProgressIndicator()),
      ),
      error: (error, _) => m3.SelectableText('$error'),
      data: (entries) {
        if (entries.isEmpty) {
          return m3.Padding(
            padding: const m3.EdgeInsets.symmetric(vertical: 24),
            child: m3.Text(l10n.contentEmptyResourcePacks),
          );
        }
        return m3.Column(
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
                      // The repository works on the entry: toggling is a rename of
                      // that one file, and the page re-reads the folder afterwards.
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

class _PackList extends ConsumerWidget {
  const _PackList({
    required this.root,
    required this.kind,
    required this.onToggle,
    required this.onDelete,
    super.key,
  });

  final String root;
  final ContentKind kind;
  final void Function(ContentEntry entry, bool enabled) onToggle;
  final void Function(ContentEntry entry) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final content = ref.read(gameContentProvider)(root);

    return FutureBuilder<List<ContentEntry>>(
      future: content.list(kind),
      builder: (context, snapshot) {
        final entries = snapshot.data;
        if (entries == null) {
          return const m3.Padding(
            padding: m3.EdgeInsets.symmetric(vertical: 24),
            child: m3.Center(child: m3.CircularProgressIndicator()),
          );
        }
        if (entries.isEmpty) {
          return m3.Padding(
            padding: const m3.EdgeInsets.symmetric(vertical: 24),
            child: m3.Text(switch (kind) {
              ContentKind.shaderPacks => l10n.contentEmptyShaderPacks,
              _ => l10n.contentEmptyResourcePacks,
            }),
          );
        }
        return m3.Column(
          children: [
            for (final entry in entries)
              ListRow(
                key: m3.ValueKey('pack-${entry.name}'),
                leadingIcon: kind == ContentKind.shaderPacks
                    ? ShellIcons.shaderPacks
                    : ShellIcons.resourcePacks,
                label: entry.name,
                supporting: formatContentSize(entry.sizeBytes),
                trailingControl: m3.Row(
                  mainAxisSize: m3.MainAxisSize.min,
                  children: [
                    // Only resource packs have a state the launcher can write.
                    if (kind == ContentKind.resourcePacks)
                      m3.Switch(
                        value: entry.enabled,
                        onChanged: (value) => onToggle(entry, value),
                      ),
                    m3.IconButton(
                      onPressed: () => onDelete(entry),
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
}

class _DataPacksHint extends StatelessWidget {
  const _DataPacksHint({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.Text(l10n.catalogNeedsWorld, style: AppTheme.body(context)),
        const m3.SizedBox(height: 8),
        AppButton(
          onPressed: onInstall,
          style: AppButtonStyle.outlined,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.contentInstall),
        ),
      ],
    );
  }
}

/// The instance page's tab row.
///
/// Text buttons with a selected surface rather than a `TabBar`: four tabs, no
/// scrolling, no indicator animation to keep in step with the page transition.
class DetailTabs extends StatelessWidget {
  const DetailTabs({
    required this.current,
    required this.onPick,
    required this.labels,
    super.key,
  });

  final int current;
  final void Function(int index) onPick;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Padding(
      padding: const m3.EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: m3.Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            m3.Material(
              color: i == current
                  ? scheme.secondaryContainer
                  : m3.Colors.transparent,
              borderRadius: m3.BorderRadius.circular(10),
              child: m3.InkWell(
                key: m3.ValueKey('detail-tab-$i'),
                borderRadius: m3.BorderRadius.circular(10),
                onTap: () => onPick(i),
                child: m3.Padding(
                  padding: const m3.EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: m3.Text(
                    labels[i],
                    style: AppTheme.label(context).copyWith(
                      color: i == current
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const m3.SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
