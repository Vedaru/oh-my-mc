import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;

/// A permanent secondary navigation list, in MD3's navigation-drawer idiom.
///
/// Used by pages that own several sections of their own (设置's six areas, an
/// instance's per-content pages). It is a real [m3.NavigationDrawer] rather than a
/// column of hand-painted rows: the drawer owns the selected-indicator pill, the icon
/// and label roles, and the 12 dp tile padding, so every section list in the app looks
/// like the same control.
///
/// Colour: `surfaceContainerLow`, no elevation. MD3 expresses a raised surface as a
/// tone step, and a shadow here would fight the primary rail beside it.
class SectionDrawer extends StatelessWidget {
  const SectionDrawer({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.width = 300,
    this.header,
    super.key,
  });

  final List<SectionDestination> destinations;
  final int selectedIndex;
  final void Function(int index) onSelected;
  final double width;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return m3.SizedBox(
      width: width,
      child: m3.ClipRRect(
        borderRadius: m3.BorderRadius.circular(16),
        child: m3.NavigationDrawer(
          backgroundColor: m3.Theme.of(context).colorScheme.surfaceContainerLow,
          elevation: 0,
          shadowColor: m3.Colors.transparent,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          header: header,
          children: [
            for (final destination in destinations)
              m3.NavigationDrawerDestination(
                key: m3.ValueKey(destination.key),
                icon: m3.Icon(destination.icon, size: 20),
                label: m3.Text(destination.label),
              ),
          ],
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
