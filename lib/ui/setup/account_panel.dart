import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/account/account.dart';
import '../../data/account_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_text_field.dart';
import '../components/empty_state.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// 设置 → 账户: who the game starts as.
///
/// The launcher used to have one name (`AppSettings.playerName`), which is one identity
/// and no way to hold two. An account list is what every other launcher has, because a
/// player is not one name: single-player worlds belong to one, a friend's server to
/// another.
///
/// Selecting an account is the write; there is no per-account "use" dialog.
class AccountPanel extends ConsumerWidget {
  const AccountPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final list = ref.watch(accountListProvider);

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        m3.Padding(
          padding: const m3.EdgeInsets.only(bottom: 8, left: 8),
          child: m3.Text(
            l10n.accountActiveHint,
            style: AppTheme.caption(context).copyWith(
              color: m3.Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        switch (list) {
          AsyncData(:final value) when value.accounts.isNotEmpty => m3.Column(
            children: [
              for (final account in value.accounts)
                _AccountRow(
                  account: account,
                  active: account.id == value.active?.id,
                ),
            ],
          ),
          AsyncData() => EmptyState(
            icon: ShellIcons.account,
            message: l10n.accountEmpty,
            hint: l10n.accountEmptyHint,
          ),
          AsyncError(:final error) => m3.SelectableText('$error'),
          _ => const m3.Padding(
            padding: m3.EdgeInsets.symmetric(vertical: 24),
            child: m3.Center(child: m3.CircularProgressIndicator()),
          ),
        },
        m3.Padding(
          padding: const m3.EdgeInsets.only(top: 8, left: 8),
          child: m3.Row(
            children: [
              AppButton(
                key: const m3.ValueKey('account-add'),
                onPressed: () => _addOffline(context, ref),
                style: AppButtonStyle.outlined,
                size: AppButtonSize.sm,
                icon: const m3.Icon(ShellIcons.add, size: 14),
                label: m3.Text(l10n.accountAdd),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addOffline(BuildContext context, WidgetRef ref) async {
    final name = await m3.showDialog<String>(
      context: context,
      builder: (context) => const _OfflineAccountDialog(),
    );
    if (name == null) return;
    final existing = ref.read(accountListProvider).value?.accounts ?? const [];
    if (existing.any((account) => account.name == name)) {
      // Two accounts with the same name are two identities with the same uuid: the
      // second one would silently share the first one's worlds.
      return;
    }
    await ref
        .read(accountListProvider.notifier)
        .add(offlineAccount(name, existing: existing));
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.account, required this.active});

  final Account account;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final notifier = ref.read(accountListProvider.notifier);

    return ListRow(
      key: m3.ValueKey('account-${account.id}'),
      leadingIcon: active ? ShellIcons.checkCircle : ShellIcons.account,
      label: account.name,
      // Kind and server, not the uuid: a hex prefix tells a user nothing, and two
      // accounts cannot share a name, so there is nothing to disambiguate.
      supporting: [
        account.isOffline ? l10n.accountOffline : l10n.accountThirdParty,
        if (account.server != null) account.server!,
      ].join(' · '),
      onPressed: active ? null : () => notifier.activate(account.id),
      trailingControl: m3.Row(
        mainAxisSize: m3.MainAxisSize.min,
        children: [
          m3.SizedBox(
            // A fixed box: an IconButton inside a `mainAxisSize.min` row otherwise
            // gets squeezed to its glyph and the bin reads as a stray bar.
            width: 32,
            height: 32,
            child: m3.IconButton(
              key: m3.ValueKey('account-remove-${account.id}'),
              onPressed: () => _remove(context, notifier),
              padding: m3.EdgeInsets.zero,
              icon: m3.Icon(
                ShellIcons.trash,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              tooltip: l10n.accountRemove,
            ),
          ),
          const m3.SizedBox(width: 4),
          m3.Switch(
            value: active,
            onChanged: (value) {
              if (value) notifier.activate(account.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    AccountListNotifier notifier,
  ) async {
    final l10n = context.l10n;
    final confirmed = await m3.showDialog<bool>(
      context: context,
      builder: (context) => m3.AlertDialog(
        title: m3.Text(l10n.accountRemoveTitle(account.name)),
        content: m3.Text(l10n.accountRemoveBody),
        actions: [
          m3.TextButton(
            onPressed: () => m3.Navigator.of(context).pop(false),
            child: m3.Text(l10n.actionCancel),
          ),
          m3.TextButton(
            key: const m3.ValueKey('account-remove-confirm'),
            onPressed: () => m3.Navigator.of(context).pop(true),
            child: m3.Text(l10n.accountRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.remove(account.id);
  }
}

/// The one form: a name the game will accept.
class _OfflineAccountDialog extends StatefulWidget {
  const _OfflineAccountDialog();

  @override
  State<_OfflineAccountDialog> createState() => _OfflineAccountDialogState();
}

class _OfflineAccountDialogState extends State<_OfflineAccountDialog> {
  final _name = m3.TextEditingController();
  var _valid = false;

  /// The rule the game applies to a name: 3-16 of `[A-Za-z0-9_]`. Validating here means
  /// the game never refuses a name the launcher accepted.
  static final _pattern = RegExp(r'^[A-Za-z0-9_]{3,16}$');

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      final valid = _pattern.hasMatch(_name.text.trim());
      if (valid != _valid) setState(() => _valid = valid);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return m3.AlertDialog(
      title: m3.Text(l10n.accountAdd),
      content: AppTextField(
        key: const m3.ValueKey('account-name'),
        controller: _name,
        autofocus: true,
        hint: l10n.accountNameHint,
        onSubmitted: (_) {
          if (_valid) m3.Navigator.of(context).pop(_name.text.trim());
        },
      ),
      actions: [
        m3.TextButton(
          onPressed: () => m3.Navigator.of(context).pop(),
          child: m3.Text(l10n.actionCancel),
        ),
        m3.TextButton(
          key: const m3.ValueKey('account-create'),
          onPressed: _valid
              ? () => m3.Navigator.of(context).pop(_name.text.trim())
              : null,
          child: m3.Text(l10n.actionSave),
        ),
      ],
    );
  }
}
