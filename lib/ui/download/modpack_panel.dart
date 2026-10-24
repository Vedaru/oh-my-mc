import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/mods/modrinth.dart';
import '../../core/packs/modpack_install.dart';
import '../../data/modpack_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/catalog_list.dart';
import '../components/action_card.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 下载 → 整合包: Modrinth's modpack catalogue, installed as a new instance.
///
/// It is a sibling of the version list rather than another kind of content install,
/// because it does something the others do not: a pack brings its own Minecraft version
/// and loader, so installing one *creates an instance* instead of filling a folder in an
/// existing one.
class ModpackPanel extends ConsumerStatefulWidget {
  const ModpackPanel({super.key});

  @override
  ConsumerState<ModpackPanel> createState() => _ModpackPanelState();
}

class _ModpackPanelState extends ConsumerState<ModpackPanel> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = ref.watch(modpackSearchProvider(_query));

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        // The search is the first row of every pane and sits at the same height in all
        // of them: it is the control the hand goes to after the tab, so it must not move.
        m3.SizedBox(
          // 48, not 40: the version pane's first row is a search field beside a
          // segmented control, and that row is 48 tall. Every pane's first row has to be
          // the same height or the content below the switch still shifts by 8 px.
          height: 48,
          child: DebouncedSearchField(
            fieldKey: const m3.ValueKey('modpack-search'),
            hint: l10n.modpackSearchHint,
            onQuery: (text) => setState(() => _query = text),
          ),
        ),
        const m3.SizedBox(height: 12),
        // The explanation sits *below* the search: it can wrap to two lines without
        // pushing the control the user is about to use.
        m3.Text(
          l10n.modpackHint,
          style: AppTheme.caption(
            context,
          ).copyWith(color: m3.Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const m3.SizedBox(height: 12),
        m3.Expanded(
          child: CatalogList<ModrinthProject>(
            results: results,
            emptyText: l10n.catalogEmpty,
            maxHeight: double.infinity,
            wrap: true,
            rowBuilder: (context, project) => ActionCard(
              key: m3.ValueKey('modpack-result-${project.id}'),
              icon: ShellIcons.mods,
              title: project.title,
              // The download count is the only quality signal Modrinth gives that a
              // reader can use at a glance; the description alone makes a 12-download
              // pack look like a 1.2-million one.
              subtitle: [
                if (project.downloads > 0) _downloads(project.downloads),
                project.description,
              ].where((part) => part.isNotEmpty).join(' · '),
              actionLabel: l10n.modpackVersions,
              onPressed: () => ModpackVersionDialog.show(context, project),
            ),
          ),
        ),
      ],
    );
  }
}

/// `1200000` -> `1.2M downloads`. The catalogue is sorted by relevance, not popularity,
/// so the number is what tells the two apart.
String _downloads(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M downloads';
  }
  if (count >= 1000) return '${(count / 1000).round()}k downloads';
  return '$count downloads';
}

/// Pick a pack version, name the instance, watch it install.
///
/// One dialog with three states rather than three dialogs: each state is the only thing
/// that can happen next, and the pack's name is the default instance name, so the user can
/// get from "this looks good" to playing with two clicks.
class ModpackVersionDialog extends ConsumerStatefulWidget {
  const ModpackVersionDialog({required this.project, super.key});

  final ModrinthProject project;

  static Future<void> show(BuildContext context, ModrinthProject project) =>
      m3.showDialog<void>(
        context: context,
        builder: (_) => ModpackVersionDialog(project: project),
      );

  @override
  ConsumerState<ModpackVersionDialog> createState() =>
      _ModpackVersionDialogState();
}

class _ModpackVersionDialogState extends ConsumerState<ModpackVersionDialog> {
  ModrinthVersion? _chosen;
  String? _step;
  String? _error;
  ModpackInstallResult? _done;
  var _running = false;

  Future<void> _install(ModrinthVersion version) async {
    setState(() {
      _chosen = version;
      _running = true;
      _error = null;
      _step = context.l10n.modpackStarting;
    });
    try {
      final result = await ref
          .read(modpackInstallerProvider)
          .install(
            project: widget.project,
            version: version,
            name: widget.project.title,
            onProgress: (step, detail) {
              if (!mounted) return;
              setState(() => _step = '${_stepLabel(step)}: $detail');
            },
          );
      if (!mounted) return;
      setState(() {
        _done = result;
        _running = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _running = false;
      });
    }
  }

  String _stepLabel(ModpackStep step) => switch (step) {
    ModpackStep.download => context.l10n.modpackStepDownload,
    ModpackStep.install => context.l10n.modpackStepInstall,
    ModpackStep.create => context.l10n.modpackStepCreate,
    ModpackStep.import => context.l10n.modpackStepImport,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    return AppDialog(
      title: widget.project.title,
      actions: [
        AppButton(
          onPressed: () => m3.Navigator.of(context).pop(),
          style: AppButtonStyle.text,
          label: m3.Text(_done == null ? l10n.actionCancel : l10n.actionClose),
        ),
      ],
      content: m3.SizedBox(
        width: 520,
        child: switch ((_done, _error, _running)) {
          // Finished: say what happened, including the files that did not arrive.
          (final ModpackInstallResult result, _, _) => m3.Column(
            mainAxisSize: m3.MainAxisSize.min,
            crossAxisAlignment: m3.CrossAxisAlignment.start,
            children: [
              m3.Text(l10n.modpackDone, style: AppTheme.body(context)),
              if (result.failed.isNotEmpty) ...[
                const m3.SizedBox(height: 8),
                m3.SelectableText(
                  l10n.modpackSomeFailed(result.failed.length),
                  style: AppTheme.caption(context)
                      .copyWith(color: scheme.error),
                ),
              ],
            ],
          ),
          (_, final String error, _) => m3.SelectableText(
            error,
            style: AppTheme.body(context).copyWith(color: scheme.error),
          ),
          (_, _, true) => m3.Row(
            children: [
              const m3.SizedBox(
                width: 16,
                height: 16,
                child: m3.CircularProgressIndicator(strokeWidth: 2),
              ),
              const m3.SizedBox(width: 12),
              m3.Expanded(
                child: m3.Text(_step ?? '', style: AppTheme.body(context)),
              ),
            ],
          ),
          _ => _VersionPicker(
            project: widget.project,
            onInstall: _install,
            busy: _chosen != null && _running,
          ),
        },
      ),
    );
  }
}

class _VersionPicker extends ConsumerWidget {
  const _VersionPicker({
    required this.project,
    required this.onInstall,
    required this.busy,
  });

  final ModrinthProject project;
  final void Function(ModrinthVersion version) onInstall;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final versions = ref.watch(modpackVersionsProvider(project.id));

    return m3.Column(
      mainAxisSize: m3.MainAxisSize.min,
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        if (project.description.isNotEmpty)
          m3.Padding(
            padding: const m3.EdgeInsets.only(bottom: 8),
            child: m3.Text(
              project.description,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        CatalogList<ModrinthVersion>(
          results: versions,
          emptyText: l10n.modpackNoVersions,
          maxHeight: 360,
          rowBuilder: (context, version) => ListRow(
            key: m3.ValueKey('modpack-version-${version.id}'),
            leadingIcon: ShellIcons.download,
            label: version.name.isEmpty ? version.versionNumber : version.name,
            // The pack decides which game version it is for, so it is information here
            // rather than a filter.
            supporting: [
              version.versionNumber,
              ...version.gameVersions,
              if (version.files.isNotEmpty) _sizeOf(version),
            ].join(' · '),
            trailingControl: AppButton(
              key: m3.ValueKey('modpack-install-${version.id}'),
              onPressed: busy ? null : () => onInstall(version),
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              label: m3.Text(l10n.modpackInstall),
            ),
          ),
        ),
      ],
    );
  }

  static String _sizeOf(ModrinthVersion version) {
    final bytes = version.primaryFile?.sizeBytes ?? 0;
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}
