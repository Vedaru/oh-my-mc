import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// The standard page frame inside the navigation rail.
///
/// Every screen gets the same outer padding, the same maximum content width and
/// the same scrolling behaviour, so the app reads as one surface instead of six
/// widgets pinned to the rail. The width cap is the point on a desktop window: a
/// settings row stretched across 2000 px puts its label and its control a head
/// turn apart, and a centred column is what Material's own desktop guidance does
/// with that space.
///
/// [scrollable] is `false` for the pages whose body is a viewport itself (a grid,
/// a log list): they own their scrolling, and wrapping them in a scroll view would
/// give them unbounded height and break their `Expanded` children.
class PageBody extends StatelessWidget {
  const PageBody({
    required this.child,
    this.maxWidth = 1040,
    this.scrollable = true,
    this.padding = const m3.EdgeInsets.fromLTRB(24, 20, 24, 24),
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final bool scrollable;
  final m3.EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = m3.ConstrainedBox(
      constraints: m3.BoxConstraints(maxWidth: maxWidth),
      child: m3.SizedBox(
        width: double.infinity,
        // A non-scrollable page fills the viewport: its own `Expanded` children
        // need a bounded height, and a short page should not float in the middle
        // of the window.
        height: scrollable ? null : double.infinity,
        child: m3.Padding(padding: padding, child: child),
      ),
    );

    return m3.Align(
      alignment: m3.Alignment.topCenter,
      child: scrollable ? m3.SingleChildScrollView(child: content) : content,
    );
  }
}

/// The page's own title, in the one style and position every screen uses.
///
/// Screens used to each pick their own padding for this row, which is how the
/// title ended up touching the rail on one page and sitting 16 px in on another.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {this.trailing, super.key});

  final String text;

  /// Right-aligned actions for the page (a count, a create button, a refresh).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final action = trailing;
    return m3.Padding(
      padding: const m3.EdgeInsets.only(bottom: 16),
      child: m3.Row(
        children: [
          m3.Expanded(
            child: m3.Text(
              text,
              style: m3.Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
