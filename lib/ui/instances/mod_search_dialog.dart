import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/instance/instance.dart';
import '../../core/mods/mc_target.dart';
import '../../core/mods/modrinth.dart';
import '../../data/launch_factory.dart';
import '../../data/mods_providers.dart';
import '../../data/modrinth_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../motion/tokens.dart';
import '../components/app_dialog.dart';
import '../components/app_text_field.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 获取模组: search Modrinth for the instance's game version and loader, install
/// with dependencies.
///
/// A dialog rather than a page because it is a detour: the user comes back to the
/// mod list it fills. The filters are not exposed as controls on purpose - they
/// come from the instance, and letting the user also pick a game version would
/// produce a list of mods that cannot load here.
class ModSearchDialog extends ConsumerStatefulWidget {
  const ModSearchDialog({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<ModSearchDialog> createState() => _ModSearchDialogState();
}

class _ModSearchDialogState extends ConsumerState<ModSearchDialog> {
  final _text = m3.TextEditingController();
  late final McTarget? _target = McTarget.fromInstance(widget.instance);
  late ModSearchQuery _query = _queryFor('');

  // Per-project install state: a row can be downloading while the others sit
  // still, and a failed one has to keep its reason visible.
  final _busy = <String>{};
  final _done = <String>{};
  final _errors = <String, String>{};

  ModSearchQuery _queryFor(String text) => ModSearchQuery(
    text: text,
    gameVersion: _target?.gameVersion ?? '',
    loader: _target?.loader,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _install(ModrinthProject project) async {
    final target = _target;
    if (target == null) return;

    setState(() {
      _busy.add(project.id);
      _errors.remove(project.id);
    });

    try {
      final paths = ref.read(launcherPathsProvider);
      final outcome = await ref.read(modInstallActionProvider)(
        ModInstallRequest(
          project: project,
          gameVersion: target.gameVersion,
          loader: target.loader,
          modsDir: Directory(modsDirFor(paths, widget.instance)),
        ),
      );
      // The mod list is the point of the dialog: refresh it now, not on close.
      ref.invalidate(instanceModsProvider(widget.instance.id));
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
    final results = ref.watch(modSearchProvider(_query));

    return AppDialog(
      title: l10n.modsSearchTitle,
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
            // What the search is filtered by is stated, not configured: these come
            // from the instance.
            m3.Text(
              target == null || !target.isModded
                  ? l10n.modsSearchNeedsLoader
                  : l10n.modsSearchFiltered(target.loader!, target.gameVersion),
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const m3.SizedBox(height: 12),
            // No field for a vanilla instance: a search box that can only return
            // unloadable mods is a control that lies about what it does.
            if (target != null && target.isModded)
              AppTextField(
                key: const m3.ValueKey('mods-search'),
                controller: _text,
                autofocus: true,
                hint: l10n.modsSearchHint,
                leading: const m3.Icon(ShellIcons.search, size: 15),
                onSubmitted: (text) => setState(() => _query = _queryFor(text)),
                onChanged: (text) {
                  // Search on a pause, not on every keystroke: the API is rate
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
              child: target == null || !target.isModded
                  ? m3.Padding(
                      padding: const m3.EdgeInsets.symmetric(vertical: 24),
                      child: m3.Text(
                        l10n.modsSearchVanillaHint,
                        style: AppTheme.body(context),
                      ),
                    )
                  : results.when(
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
                              padding: const m3.EdgeInsets.symmetric(
                                vertical: 24,
                              ),
                              child: m3.Text(
                                l10n.modsSearchEmpty,
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
                                    key: m3.ValueKey('mods-result-${hit.id}'),
                                    leadingIcon: ShellIcons.mods,
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
                                        ? const m3.Icon(
                                            ShellIcons.check,
                                            size: 16,
                                          )
                                        : AppButton(
                                            onPressed: () => _install(hit),
                                            style: AppButtonStyle.text,
                                            size: AppButtonSize.sm,
                                            label: m3.Text(l10n.modsInstall),
                                          ),
                                    errorText: _errors[hit.id],
                                  ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
