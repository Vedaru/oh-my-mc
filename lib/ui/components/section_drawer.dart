import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../theme/app_theme.dart';

/// A permanent secondary navigation list, in MD3's drawer anatomy.
///
/// Used by pages that own several sections of their own (设置's six areas, an
/// instance's per-content pages). Each row is the same widget MD3 uses inside a
/// `NavigationDrawerDestination` - a `ListTile` whose selected state is a
/// `secondaryContainer` stadium behind icon and label - but **the panel hugs its
/// items** instead of running the full height of the window.
///
/// That is the difference between a rail and a section list: a drawer pinned to the
/// bottom of an 800 px window with four items in it is four items and 500 px of empty
/// panel, which reads as an unfinished panel rather than a navigation control. The
/// width is fixed so the body pane starts at the same x on every page.
///
/// Colour: `surfaceContainerLow`, no elevation. MD3 expresses a raised surface as a
/// tone step, and a shadow here would fight the primary rail beside it.
class SectionDrawer extends StatelessWidget {
  const SectionDrawer({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.width = 280,
    this.header,
    super.key,
  });

  final List<SectionDestination> destinations;
  final int selectedIndex;
  final void Function(int index) onSelected;
  final double width;

  /// An optional caption above the destinations: a subject, a count.
  final Widget? header;

  /// Height of one destination. 52 is MD3's drawer-item height with a single line.
  static const itemHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    final header = this.header;

    return m3.SizedBox(
      width: width,
      child: m3.Align(
        alignment: m3.Alignment.topLeft,
        child: m3.DecoratedBox(
          decoration: m3.BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: m3.BorderRadius.circular(16),
          ),
          child: m3.Padding(
            padding: const m3.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: m3.Column(
              mainAxisSize: m3.MainAxisSize.min,
              crossAxisAlignment: m3.CrossAxisAlignment.stretch,
              children: [
                if (header != null) ...[
                  m3.Padding(
                    padding: const m3.EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: header,
                  ),
                ],
                for (final (index, destination) in destinations.indexed)
                  _Destination(
                    key: m3.ValueKey(destination.key),
                    destination: destination,
                    selected: index == selectedIndex,
                    onPressed: () => onSelected(index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of a [SectionDrawer]: MD3's drawer-destination anatomy.
class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final SectionDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = m3.Theme.of(context).colorScheme;
    return m3.Semantics(
      selected: selected,
      button: true,
      child: m3.Padding(
        padding: const m3.EdgeInsets.symmetric(vertical: 2),
        child: m3.Material(
          type: m3.MaterialType.transparency,
          child: m3.InkWell(
            onTap: onPressed,
            customBorder: const m3.StadiumBorder(),
            child: m3.Container(
              height: SectionDrawer.itemHeight,
              decoration: m3.ShapeDecoration(
                shape: const m3.StadiumBorder(),
                color: selected
                    ? scheme.secondaryContainer
                    : m3.Colors.transparent,
              ),
              padding: const m3.EdgeInsets.symmetric(horizontal: 12),
              child: m3.Row(
                children: [
                  m3.Icon(
                    destination.icon,
                    size: 20,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  const m3.SizedBox(width: 12),
                  m3.Expanded(
                    child: m3.Text(
                      destination.label,
                      maxLines: 1,
                      overflow: m3.TextOverflow.ellipsis,
                      style: AppTheme.label(context).copyWith(
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                        fontWeight: selected
                            ? m3.FontWeight.w600
                            : m3.FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of a [SectionDrawer].
class SectionDestination {
  const SectionDestination({
    required this.key,
    required this.label,
    required this.icon,
  });

  /// Stable `ValueKey` id, so tests address a section by name rather than by index.
  final String key;
  final String label;
  final m3.IconData icon;
}
