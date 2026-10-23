import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/game/content.dart';
import '../../core/instance/instance.dart';
import '../../core/mods/mc_target.dart';
import '../../core/mods/modrinth.dart';
import '../../data/mods_providers.dart';
import '../../data/launch_factory.dart';
import '../../data/modrinth_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/app_text_field.dart';
import '../components/list_row.dart';
import '../motion/tokens.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 下载 → 模组 / 资源包 / 光影 / 数据包: search Modrinth for what this instance can
/// actually load, and install it with its dependencies.
///
/// A dialog rather than a page because it is a detour: the user comes back to the
/// list it fills. The filters are not controls on purpose - they come from the
/// instance, and letting the user also pick a game version would produce a list of
/// files that cannot load here.
class ContentSearchDialog extends ConsumerStatefulWidget {
  const ContentSearchDialog({
    required this.instance,
    required this.kind,
    this.world,
    super.key,
  });

  final Instance instance;
  final CatalogKind kind;

  /// The world a datapack installs into. Required for [CatalogKind.datapack].
  final String? world;

  @override
  ConsumerState<ContentSearchDialog> createState() =>
      _ContentSearchDialogState();
}

class _ContentSearchDialogState extends ConsumerState<ContentSearchDialog> {
  final _text = m3.TextEditingController();
  late final McTarget? _target = McTarget.fromInstance(widget.instance);
  late ContentSearchQuery _query = _queryFor('');

  /// Per-project install state: a row can be downloading while the others sit
  /// still, and a failed one has to keep its reason visible.
  final _busy = <String>{};
  final _done = <String>{};
  final _errors = <String, String>{};

  ContentSearchQuery _queryFor(String text) => ContentSearchQuery(
    text: text,
    kind: widget.kind,
    gameVersion: _target?.gameVersion ?? '',
    loader: widget.kind == CatalogKind.mod ? _target?.loader : null,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _needsLoader =>
      widget.kind == CatalogKind.mod && (_target?.isModded ?? false) == false;

  Future<void> _install(ModrinthProject project) async {
    final target = _target;
    if (target == null) return;

    final paths = ref.read(launcherPathsProvider);
    final directory = widget.kind.targetFor(
      widget.instance,
      paths,
      world: widget.world,
    );
    if (directory == null) return;

    setState(() {
      _busy.add(project.id);
      _errors.remove(project.id);
    });

    try {
      final outcome = await ref.read(contentInstallActionProvider)(
        ContentInstallRequest(
          project: project,
          kind: widget.kind,
          gameVersion: target.gameVersion,
          loader: widget.kind == CatalogKind.mod ? target.loader : null,
          target: directory,
          // A resource pack nobody turned on is a download the user has to finish
          // in a menu the game does not show them.
          enablePack: widget.kind == CatalogKind.resourcePack,
        ),
      );
      // The list behind the dialog is the point: refresh it now, not on close.
      if (widget.kind == CatalogKind.mod) {
        ref.invalidate(instanceModsProvider(widget.instance.id));
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(project.id);
        if (outcome.isClean) {
          _done.add(project.id);
        } else {
          _errors[project.id] = outcome.failed.values.first;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy.remove(project.id);
        _errors[project.id] = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final target = _target;
    final results = ref.watch(contentSearchProvider(_query));

    // A datapack has nowhere to go without a world, and a mod has nowhere to go on
    // vanilla: both are stated instead of showing a search that cannot deliver.
    final blocked =
        _needsLoader ||
        (widget.kind == CatalogKind.datapack && widget.world == null);

    return AppDialog(
      title: _kindName(l10n),
      actions: [
        AppButton(
          onPressed: () => m3.Navigator.of(context).pop(),
          style: AppButtonStyle.text,
          label: m3.Text(l10n.actionClose),
        ),
      ],
      content: m3.SizedBox(
        width: 520,
        child: m3.Column(
          mainAxisSize: m3.MainAxisSize.min,
          crossAxisAlignment: m3.CrossAxisAlignment.stretch,
          children: [
            m3.Text(
              _filterLine(l10n, target),
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const m3.SizedBox(height: 12),
            if (blocked)
              m3.Padding(
                padding: const m3.EdgeInsets.symmetric(vertical: 24),
                child: m3.Text(
                  widget.kind == CatalogKind.datapack
                      ? l10n.catalogNeedsWorld
                      : l10n.catalogNeedsLoader,
                  style: AppTheme.body(context),
                ),
              )
            else ...[
              AppTextField(
                key: const m3.ValueKey('content-search'),
                controller: _text,
                autofocus: true,
                hint: l10n.catalogSearchHint,
                leading: const m3.Icon(ShellIcons.search, size: 15),
                onSubmitted: (text) => setState(() => _query = _queryFor(text)),
                onChanged: (text) {
                  // Search after a pause, not on every keystroke: the API is rate
                  // limited and a one-letter query matches the whole site.
                  Future<void>.delayed(Durations.debounce, () {
                    if (!mounted || _text.text != text) return;
                    setState(() => _query = _queryFor(text));
                  });
                },
              ),
              const m3.SizedBox(height: 12),
              m3.ConstrainedBox(
                constraints: const m3.BoxConstraints(maxHeight: 380),
                child: results.when(
                  loading: () => const m3.Padding(
                    padding: m3.EdgeInsets.symmetric(vertical: 24),
                    child: m3.Center(child: m3.CircularProgressIndicator()),
                  ),
                  error: (error, _) => m3.Padding(
                    padding: const m3.EdgeInsets.symmetric(vertical: 24),
                    child: m3.SelectableText('$error'),
                  ),
                  data: (hits) => hits.isEmpty
                      ? m3.Padding(
                          padding: const m3.EdgeInsets.symmetric(vertical: 24),
                          child: m3.Text(
                            l10n.catalogEmpty,
                            style: AppTheme.body(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : m3.ListView(
                          shrinkWrap: true,
                          padding: m3.EdgeInsets.zero,
                          children: [
                            for (final hit in hits)
                              ListRow(
                                key: m3.ValueKey('catalog-result-${hit.id}'),
                                leadingIcon: _icon,
                                label: hit.title,
                                supporting: hit.description,
                                trailingControl: _busy.contains(hit.id)
                                    ? const m3.SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: m3.CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : _done.contains(hit.id)
                                    ? const m3.Icon(ShellIcons.check, size: 16)
                                    : AppButton(
                                        onPressed: () => _install(hit),
                                        style: AppButtonStyle.text,
                                        size: AppButtonSize.sm,
                                        label: m3.Text(l10n.catalogInstall),
                                      ),
                                errorText: _errors[hit.id],
                              ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// What the search is filtered by, stated rather than configured.
  String _filterLine(AppLocalizations l10n, McTarget? target) {
    if (target == null) return l10n.catalogUnknownVersion;
    if (widget.kind == CatalogKind.datapack) {
      return l10n.catalogFilteredGame(target.gameVersion);
    }
    if (widget.kind == CatalogKind.mod) {
      return target.loader == null
          ? l10n.catalogFilteredGame(target.gameVersion)
          : l10n.catalogFilteredLoader(target.loader!, target.gameVersion);
    }
    // Resource packs and shaders are not built for a loader.
    return l10n.catalogFilteredGame(target.gameVersion);
  }

  String _kindName(AppLocalizations l10n) => switch (widget.kind) {
    CatalogKind.mod => l10n.catalogMods,
    CatalogKind.resourcePack => l10n.catalogResourcePacks,
    CatalogKind.shader => l10n.catalogShaders,
    CatalogKind.datapack => l10n.catalogDataPacks,
  };

  m3.IconData get _icon => switch (widget.kind) {
    CatalogKind.mod => ShellIcons.mods,
    CatalogKind.resourcePack => ShellIcons.resourcePacks,
    CatalogKind.shader => ShellIcons.shaderPacks,
    CatalogKind.datapack => ShellIcons.saves,
  };
}

/// Opens the dialog for [kind], resolving the paths it needs.
Future<void> showContentSearch({
  required BuildContext context,
  required WidgetRef ref,
  required Instance instance,
  required CatalogKind kind,
  String? world,
}) async {
  if (kind == CatalogKind.datapack && world == null) {
    // A datapack is per world, so the world is the first question, not a detail of
    // where the files go.
    final root = ref.read(launcherPathsProvider).gamePathsFor(instance).root;
    final saves = await GameContent(root).list(ContentKind.saves);
    if (!context.mounted) return;
    if (saves.isEmpty) {
      await m3.showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: context.l10n.catalogDataPacks,
          content: m3.Text(context.l10n.catalogNeedsWorld),
          actions: [
            AppButton(
              onPressed: () => m3.Navigator.of(context).pop(),
              style: AppButtonStyle.text,
              label: m3.Text(context.l10n.actionClose),
            ),
          ],
        ),
      );
      return;
    }
    world = await m3.showDialog<String>(
      context: context,
      builder: (context) => _WorldPickerDialog(saves: saves),
    );
    if (world == null || !context.mounted) return;
  }

  await m3.showDialog<void>(
    context: context,
    builder: (context) =>
        ContentSearchDialog(instance: instance, kind: kind, world: world),
  );
}

/// Picks the world a datapack goes into.
class _WorldPickerDialog extends StatelessWidget {
  const _WorldPickerDialog({required this.saves});

  final List<ContentEntry> saves;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.catalogPickWorld,
      content: m3.SizedBox(
        width: 360,
        child: m3.ConstrainedBox(
          constraints: const m3.BoxConstraints(maxHeight: 320),
          child: m3.ListView(
            shrinkWrap: true,
            padding: m3.EdgeInsets.zero,
            children: [
              for (final save in saves)
                ListRow(
                  key: m3.ValueKey('world-${save.name}'),
                  leadingIcon: ShellIcons.saves,
                  label: save.name,
                  supporting: save.detail ?? '',
                  onPressed: () => m3.Navigator.of(context).pop(save.name),
                ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          onPressed: () => m3.Navigator.of(context).pop(),
          style: AppButtonStyle.text,
          label: m3.Text(l10n.actionCancel),
        ),
      ],
    );
  }
}
