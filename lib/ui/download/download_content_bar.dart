import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:path/path.dart' as p;

import '../../core/game/world_import.dart';
import '../../core/instance/instance.dart';
import '../../data/instance_providers.dart';
import '../../data/launch_factory.dart';
import '../../data/modrinth_providers.dart';
import '../../l10n/l10n.dart';
import '../components/action_card.dart';
import '../instances/content_search_dialog.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 下载 → 内容: the catalogues that are not game versions.
///
/// Every one of them needs a *destination* - a mod goes into an instance's `mods/`,
/// a data pack into one of its worlds - which is why this bar shows the target
/// instance instead of hiding the choice: a download button that silently picks an
/// instance is a download into the wrong place.
class DownloadContentBar extends ConsumerStatefulWidget {
  const DownloadContentBar({super.key});

  @override
  ConsumerState<DownloadContentBar> createState() => _DownloadContentBarState();
}

class _DownloadContentBarState extends ConsumerState<DownloadContentBar> {
  var _importing = false;

  Instance? get _target {
    final state = ref.watch(instanceListProvider);
    if (state is! InstanceListReady) return null;
    final selected = state.selectedId;
    if (selected == null) return null;
    return state.instances.where((i) => i.id == selected).firstOrNull;
  }

  Future<void> _open(CatalogKind kind) async {
    final instance = _target;
    if (instance == null) return;
    await showContentSearch(
      context: context,
      ref: ref,
      instance: instance,
      kind: kind,
    );
  }

  /// A world zip is not a catalogue: there is no platform to search, just a file.
  Future<void> _importWorld() async {
    final instance = _target;
    if (instance == null) return;
    final l10n = context.l10n;
    final messenger = m3.ScaffoldMessenger.maybeOf(context);

    final picked = await FilePicker.pickFiles(
      dialogTitle: l10n.catalogImportWorld,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null || !mounted) return;

    setState(() => _importing = true);
    try {
      final paths = ref.read(launcherPathsProvider);
      final root = paths.gamePathsFor(instance).root;
      final result = await const WorldImporter().importZip(
        File(path),
        savesDir: Directory(p.join(root, 'saves')),
      );
      if (!mounted) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(
              l10n.catalogWorldImported(p.basename(result.path)),
            ),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    } on Object catch (e) {
      if (!mounted) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          m3.SnackBar(
            content: m3.Text(l10n.catalogWorldImportFailed('$e')),
            behavior: m3.SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// The five actions, in reading order, each with the sentence that makes it usable.
  ///
  /// Every card comes from one list through one widget: five separate cards built by
  /// hand is how one of them ended up with a different weight, a wider gap, or no
  /// explanation at all.
  List<Widget> _cards(AppLocalizations l10n, bool enabled) => [
    ActionCard(
      key: const m3.ValueKey('catalog-mod'),
      icon: ShellIcons.mods,
      title: l10n.catalogMods,
      subtitle: l10n.catalogModsBlurb,
      actionLabel: l10n.catalogBrowse,
      onPressed: enabled ? () => _open(CatalogKind.mod) : null,
    ),
    ActionCard(
      key: const m3.ValueKey('catalog-resourcePack'),
      icon: ShellIcons.resourcePacks,
      title: l10n.catalogResourcePacks,
      subtitle: l10n.catalogResourcePacksBlurb,
      actionLabel: l10n.catalogBrowse,
      onPressed: enabled ? () => _open(CatalogKind.resourcePack) : null,
    ),
    ActionCard(
      key: const m3.ValueKey('catalog-shader'),
      icon: ShellIcons.shaderPacks,
      title: l10n.catalogShaders,
      subtitle: l10n.catalogShadersBlurb,
      actionLabel: l10n.catalogBrowse,
      onPressed: enabled ? () => _open(CatalogKind.shader) : null,
    ),
    ActionCard(
      key: const m3.ValueKey('catalog-datapack'),
      icon: ShellIcons.saves,
      title: l10n.catalogDataPacks,
      subtitle: l10n.catalogDataPacksBlurb,
      actionLabel: l10n.catalogBrowse,
      onPressed: enabled ? () => _open(CatalogKind.datapack) : null,
    ),
    // Worlds and packs are files, not catalogues: Modrinth has no world directory, so
    // promising a search there would be a dead end. Same card, because it is one more
    // way to put content into an instance.
    ActionCard(
      key: const m3.ValueKey('catalog-import-world'),
      icon: ShellIcons.folder,
      title: _importing ? l10n.catalogImporting : l10n.catalogImportWorld,
      subtitle: l10n.catalogImportWorldBlurb,
      // "Browse" would promise a catalogue; this one opens a file picker.
      actionLabel: l10n.catalogChooseFile,
      onPressed: enabled ? _importWorld : null,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final instance = _target;
    final enabled = instance != null && !_importing;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        // The other two panes start with a 48 px search row; this one has no search, so
        // its single line occupies that row instead of sitting 24 px higher than theirs.
        m3.SizedBox(
          key: const m3.ValueKey('content-target-row'),
          height: 48,
          child: m3.Align(
            alignment: m3.Alignment.centerLeft,
            child: m3.Text(
              instance == null
                  ? l10n.catalogNoTarget
                  : l10n.catalogTarget(instance.name),
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        const m3.SizedBox(height: 12),
        // A grid, not a row: five cards at their natural width fill a 1440 px window
        // and wrap to two or three columns on a narrow one, instead of five pills in a
        // line above an empty page.
        m3.Wrap(spacing: 12, runSpacing: 12, children: _cards(l10n, enabled)),
      ],
    );
  }
}
