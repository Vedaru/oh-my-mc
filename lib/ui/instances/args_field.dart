import 'package:fluent_ui/fluent_ui.dart';

import '../../core/instance/args.dart';
import '../../l10n/l10n.dart';

/// The JVM/game argument editors.
///
/// A multiline text box rather than a chip list: arguments are pasted from forum
/// posts and crash reports, and a list that has to be added to one row at a time
/// makes that painful. The trade-off is that the text is not the truth - the
/// parsed list is - so [ArgsField] shows what will actually be passed, which is
/// how a quoting mistake becomes visible before launch instead of as a JVM error.
class ArgsField extends StatefulWidget {
  const ArgsField({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.fieldKey,
    super.key,
  });

  final String label;
  final String hint;
  final List<String> value;
  final void Function(List<String>) onChanged;
  final Key? fieldKey;

  @override
  State<ArgsField> createState() => _ArgsFieldState();
}

class _ArgsFieldState extends State<ArgsField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  late List<String> _parsed;

  @override
  void initState() {
    super.initState();
    _parsed = widget.value;
    _controller = TextEditingController(text: formatArgs(widget.value));
    _focus.addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(ArgsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the value changed from outside: rewriting the controller on every
    // rebuild would fight the cursor while the user types.
    if (!_sameList(widget.value, oldWidget.value) &&
        !_sameList(widget.value, _parsed)) {
      _controller.text = formatArgs(widget.value);
      _parsed = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_commitOnBlur);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _commitOnBlur() {
    if (!_focus.hasFocus) _commit();
  }

  /// Re-parses for the preview only. Persisting stays on blur: a write per
  /// keystroke would rewrite `instances.json` dozens of times for one argument.
  void _reparse() {
    final parsed = parseArgs(_controller.text);
    if (_sameList(parsed, _parsed)) return;
    setState(() => _parsed = parsed);
  }

  void _commit() {
    final parsed = parseArgs(_controller.text);
    setState(() => _parsed = parsed);
    if (_sameList(parsed, widget.value)) return;
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: theme.typography.bodyStrong),
        const SizedBox(height: 4),
        TextBox(
          key: widget.fieldKey,
          controller: _controller,
          focusNode: _focus,
          maxLines: 4,
          placeholder: widget.hint,
          // The preview is live so a quoting mistake shows up while the text is
          // still in front of the user; the write is not.
          onChanged: (_) => _reparse(),
          onSubmitted: (_) => _commit(),
        ),
        const SizedBox(height: 4),
        Text(
          _parsed.isEmpty
              ? l10n.instanceArgsPreview(0)
              : l10n.instanceArgsPreview(_parsed.length),
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
        if (_parsed.isNotEmpty)
          SelectableText(
            l10n.instanceArgsPreviewList(_parsed.join(' · ')),
            style: theme.typography.caption?.copyWith(
              fontFamily: 'monospace',
              color: theme.inactiveColor,
            ),
          ),
      ],
    );
  }
}
