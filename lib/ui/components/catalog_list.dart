import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../motion/tokens.dart';
import '../shell/shell_icons.dart';
import '../theme/app_theme.dart';
import 'app_text_field.dart';

/// A search field that reports after a pause, not on every keystroke.
///
/// Every catalogue search in the app is rate-limited and a one-letter query matches the
/// whole site, so this is the same 350 ms debounce everywhere - and it is here, once,
/// because three copies of "wait, check the text has not changed, then search" is three
/// places for the staleness check to be forgotten.
///
/// The wrapper owns the icon, the key and the disposal; a caller only says what to do with
/// the query.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    required this.onQuery,
    required this.hint,
    this.autofocus = false,
    this.fieldKey,
    this.leading = const m3.Icon(ShellIcons.search, size: 15),
    super.key,
  });

  /// Called with the trimmed query after the user stops typing, and on submit.
  final void Function(String query) onQuery;
  final String hint;
  final bool autofocus;
  final m3.Key? fieldKey;
  final m3.Widget leading;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  final _text = m3.TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: widget.fieldKey,
      controller: _text,
      autofocus: widget.autofocus,
      hint: widget.hint,
      leading: widget.leading,
      onSubmitted: widget.onQuery,
      onChanged: (text) {
        Future<void>.delayed(Durations.debounce, () {
          // The user may have typed on while this timer was pending; a stale query would
          // replace the results with an older search's.
          if (!mounted || _text.text != text) return;
          widget.onQuery(text.trim());
        });
      },
    );
  }
}

/// The three states of a catalogue list, in one place.
///
/// Loading, empty and error look the same in every search surface, and their copy and
/// caption colour is exactly where they drift apart. [rowBuilder] is only ever called with
/// a non-empty list, so a caller's row code has no empty case to get wrong.
class CatalogList<T> extends StatelessWidget {
  const CatalogList({
    required this.results,
    required this.rowBuilder,
    required this.emptyText,
    this.maxHeight = 380,
    this.wrap = false,
    super.key,
  });

  final AsyncValue<List<T>> results;
  final Widget Function(BuildContext context, T item) rowBuilder;

  /// Shown when the search succeeded and matched nothing.
  final String emptyText;

  final double maxHeight;

  /// Cards in a wrapping grid instead of rows in a list.
  ///
  /// A catalogue of *things you pick one of* reads better as cards, and a grid fills a
  /// wide window where a list of rows leaves it half empty. The three states above are
  /// the same either way, which is the point of this widget.
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final body = switch (results) {
      AsyncLoading() => const m3.Padding(
        padding: m3.EdgeInsets.symmetric(vertical: 24),
        child: m3.Center(child: m3.CircularProgressIndicator()),
      ),
      AsyncError(:final error) => m3.Padding(
        padding: const m3.EdgeInsets.symmetric(vertical: 24),
        child: m3.SelectableText('$error'),
      ),
      AsyncData(:final value) when value.isEmpty => m3.Padding(
        padding: const m3.EdgeInsets.symmetric(vertical: 24),
        child: m3.Text(
          emptyText,
          style: AppTheme.body(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      AsyncData(:final value) when wrap => m3.SingleChildScrollView(
        child: m3.Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final item in value) rowBuilder(context, item)],
        ),
      ),
      AsyncData(:final value) => m3.ListView(
        shrinkWrap: true,
        padding: m3.EdgeInsets.zero,
        children: [for (final item in value) rowBuilder(context, item)],
      ),
    };

    return m3.ConstrainedBox(
      constraints: m3.BoxConstraints(maxHeight: maxHeight),
      child: body,
    );
  }
}
