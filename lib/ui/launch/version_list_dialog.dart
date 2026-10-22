import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../app/router.dart';
import '../../core/instance/instance.dart';
import '../../data/instance_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// The version list, as PCL puts it behind the version card.
///
/// PCL's launch page has one card, and clicking it opens **版本列表**: a dialog
/// that lists the installed versions, switches to one, and offers the two things
/// a version needs from here - its own settings, and a way to create or manage
/// versions. It is a dialog and not an anchored dropdown because the card is the
/// page's *subject*, not a combo box: a popup menu that floats over the log
/// answers "which one" and nothing else, and it has to guess its own width from
/// the widest row (which is how a 500 px card ended up with a 240 px menu
/// hovering under it).
///
/// Rows are `ListRow`s so they match every other list in the app: leading icon
/// (the selection mark on the current version), name, "version · loader", and a
/// trailing action that opens that version's settings.
class VersionListDialog extends ConsumerWidget {
  const VersionListDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final state = ref.watch(instanceListProvider);
    final instances = switch (state) {
      InstanceListReady(:final instances) => instances,
      _ => const <Instance>[],
    };
    final selectedId = state is InstanceListReady ? state.selectedId : null;

    void close() => m3.Navigator.pop(context);
    void manage() {
      close();
      if (GoRouter.maybeOf(context) != null) context.go(Routes.instances);
    }

    return AppDialog(
      title: l10n.launchVersionListTitle,
      // A fixed width and a scroll view: the dialog must not size itself to the
      // widest row (that is how the old menu ended up 240 px under a 500 px card),
      // and ten versions must scroll instead of overflowing the dialog.
      content: m3.SizedBox(
        width: 420,
        child: m3.ConstrainedBox(
          constraints: const m3.BoxConstraints(maxHeight: 380),
          child: instances.isEmpty
              ? m3.Padding(
                  padding: const m3.EdgeInsets.symmetric(vertical: 20),
                  child: m3.Text(
                    l10n.launchVersionListEmpty,
                    style: AppTheme.body(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              : m3.SingleChildScrollView(
                  child: m3.Column(
                    mainAxisSize: m3.MainAxisSize.min,
                    children: [
                      for (final instance in instances)
                        ListRow(
                          key: m3.ValueKey('version-row-${instance.id}'),
                          leadingIcon: instance.id == selectedId
                              ? ShellIcons.check
                              : ShellIcons.instance,
                          label: instance.displayName,
                          // "26.2 · Fabric 0.16.9". When the instance is named after
                          // its version, repeating it says nothing - the loader is
                          // the part that informs.
                          supporting: _supporting(instance),
                          trailingIcon: ShellIcons.settings,
                          trailingTooltip: l10n.launchVersionSettings,
                          onTrailingPressed: () {
                            close();
                            if (GoRouter.maybeOf(context) != null) {
                              context.go(Routes.instanceDetail(instance.id));
                            }
                          },
                          onPressed: () {
                            ref
                                .read(instanceListProvider.notifier)
                                .select(instance.id);
                            close();
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        AppButton(
          key: const m3.ValueKey('version-list-manage'),
          onPressed: manage,
          style: AppButtonStyle.text,
          label: m3.Text(l10n.launchManageInstances),
        ),
        AppButton(
          key: const m3.ValueKey('version-list-new'),
          onPressed: manage,
          style: AppButtonStyle.filled,
          label: m3.Text(l10n.launchNewInstance),
        ),
      ],
    );
  }

  static String _supporting(Instance instance) {
    final loader = instance.loader.isModded
        ? '${instance.loader.label} ${instance.loaderVersion ?? ''}'.trim()
        : null;
    final version = instance.versionId == instance.displayName
        ? null
        : instance.versionId;
    return [
      version ?? '',
      loader ?? '',
    ].where((s) => s.isNotEmpty).join('  ·  ');
  }
}

/// Opens [VersionListDialog]. One entry point, so the launch page never grows a
/// second way to pick a version.
Future<void> showVersionList(BuildContext context) => m3.showDialog<void>(
  context: context,
  builder: (context) => const VersionListDialog(),
);
