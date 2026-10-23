import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../core/mods/mod_scanner.dart';
import '../../core/mods/mc_target.dart';
import '../../core/net/progress.dart' show formatBytes;
import '../../data/instance_providers.dart';
import '../../data/launch_factory.dart';
import '../../data/mods_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/app_switch.dart';
import '../components/app_text_field.dart';
import '../components/list_row.dart';
import '../components/page_body.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'mod_search_dialog.dart';

/// 版本设置 → Mod 管理: the instance's `mods/` folder as a list.
///
/// The list is the whole feature: what is installed, whether the game will load
/// it, and one switch to change that. Enabling and disabling is a rename to
/// `.jar.disabled`, which is what every other launcher does too, so a user can
/// still fix a bad mod by hand in a file manager and this screen stays honest.
class InstanceModsScreen extends ConsumerStatefulWidget {
  const InstanceModsScreen({required this.id, this.onClose, super.key});

  final String id;

  /// Leaves the page; production uses the router, tests pass a callback.
  final VoidCallback? onClose;

  @override
  ConsumerState<InstanceModsScreen> createState() => _InstanceModsScreenState();
}

class _InstanceModsScreenState extends ConsumerState<InstanceModsScreen> {
  final _filter = m3.TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _close() {
    final close = widget.onClose;
    if (close != null) return close();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.instances);
    }
  }

  Instance? _instance() {
    final state = ref.watch(instanceListProvider);
    if (state is! InstanceListReady) return null;
    for (final instance in state.instances) {
      if (instance.id == widget.id) return instance;
    }
    return null;
  }

  Future<void> _rescan() async =>
      ref.invalidate(instanceModsProvider(widget.id));

  Future<void> _openFolder(Instance instance) async {
    final dir = modsDirFor(ref.read(launcherPathsProvider), instance);
    await Directory(dir).create(recursive: true);
    final opener = Platform.isWindows
        ? 'explorer'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    await Process.start(opener, [dir], mode: ProcessStartMode.detached);
  }

  Future<void> _toggle(ModEntry mod, bool enabled) async {
    try {
      await ref.read(modsRepositoryProvider).setEnabled(mod, enabled);
    } on FileSystemException catch (e) {
      if (!mounted) return;
      _toast(context.l10n.modsToggleFailed(e.message));
    } finally {
      await _rescan();
    }
  }

  Future<void> _confirmDelete(ModEntry mod) async {
    final l10n = context.l10n;
    final confirmed = await m3.showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: l10n.modsDeleteTitle,
        content: m3.Text(l10n.modsDeleteBody(mod.displayName)),
        actions: [
          AppButton(
            onPressed: () => m3.Navigator.pop(context, false),
            style: AppButtonStyle.text,
            label: m3.Text(l10n.actionCancel),
          ),
          AppButton(
            key: const m3.ValueKey('mod-delete-confirm'),
            onPressed: () => m3.Navigator.pop(context, true),
            style: AppButtonStyle.filled,
            label: m3.Text(l10n.modsDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(modsRepositoryProvider).delete(mod);
    await _rescan();
  }

  void _toast(String message) {
    m3.ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        m3.SnackBar(
          content: m3.Text(message),
          behavior: m3.SnackBarBehavior.floating,
        ),
      );
  }

  /// Opens the Modrinth search for this instance's loader and game version.
  void _openSearch(Instance instance) {
    if (McTarget.fromInstance(instance)?.isModded == false) {
      // A vanilla instance has nothing to search against: say why instead of
      // opening a dialog that returns nothing loadable.
      m3.showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: context.l10n.modsSearchNeedsLoader,
          content: m3.Text(context.l10n.modsSearchVanillaHint),
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
    m3.showDialog<void>(
      context: context,
      builder: (context) => ModSearchDialog(instance: instance),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final instance = _instance();
    if (instance == null) {
      return PageBody(
        child: m3.Column(
          crossAxisAlignment: m3.CrossAxisAlignment.start,
          children: [
            m3.Text(l10n.instanceMissing, style: AppTheme.body(context)),
            const m3.SizedBox(height: 12),
            AppButton(
              onPressed: _close,
              style: AppButtonStyle.filled,
              label: m3.Text(l10n.actionBack),
            ),
          ],
        ),
      );
    }

    final mods = ref.watch(instanceModsProvider(widget.id));

    return PageBody(
      scrollable: false,
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          _Header(
            instance: instance,
            filter: _filter,
            onFilterChanged: () => setState(() {}),
            onBack: _close,
            onRefresh: _rescan,
            onOpenFolder: () => _openFolder(instance),
            onGetMods: () => _openSearch(instance),
            enabled: mods.value?.where((m) => m.enabled).length,
            total: mods.value?.length,
          ),
          const m3.SizedBox(height: 12),
          m3.Expanded(
            child: mods.when(
              loading: () =>
                  const m3.Center(child: m3.CircularProgressIndicator()),
              error: (error, _) =>
                  m3.Center(child: m3.SelectableText('$error')),
              data: (list) {
                final query = _filter.text.trim().toLowerCase();
                final visible = query.isEmpty
                    ? list
                    : list
                          .where(
                            (m) =>
                                m.displayName.toLowerCase().contains(query) ||
                                (m.id ?? '').toLowerCase().contains(query),
                          )
                          .toList();
                if (list.isEmpty) {
                  return _Empty(onOpenFolder: () => _openFolder(instance));
                }
                return m3.ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) => _ModRow(
                    mod: visible[index],
                    onToggle: (enabled) => _toggle(visible[index], enabled),
                    onDelete: () => _confirmDelete(visible[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.instance,
    required this.filter,
    required this.onFilterChanged,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenFolder,
    required this.onGetMods,
    required this.enabled,
    required this.total,
  });

  final Instance instance;
  final m3.TextEditingController filter;
  final VoidCallback onFilterChanged;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFolder;
  final VoidCallback onGetMods;
  final int? enabled;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final counts = total == null ? '' : l10n.modsCounts(enabled ?? 0, total!);

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Row(
          children: [
            m3.IconButton(
              key: const m3.ValueKey('mods-back'),
              onPressed: onBack,
              icon: const m3.Icon(ShellIcons.back, size: 18),
              tooltip: l10n.actionBack,
              visualDensity: m3.VisualDensity.compact,
            ),
            const m3.SizedBox(width: 4),
            m3.Expanded(
              child: m3.Column(
                crossAxisAlignment: m3.CrossAxisAlignment.start,
                mainAxisSize: m3.MainAxisSize.min,
                children: [
                  m3.Text(l10n.modsTitle, style: AppTheme.title(context)),
                  m3.Text(
                    counts.isEmpty
                        ? instance.name
                        : '${instance.name} · $counts',
                    style: AppTheme.caption(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            m3.SizedBox(
              width: 220,
              child: AppTextField(
                key: const m3.ValueKey('mods-filter'),
                controller: filter,
                hint: l10n.modsSearchHint,
                leading: const m3.Icon(ShellIcons.search, size: 15),
                onChanged: (_) => onFilterChanged(),
              ),
            ),
            const m3.SizedBox(width: 8),
            // The one action that adds something: searching Modrinth is the only
            // way a user gets a mod without visiting a website and finding the
            // mods folder by hand.
            AppButton(
              key: const m3.ValueKey('mods-get'),
              onPressed: onGetMods,
              style: AppButtonStyle.filled,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.add, size: 14),
              label: m3.Text(l10n.modsGet),
            ),
            const m3.SizedBox(width: 8),
            AppButton(
              key: const m3.ValueKey('mods-refresh'),
              onPressed: onRefresh,
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.refresh, size: 14),
              label: m3.Text(l10n.modsRefresh),
            ),
            AppButton(
              key: const m3.ValueKey('mods-open-folder'),
              onPressed: onOpenFolder,
              style: AppButtonStyle.outlined,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.folder, size: 14),
              label: m3.Text(l10n.modsOpenFolder),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModRow extends StatelessWidget {
  const _ModRow({
    required this.mod,
    required this.onToggle,
    required this.onDelete,
  });

  final ModEntry mod;
  final m3.ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final broken = mod.problem != null;

    // "version · loader · size" - the three things that decide whether this jar
    // will work, in the order a user checks them.
    final supporting = [
      if (mod.version != null) mod.version!,
      mod.loader.label,
      formatBytes(mod.sizeBytes),
    ].join(' · ');

    return ListRow(
      key: m3.ValueKey('mod-${mod.fileName}'),
      leadingIcon: broken ? ShellIcons.warning : ShellIcons.mods,
      label: mod.displayName,
      // The label already *is* the file name when the metadata is unreadable, so
      // repeating it here would read as two different things.
      supporting: broken ? mod.problem! : supporting,
      trailingText: mod.enabled ? null : l10n.modsDisabled,
      trailingTextKey: m3.ValueKey('mod-state-${mod.fileName}'),
      trailingIcon: ShellIcons.trash,
      trailingTooltip: l10n.modsDeleteAction,
      onTrailingPressed: onDelete,
      trailingControl: AppSwitch(
        key: m3.ValueKey('mod-switch-${mod.fileName}'),
        value: mod.enabled,
        onChanged: onToggle,
        label: mod.displayName,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onOpenFolder});

  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Center(
      child: m3.Column(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          m3.Icon(ShellIcons.mods, size: 32, color: scheme.onSurfaceVariant),
          const m3.SizedBox(height: 12),
          m3.Text(l10n.modsEmptyTitle, style: AppTheme.subtitle(context)),
          const m3.SizedBox(height: 4),
          m3.Text(
            l10n.modsEmptyBody,
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
            textAlign: m3.TextAlign.center,
          ),
          const m3.SizedBox(height: 16),
          // Only the folder action: "get mods" is a permanent button in the
          // header, and a second copy in the middle of an empty list is the same
          // control drawn twice.
          m3.Row(
            mainAxisAlignment: m3.MainAxisAlignment.center,
            children: [
              AppButton(
                onPressed: onOpenFolder,
                style: AppButtonStyle.outlined,
                label: m3.Text(l10n.modsOpenFolder),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
