import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../app/providers.dart';
import '../../core/account/account.dart';
import '../../core/account/microsoft.dart';
import '../../data/account_providers.dart';
import '../../data/microsoft_providers.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/app_text_field.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// Microsoft sign-in, as a dialog: a code to type, and then waiting.
///
/// The device-code flow exists because a desktop app cannot hold a client secret and
/// should not open a local port for a redirect. So the dialog's job is narrow and
/// specific: show the code big enough to read off the screen, keep it copyable, say
/// plainly that the page is where the typing happens, and report the failures that have
/// an explanation (no Xbox profile, child account, no game on the account).
class MicrosoftSignInDialog extends ConsumerStatefulWidget {
  const MicrosoftSignInDialog({super.key});

  /// Returns the signed-in account, or null when the user closed the dialog.
  static Future<Account?> show(BuildContext context) => m3.showDialog<Account>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const MicrosoftSignInDialog(),
  );

  @override
  ConsumerState<MicrosoftSignInDialog> createState() =>
      _MicrosoftSignInDialogState();
}

class _MicrosoftSignInDialogState extends ConsumerState<MicrosoftSignInDialog> {
  DeviceCode? _code;
  String? _error;

  /// Flips when the dialog closes so the poll stops instead of running on into a dead
  /// widget.
  var _closed = false;

  @override
  void initState() {
    super.initState();
    // Starting the flow is a network call; it is kicked off after the first frame so the
    // dialog is on screen while it happens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _start() async {
    // Without an application id there is nothing to ask Microsoft for, and the form in
    // `build` is what the user needs to see. The chain itself would refuse too
    // (`missing_client_id`), but refusing here keeps the failed request off the wire.
    if (ref.read(appSettingsProvider).microsoftClientId.trim().isEmpty) return;
    final auth = ref.read(microsoftAuthProvider);
    try {
      final code = await auth.requestDeviceCode();
      if (!mounted) return;
      setState(() => _code = code);
      final session = await auth.waitForSignIn(code, cancelled: () => _closed);
      if (!mounted) return;
      final account = accountFromSession(session);
      await ref.read(accountListProvider.notifier).add(account);
      if (!mounted) return;
      m3.Navigator.of(context).pop(account);
    } on MicrosoftAuthException catch (error) {
      if (!mounted || _closed) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final code = _code;
    final clientId = ref.watch(
      appSettingsProvider.select((settings) => settings.microsoftClientId),
    );

    return m3.AlertDialog(
      title: m3.Text(l10n.microsoftSignIn),
      content: m3.SizedBox(
        width: 420,
        child: m3.Column(
          mainAxisSize: m3.MainAxisSize.min,
          crossAxisAlignment: m3.CrossAxisAlignment.start,
          children: [
            if (clientId.trim().isEmpty)
              _ClientIdForm(
                onSubmit: (id) async {
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setMicrosoftClientId(id);
                  if (!mounted) return;
                  setState(() => _error = null);
                  await _start();
                },
              )
            else if (_error != null)
              m3.SelectableText(
                _error!,
                style: AppTheme.body(context).copyWith(color: scheme.error),
              )
            else if (code == null)
              m3.Row(
                children: [
                  const m3.SizedBox(
                    width: 16,
                    height: 16,
                    child: m3.CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const m3.SizedBox(width: 12),
                  m3.Text(
                    l10n.microsoftPreparing,
                    style: AppTheme.body(context),
                  ),
                ],
              )
            else ...[
              m3.Text(l10n.microsoftCodeHint, style: AppTheme.body(context)),
              const m3.SizedBox(height: 12),
              _CodeBlock(code: code),
              const m3.SizedBox(height: 16),
              m3.Text(
                l10n.microsoftWaiting,
                style: AppTheme.caption(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      actions: [
        m3.TextButton(
          key: const m3.ValueKey('microsoft-cancel'),
          onPressed: () => m3.Navigator.of(context).pop(),
          child: m3.Text(l10n.actionCancel),
        ),
      ],
    );
  }
}

/// The code, big and copyable, beside the address to type it at.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code});

  final DeviceCode code;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.DecoratedBox(
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: m3.BorderRadius.circular(12),
      ),
      child: m3.Padding(
        padding: const m3.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: m3.Row(
          children: [
            m3.Expanded(
              child: m3.Column(
                crossAxisAlignment: m3.CrossAxisAlignment.start,
                children: [
                  m3.Text(
                    code.userCode,
                    style: m3.TextStyle(
                      fontSize: 26,
                      letterSpacing: 4,
                      fontWeight: m3.FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const m3.SizedBox(height: 4),
                  m3.SelectableText(
                    code.verificationUri,
                    style: AppTheme.caption(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            AppButton(
              key: const m3.ValueKey('microsoft-copy-code'),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: code.userCode)),
              style: AppButtonStyle.text,
              size: AppButtonSize.sm,
              icon: const m3.Icon(ShellIcons.copy, size: 14),
              label: m3.Text(l10n.settingsCopy),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asked once, then remembered: an Azure application id is per-launcher, so a build
/// cannot ship one and the user has to supply their own.
class _ClientIdForm extends StatefulWidget {
  const _ClientIdForm({required this.onSubmit});

  final Future<void> Function(String id) onSubmit;

  @override
  State<_ClientIdForm> createState() => _ClientIdFormState();
}

class _ClientIdFormState extends State<_ClientIdForm> {
  final _id = m3.TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.start,
      children: [
        m3.Text(l10n.microsoftNeedsClientId, style: AppTheme.body(context)),
        const m3.SizedBox(height: 8),
        m3.Text(
          l10n.microsoftClientIdHint,
          style: AppTheme.caption(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const m3.SizedBox(height: 12),
        AppTextField(
          key: const m3.ValueKey('microsoft-client-id'),
          controller: _id,
          autofocus: true,
          hint: '00000000-0000-0000-0000-000000000000',
          onSubmitted: (_) => widget.onSubmit(_id.text),
        ),
        const m3.SizedBox(height: 12),
        AppButton(
          key: const m3.ValueKey('microsoft-client-id-save'),
          onPressed: () => widget.onSubmit(_id.text),
          style: AppButtonStyle.filled,
          size: AppButtonSize.sm,
          label: m3.Text(l10n.actionSave),
        ),
      ],
    );
  }
}
