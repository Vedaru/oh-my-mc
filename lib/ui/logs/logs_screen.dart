import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../core/launch/launch_handle.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';

/// Which log lines are visible.
enum LogFilter {
  all,
  errors;

  /// `all` keeps everything; `errors` keeps stderr plus anything that looks like
  /// a failure on stdout.
  ///
  /// The second half matters because Minecraft writes most of its crashes to
  /// stdout: filtering strictly on the channel would hide
  /// `java.lang.NoSuchMethodError` while showing harmless warnings.
  bool accepts(LogLine line) {
    if (this == LogFilter.all) return true;
    if (line.channel == LogChannel.stderr) return true;
    final text = line.text;
    return text.contains('Exception') ||
        text.contains('Error') ||
        text.contains('Caused by:') ||
        text.contains('FAILED');
  }
}

/// The log console: the current session's output, filtered and searchable.
///
/// Deliberately a separate screen from the launch screen's tail. The tail exists
/// to answer "did it start?" in one glance; this screen exists to answer "why did
/// it not?", which needs a filter, a search box, and a way to get the text out to
/// somewhere it can be pasted.
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _search = TextEditingController();
  var _filter = LogFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = m3.Theme.of(context).colorScheme;
    final session = ref.watch(launchControllerProvider);

    final needle = _search.text.trim().toLowerCase();
    final visible = session.log
        .where(_filter.accepts)
        .where(
          (line) => needle.isEmpty || line.text.toLowerCase().contains(needle),
        )
        .toList();

    return MotionEntrance(
      children: [
        m3.Padding(
          padding: const m3.EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: m3.Row(
            children: [
              m3.Expanded(
                child: m3.Text(l10n.logsTitle, style: AppTheme.title(context)),
              ),
              if (session.log.isNotEmpty)
                AppButton(
                  key: const m3.ValueKey('logs-copy'),
                  onPressed: () => _copy(context, session.log),
                  style: m3e.M3EButtonStyle.outlined,
                  size: m3e.M3EButtonSize.sm,
                  icon: const m3.Icon(ShellIcons.copy, size: 14),
                  label: m3.Text(l10n.logsCopy),
                ),
            ],
          ),
        ),
        m3.Padding(
          padding: const m3.EdgeInsets.symmetric(horizontal: 16),
          child: m3.Row(
            children: [
              m3.Expanded(
                child: m3e.M3ETextField(
                  key: const m3.ValueKey('logs-search'),
                  controller: _search,
                  placeholder: l10n.logsSearchHint,
                  leading: const m3.Icon(ShellIcons.search, size: 15),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const m3.SizedBox(width: 12),
              m3e.M3ESwitch(
                value: _filter == LogFilter.errors,
                onChanged: (errors) => setState(() {
                  _filter = errors ? LogFilter.errors : LogFilter.all;
                }),
                semanticLabel: l10n.logsOnlyErrors,
              ),
              const m3.SizedBox(width: 8),
              m3.Text(
                l10n.logsOnlyErrors,
                style: AppTheme.body(context).copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        m3.Expanded(
          child: m3.Padding(
            padding: const m3.EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _Lines(
              lines: visible,
              // Distinguishes "nothing has run" from "your filter hides
              // everything", which are the same empty box otherwise.
              emptyText: session.log.isEmpty
                  ? l10n.logsEmpty
                  : l10n.logsNoMatches,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, List<LogLine> lines) async {
    // The *whole* log, not the filtered view: the user filtered it to read it,
    // and whoever they hand it to needs the rest.
    final text = lines.map(_withChannel).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// stderr lines are marked so a pasted log keeps the distinction the colours
  /// made on screen.
  static String _withChannel(LogLine line) =>
      line.channel == LogChannel.stderr ? '! ${line.text}' : line.text;
}

class _Lines extends StatelessWidget {
  const _Lines({required this.lines, required this.emptyText});

  final List<LogLine> lines;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;

    if (lines.isEmpty) {
      return m3.Center(
        child: m3.Text(
          emptyText,
          key: const m3.ValueKey('logs-empty'),
          style: AppTheme.caption(context).copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return m3.Container(
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: m3.BorderRadius.circular(10),
        border: m3.Border.all(color: scheme.outlineVariant),
      ),
      child: m3.ListView.builder(
        padding: const m3.EdgeInsets.all(10),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          return m3.Text(
            line.text,
            style: AppTheme.mono(context).copyWith(
              color: line.channel == LogChannel.stderr
                  ? scheme.error
                  : scheme.onSurface,
            ),
          );
        },
      ),
    );
  }
}
