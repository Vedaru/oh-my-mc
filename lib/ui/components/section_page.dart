import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../components/section_drawer.dart';
import '../shell/shell_icons.dart';

/// A page whose own navigation is a section list.
///
/// The settings page and an instance's page are the same shape: a heading, a list of
/// sections down the left, one section on the right. They used to build that shape
/// themselves, and the two copies disagreed - the settings drawer sat 24 px inside the
/// rail under a `PageTitle`, while the instance drawer sat 8 px inside it under a
/// hand-built header row - so the same control "moved" when you walked between pages.
/// One frame, one set of numbers:
///
/// * the heading row is [titleHeight] tall whether or not it has actions, so the drawer
///   below it starts at the same y on every page;
/// * the heading's icon occupies a fixed [iconSlot] whether or not the page has one, so
///   the title text starts at the same x on every page;
/// * the drawer is [drawerWidth] wide, inset by the page padding only;
/// * the body pane starts [gutter] right of the drawer and the content is capped at
///   [maxWidth].
class SectionPage extends StatelessWidget {
  const SectionPage({
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.mark,
    this.subtitle,
    this.actions,
    this.bodyScrollable = false,
    this.onBack,
    this.backLabel,
    this.drawerHeader,
    super.key,
  });

  final String title;

  /// The page's mark in the heading: a settings gear, an instance's loader icon (which
  /// is wrapped in the shared-element `Hero`, so it flies in from the card). Sits in a
  /// slot that is always [iconSlot] wide, so a page without one still lines up.
  final Widget? mark;

  /// A line under the title: what this page is about (a loader and version, a hint).
  final String? subtitle;

  /// The heading row's right end: the page's primary action and its menu.
  final Widget? actions;

  final Widget body;

  /// `true` when [body] is a form that should scroll inside the pane; `false` when it
  /// already is a fill-height list (a `ListView`, a viewport) - wrapping one of those
  /// in a scroll view gives it unbounded height and breaks its `Expanded`.
  final bool bodyScrollable;

  final List<SectionDestination> destinations;
  final int selectedIndex;
  final void Function(int index) onSelected;

  /// Where this page came from. Rendered as the drawer's first row rather than beside
  /// the heading: a back arrow in the heading pushes the page's mark out of the slot
  /// every page's section list lines up on, and the drawer's top is the one place that
  /// costs no alignment.
  final VoidCallback? onBack;

  /// What the back row says - the destination, not "back": "实例" tells you where you
  /// are going.
  final String? backLabel;

  /// An optional block above the destinations - a small caption, a total.
  final Widget? drawerHeader;

  /// Height of the heading row. Fixed rather than derived from its children, because
  /// the whole point is that the drawer's top edge does not depend on whether the page
  /// happens to have actions.
  static const titleHeight = 48.0;

  /// Width of the heading's icon slot, including the gap after it.
  static const iconSlot = 32.0;

  static const drawerWidth = 280.0;

  /// Gap between the drawer and the body pane.
  static const gutter = 24.0;

  static const maxWidth = 1200.0;

  Widget? _drawerHeader(BuildContext context, m3.ColorScheme scheme) {
    final onBack = this.onBack;
    final header = drawerHeader;
    if (onBack == null && header == null) return null;
    return m3.Column(
      crossAxisAlignment: m3.CrossAxisAlignment.stretch,
      children: [
        if (onBack != null)
          m3.TextButton(
            key: const m3.ValueKey('section-back'),
            onPressed: onBack,
            style: m3.TextButton.styleFrom(
              alignment: m3.Alignment.centerLeft,
              padding: const m3.EdgeInsets.symmetric(horizontal: 8),
            ),
            child: m3.Row(
              children: [
                m3.Icon(
                  ShellIcons.back,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const m3.SizedBox(width: 8),
                m3.Text(
                  backLabel ?? '',
                  style: m3.Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ?header,
        if (onBack != null || header != null)
          m3.Padding(
            padding: const m3.EdgeInsets.only(top: 6, bottom: 4),
            child: m3.Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final theme = m3.Theme.of(context);
    final mark = this.mark;
    final subtitle = this.subtitle;
    final actions = this.actions;

    return m3.Align(
      alignment: m3.Alignment.topCenter,
      child: m3.ConstrainedBox(
        constraints: const m3.BoxConstraints(maxWidth: maxWidth),
        child: m3.Padding(
          padding: const m3.EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: m3.Column(
            crossAxisAlignment: m3.CrossAxisAlignment.stretch,
            children: [
              m3.SizedBox(
                height: titleHeight,
                child: m3.Row(
                  children: [
                    m3.SizedBox(
                      width: iconSlot,
                      child: mark == null
                          ? null
                          : m3.Align(
                              alignment: m3.Alignment.centerLeft,
                              child: mark,
                            ),
                    ),
                    m3.Expanded(
                      child: m3.Column(
                        crossAxisAlignment: m3.CrossAxisAlignment.start,
                        mainAxisAlignment: m3.MainAxisAlignment.center,
                        children: [
                          m3.Text(
                            title,
                            style: theme.textTheme.headlineSmall,
                            maxLines: 1,
                            overflow: m3.TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            m3.Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: m3.TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    ?actions,
                  ],
                ),
              ),
              const m3.SizedBox(height: 16),
              m3.Expanded(
                child: m3.Row(
                  crossAxisAlignment: m3.CrossAxisAlignment.stretch,
                  children: [
                    SectionDrawer(
                      width: drawerWidth,
                      selectedIndex: selectedIndex,
                      onSelected: onSelected,
                      header: _drawerHeader(context, scheme),
                      destinations: destinations,
                    ),
                    const m3.SizedBox(width: gutter),
                    m3.Expanded(
                      child: bodyScrollable
                          ? m3.SingleChildScrollView(
                              padding: const m3.EdgeInsets.only(bottom: 24),
                              child: body,
                            )
                          : body,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
