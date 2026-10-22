import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/ui/components/app_button.dart';

import '../../core/launch/launch_handle.dart';
import '../../data/launch_providers.dart';
import '../../l10n/l10n.dart';
import '../components/page_body.dart';
import '../motion/motion.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import '../components/app_switch.dart';
import '../components/app_text_field.dart';

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

    return PageBody(
      scrollable: false,
      child: MotionEntrance(
        children: [
          PageTitle(
            l10n.logsTitle,
            trailing: session.log.isNotEmpty
                ? AppButton(
                    key: const m3.ValueKey('logs-copy'),
                    onPressed: () => _copy(context, session.log),
                    style: AppButtonStyle.outlined,
                    size: AppButtonSize.sm,
                    icon: const m3.Icon(ShellIcons.copy, size: 14),
                    label: m3.Text(l10n.logsCopy),
                  )
                : null,
          ),
          m3.Padding(
            padding: const m3.EdgeInsets.only(bottom: 12),
            child: m3.Row(
              children: [
                m3.SizedBox(
                  // Fixed, not `Expanded` + `ConstrainedBox`: an Expanded hands
                  // down tight constraints, which silently override a maxWidth -
                  // that is how this field used to stretch across the page.
                  width: 380,
                  child: AppTextField(
                    key: const m3.ValueKey('logs-search'),
                    controller: _search,
                    hint: l10n.logsSearchHint,
                    leading: const m3.Icon(ShellIcons.search, size: 15),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const m3.SizedBox(width: 12),
                AppSwitch(
                  value: _filter == LogFilter.errors,
                  onChanged: (errors) => setState(() {
                    _filter = errors ? LogFilter.errors : LogFilter.all;
                  }),
                  label: l10n.logsOnlyErrors,
                ),
                const m3.SizedBox(width: 8),
                m3.Text(
                  l10n.logsOnlyErrors,
                  style: AppTheme.body(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          m3.Expanded(
            child: _Lines(
              lines: visible,
              // Distinguishes "nothing has run" from "your filter hides
              // everything", which are the same empty box otherwise.
              emptyText: session.log.isEmpty
                  ? l10n.logsEmpty
                  : l10n.logsNoMatches,
            ),
          ),
        ],
      ),
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

class _Lines extends StatefulWidget {
  const _Lines({required this.lines, required this.emptyText});

  final List<LogLine> lines;
  final String emptyText;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  /// The list owns its own item count (`insertItem`/`removeItem`), so this
  /// widget keeps the list of rows it has told the list about. The diff between
  /// that and [widget.lines] is what turns a provider update into insert calls.
  late List<LogLine> _shown = widget.lines;

  /// Rows that arrived on the last update. Their tint plays once; a row that was
  /// already on screen must not re-run it, or every rebuild would flash the
  /// console.
  var _fresh = <LogLine>{};

  var _listKey = GlobalKey<m3.AnimatedListState>();

  @override
  void didUpdateWidget(covariant _Lines oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.lines;

    // A parent rebuild with the same rows (a resize, a theme change) must not
    // touch the list.
    if (_sameRows(next, _shown)) return;

    if (!_isAppend(next)) {
      setState(() {
        // A fresh key rebuilds the list from scratch: a diff it cannot express
        // must not be faked with inserts.
        _listKey = GlobalKey<m3.AnimatedListState>();
        _shown = next;
        _fresh = const {};
      });
      return;
    }

    final start = _shown.length;
    // A backfill (nothing on screen yet) arrives without animation: it is a wall
    // of text, and animating it would delay the user's first useful frame.
    final duration = start == 0
        ? Duration.zero
        : MotionScope.of(context).of(Durations.base);

    setState(() {
      _shown = next;
      _fresh = {
        for (final line in next.skip(start))
          if (_isWarning(line)) line,
      };
      final list = _listKey.currentState;
      for (var i = start; i < next.length; i++) {
        list?.insertItem(i, duration: duration);
      }
    });
  }

  /// Identity, not equality: the session appends the same `LogLine` instances,
  /// while a filtered view is a different list of the same values.
  static bool _sameRows(List<LogLine> a, List<LogLine> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Whether [next] is [previous] plus new rows at the end.
  bool _isAppend(List<LogLine> next) {
    if (next.length < _shown.length) return false;
    for (var i = 0; i < _shown.length; i++) {
      if (!identical(next[i], _shown[i])) return false;
    }
    return true;
  }

  /// A line worth tinting on arrival: stderr, or a warning/error on stdout,
  /// which is where a JVM puts most of its bad news.
  static bool _isWarning(LogLine line) =>
      line.channel == LogChannel.stderr ||
      line.text.contains('WARN') ||
      line.text.contains('Error') ||
      line.text.contains('Exception');

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final warning = AppTheme.status(context).warning;

    if (widget.lines.isEmpty) {
      return m3.Container(
        decoration: m3.BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: m3.BorderRadius.circular(16),
        ),
        child: m3.Center(
          child: m3.Column(
            mainAxisSize: m3.MainAxisSize.min,
            children: [
              m3.Icon(
                ShellIcons.document,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
              const m3.SizedBox(height: 12),
              m3.Text(
                widget.emptyText,
                key: const m3.ValueKey('logs-empty'),
                style: AppTheme.caption(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
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
      child: m3.AnimatedList(
        // The global key *is* the identity: replacing it is what makes a
        // wholesale change rebuild the list instead of animating a diff.
        key: _listKey,
        padding: const m3.EdgeInsets.all(10),
        initialItemCount: _shown.length,
        itemBuilder: (context, index, animation) {
          final line = _shown[index];
          return m3.SizeTransition(
            sizeFactor: animation,
            alignment: m3.Alignment.topCenter,
            child: m3.FadeTransition(
              opacity: animation,
              child: AppendHighlight(
                enabled: _fresh.contains(line),
                tint: warning,
                child: m3.Text(
                  line.text,
                  style: AppTheme.mono(context).copyWith(
                    color: line.channel == LogChannel.stderr
                        ? scheme.error
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
