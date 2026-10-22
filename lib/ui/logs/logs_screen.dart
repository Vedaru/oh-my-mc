import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/launch/launch_handle.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';

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
    final theme = FluentTheme.of(context);
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.logsTitle, style: theme.typography.title),
              ),
              if (session.log.isNotEmpty)
                Button(
                  key: const ValueKey('logs-copy'),
                  onPressed: () => _copy(context, session.log),
                  child: Text(l10n.logsCopy),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  key: const ValueKey('logs-search'),
                  controller: _search,
                  placeholder: l10n.logsSearchHint,
                  prefix: const Padding(
                    padding: EdgeInsetsDirectional.only(start: 8),
                    child: Icon(ShellIcons.search, size: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ToggleSwitch(
                checked: _filter == LogFilter.errors,
                onChanged: (errors) => setState(() {
                  _filter = errors ? LogFilter.errors : LogFilter.all;
                }),
                content: Text(l10n.logsOnlyErrors),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
    final theme = FluentTheme.of(context);

    if (lines.isEmpty) {
      return Center(
        child: Text(
          emptyText,
          key: const ValueKey('logs-empty'),
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          return Text(
            line.text,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'Consolas',
              color: line.channel == LogChannel.stderr
                  ? theme.resources.systemFillColorCritical
                  : theme.typography.caption?.color,
            ),
          );
        },
      ),
    );
  }
}
