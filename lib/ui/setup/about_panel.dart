import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:url_launcher/url_launcher.dart';

import '../../app/version.dart';
import '../../core/update/update_check.dart';
import '../../l10n/l10n.dart';
import '../components/app_button.dart';
import '../components/list_row.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// The release-feed client.
///
/// A provider so a test never talks to GitHub: the panel's job is the three outcomes,
/// and `test/core/update/update_check_test.dart` owns the feed parsing.
final updateCheckerProvider = Provider<UpdateChecker>((ref) {
  final checker = UpdateChecker();
  ref.onDispose(checker.close);
  return checker;
});

/// 设置 → 关于: which build this is, and whether a newer one exists.
///
/// The check runs on demand, not at launch: a request to GitHub on every start is a
/// privacy answer the user did not give, and a banner over the play button is noise
/// for someone who just wants to play.
class AboutPanel extends ConsumerStatefulWidget {
  const AboutPanel({super.key});

  @override
  ConsumerState<AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends ConsumerState<AboutPanel> {
  UpdateCheck? _result;
  var _checking = false;
  var _checked = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _checked = true;
    });
    try {
      final result = await ref
          .read(updateCheckerProvider)
          .check(currentVersion: appVersion);
      if (!mounted) return;
      setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final result = _result;
    final newer = result?.isNewer ?? false;

    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        ListRow(
          key: const m3.ValueKey('about-version'),
          leadingIcon: ShellIcons.info,
          label: l10n.aboutVersion,
          supporting: appVersion,
          supportingMono: true,
          trailingControl: AppButton(
            key: const m3.ValueKey('about-check'),
            onPressed: _checking ? null : _check,
            style: AppButtonStyle.outlined,
            size: AppButtonSize.sm,
            label: m3.Text(_checking ? l10n.aboutChecking : l10n.aboutCheck),
          ),
        ),
        // Three outcomes, each said plainly: an update, no update, or no answer.
        if (_checked && !_checking && result == null)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 8),
            child: m3.Text(
              l10n.aboutCheckFailed,
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (result != null && !newer)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 8),
            child: m3.Text(
              l10n.aboutUpToDate(appVersion),
              style: AppTheme.caption(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (result != null && newer) ...[
          const m3.SizedBox(height: 8),
          m3.Container(
            padding: const m3.EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: m3.BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: m3.BorderRadius.circular(14),
              border: m3.Border(
                left: m3.BorderSide(color: scheme.primary, width: 3),
              ),
            ),
            child: m3.Column(
              crossAxisAlignment: m3.CrossAxisAlignment.start,
              children: [
                m3.Text(
                  l10n.aboutNewVersion(result.latest.version),
                  style: AppTheme.subtitle(context),
                ),
                if (result.latest.notes.trim().isNotEmpty) ...[
                  const m3.SizedBox(height: 6),
                  // The release notes as written: they are the announcement, and
                  // summarizing them would be inventing a summary of a changelog.
                  m3.ConstrainedBox(
                    constraints: const m3.BoxConstraints(maxHeight: 160),
                    child: m3.SingleChildScrollView(
                      child: m3.SelectableText(
                        result.latest.notes.trim(),
                        style: AppTheme.body(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
                if (result.latest.publishedAt != null) ...[
                  const m3.SizedBox(height: 6),
                  m3.Text(
                    l10n.aboutPublished(_date(result.latest.publishedAt!)),
                    style: AppTheme.caption(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const m3.SizedBox(height: 10),
                m3.Wrap(
                  spacing: 8,
                  children: [
                    if (result.latest.installerUrl != null)
                      AppButton(
                        key: const m3.ValueKey('about-download'),
                        onPressed: () => _open(result.latest.installerUrl!),
                        style: AppButtonStyle.filled,
                        size: AppButtonSize.sm,
                        icon: const m3.Icon(ShellIcons.download, size: 14),
                        label: m3.Text(l10n.aboutDownload),
                      ),
                    if (result.latest.pageUrl.isNotEmpty)
                      AppButton(
                        onPressed: () => _open(result.latest.pageUrl),
                        style: AppButtonStyle.text,
                        size: AppButtonSize.sm,
                        icon: const m3.Icon(ShellIcons.openExternal, size: 14),
                        label: m3.Text(l10n.aboutReleasePage),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _date(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
