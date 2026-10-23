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
import '../components/app_button.dart';
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

  /// The row's five actions, in reading order.
  ///
  /// Every one goes through [_BarButton], the same widget with the same style: five
  /// buttons built by five separate `AppButton(...)` calls is how one of them ended up
  /// a text link with a wider optical gap than its neighbours.
  List<Widget> _buttons(AppLocalizations l10n, bool enabled) => [
    _BarButton(
      id: 'catalog-mod',
      icon: ShellIcons.mods,
      label: l10n.catalogMods,
      onPressed: enabled ? () => _open(CatalogKind.mod) : null,
    ),
    _BarButton(
      id: 'catalog-resourcePack',
      icon: ShellIcons.resourcePacks,
      label: l10n.catalogResourcePacks,
      onPressed: enabled ? () => _open(CatalogKind.resourcePack) : null,
    ),
    _BarButton(
      id: 'catalog-shader',
      icon: ShellIcons.shaderPacks,
      label: l10n.catalogShaders,
      onPressed: enabled ? () => _open(CatalogKind.shader) : null,
    ),
    _BarButton(
      id: 'catalog-datapack',
      icon: ShellIcons.saves,
      label: l10n.catalogDataPacks,
      onPressed: enabled ? () => _open(CatalogKind.datapack) : null,
    ),
    // Worlds and packs are files, not catalogues: Modrinth has no world directory, so
    // promising a search there would be a dead end. The button is the same pill as the
    // four catalogues - it is one more way to put content into an instance.
    _BarButton(
      id: 'catalog-import-world',
      icon: ShellIcons.saves,
      label: _importing ? l10n.catalogImporting : l10n.catalogImportWorld,
      onPressed: enabled ? _importWorld : null,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final instance = _target;
    final enabled = instance != null && !_importing;

    return m3.Padding(
      padding: const m3.EdgeInsets.only(bottom: 12),
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.start,
        children: [
          m3.Text(
            instance == null
                ? l10n.catalogNoTarget
                : l10n.catalogTarget(instance.name),
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const m3.SizedBox(height: 8),
          // One row, scrolling sideways on a narrow window: five buttons that wrap
          // onto a second line double the bar's height for no information gained.
          //
          // The gaps come from the loop, not from hand-placed `SizedBox`es between
          // them: a row of five buttons is exactly the place where one missing spacer
          // is invisible in code review and obvious on screen.
          m3.SingleChildScrollView(
            scrollDirection: m3.Axis.horizontal,
            child: m3.Row(
              children: [
                for (final (index, button) in _buttons(
                  l10n,
                  enabled,
                ).indexed) ...[
                  if (index > 0) const m3.SizedBox(width: 8),
                  button,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One pill in the content bar.
///
/// `id` is the widget key, not a catalogue: the world import is not a catalogue and
/// still belongs in this row, and it has to be built exactly like the four that are.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String id;
  final Object icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: m3.ValueKey(id),
      onPressed: onPressed,
      style: AppButtonStyle.outlined,
      size: AppButtonSize.sm,
      icon: m3.Icon(icon as m3.IconData, size: 14),
      label: m3.Text(label),
    );
  }
}
