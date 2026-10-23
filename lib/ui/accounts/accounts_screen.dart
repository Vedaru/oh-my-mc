import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../l10n/l10n.dart';
import '../components/page_body.dart';
import '../setup/account_panel.dart';

/// 账户: who the game starts as.
///
/// Accounts were a settings section first, which is where this kind of thing usually
/// lives - but an account is not a preference, it is the thing every launch depends on,
/// so it belongs in the rail next to 启动 rather than two clicks inside 设置.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;

    return PageBody(
      child: m3.Column(
        crossAxisAlignment: m3.CrossAxisAlignment.stretch,
        children: [
          PageTitle(l10n.navAccounts),
          m3.DecoratedBox(
            decoration: m3.BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: m3.BorderRadius.circular(16),
            ),
            child: m3.Padding(
              padding: const m3.EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: const AccountPanel(),
            ),
          ),
        ],
      ),
    );
  }
}
