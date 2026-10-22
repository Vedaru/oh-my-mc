import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import '../theme/app_theme.dart';
import 'shell_icons.dart';

/// One navigation destination. Derived from [Routes], so a route and its rail
/// item cannot disagree about the path.
class ShellDestination {
  const ShellDestination({
    required this.location,
    required this.label,
    required this.icon,
  });

  final String location;
  final String Function(AppLocalizations l10n) label;
  final m3.IconData icon;
}

/// The destinations, in rail order.
///
/// **Launch first and no Instances tab**, which is PCL's operation logic: the
/// launch page owns version selection (its picker lists every version and reaches
/// management from there), so a second tab whose only job is choosing what the
/// launch page already chooses is two doors to one room. `/instances` still
/// exists as a route - it is the management screen the picker links to.
List<ShellDestination> destinationsFor(AppLocalizations l10n) => [
  ShellDestination(
    location: Routes.launch,
    label: (l) => l.navLaunch,
    icon: ShellIcons.forRoute(Routes.launch),
  ),
  ShellDestination(
    location: Routes.download,
    label: (l) => l.navDownload,
    icon: ShellIcons.forRoute(Routes.download),
  ),
  ShellDestination(
    location: Routes.logs,
    label: (l) => l.navLogs,
    icon: ShellIcons.forRoute(Routes.logs),
  ),
  ShellDestination(
    location: Routes.setup,
    label: (l) => l.navSetup,
    icon: ShellIcons.forRoute(Routes.setup),
  ),
];

/// The application shell: a navigation rail whose selection follows the router
/// rather than its own state.
///
/// The single decision this widget makes is that **the router is the source of
/// truth for navigation state**. A rail would happily keep its own selected
/// index and drift from the URL after a deep link, a back gesture or a
/// programmatic `context.go()`; taking the index from [location] and treating
/// `onDestinationSelected` as a request removes the possibility of the two
/// disagreeing.
///
/// The rail is **fixed-width with the label under each icon**
/// ([m3.NavigationRailLabelType.all]). Two decisions, one reason each: an
/// extended, beside-the-icon rail spent 216 px on five two-character labels, and
/// a collapsible rail animates its own width, which would make the body's
/// constraints depend on a control inside it. A fixed compact rail keeps the
/// icons and their names together and keeps the body's width a constant.
class AppShell extends StatelessWidget {
  const AppShell({required this.location, required this.child, super.key});

  /// The current location, from `GoRouterState.uri.path`.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = destinationsFor(l10n);
    final selected = selectedIndexFor(destinations, location);

    // The `Scaffold` is not decoration: without it there is no `Material`
    // ancestor for the page, so every ink splash asserts ("No Material widget
    // found") and any text that does not carry an explicit style falls back to
    // MaterialApp's 48 px red error style. It also supplies the themed
    // background, which a bare Column does not paint at all.
    return m3.Scaffold(
      body: m3.Column(
        children: [
          const _ShellHeader(),
          m3.Expanded(
            child: m3.Row(
              children: [
                m3.NavigationRail(
                  // Labels sit *under* their icon (MD3 `labelType.all`) instead
                  // of beside it: the destinations then read as a stack of tabs,
                  // and the rail stops charging the page 216 px of width for five
                  // two-character labels. The width stays constant, so the body's
                  // constraints still do not depend on a control inside the rail -
                  // this is a fixed-width rail, not a collapsible one.
                  labelType: m3.NavigationRailLabelType.all,
                  minWidth: 88,
                  selectedIndex: selected,
                  onDestinationSelected: (index) =>
                      context.go(destinations[index].location),
                  destinations: [
                    for (final destination in destinations)
                      m3.NavigationRailDestination(
                        icon: m3.Icon(destination.icon),
                        label: m3.Text(destination.label(l10n)),
                      ),
                  ],
                ),
                m3.Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a location to a rail index.
///
/// A prefix test, not equality: `/instances/:id` is a child route and must
/// highlight the Instances item, which is the whole reason this is a function
/// with a test rather than an `indexOf`. An unknown path falls back to 0 so a
/// stale deep link still highlights something sane.
int selectedIndexFor(List<ShellDestination> destinations, String location) {
  var best = 0;
  var bestLength = 0;
  for (var i = 0; i < destinations.length; i++) {
    final path = destinations[i].location;
    if (location.startsWith(path) && path.length > bestLength) {
      best = i;
      bestLength = path.length;
    }
  }
  return best;
}

/// The app header above the rail.
///
/// Deliberately not a window title bar. Window decorations are left to the
/// platform: on Linux, GTK negotiates client-side decorations on Wayland
/// (GNOME implements no `xdg-decoration`) and server-side ones elsewhere, and a
/// second, hand-drawn caption would either duplicate or fight the compositor's.
/// Keeping the platform's chrome is what makes dragging, snapping and
/// maximise-on-double-click work natively on Wayland without a line of code.
///
/// So this is a *header*: the app mark, the current screen's name, and on the
/// right the app name. It carries no window controls.
class _ShellHeader extends StatelessWidget {
  const _ShellHeader();

  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final motion = MotionScope.of(context);
    final scheme = m3.Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.path;
    final subtitle = routeTitle(l10n, location);

    return m3.Container(
      height: height,
      decoration: m3.BoxDecoration(color: scheme.surfaceContainer),
      padding: const m3.EdgeInsets.symmetric(horizontal: 20),
      child: m3.Row(
        children: [
          m3.Icon(ShellIcons.instance, size: 18, color: scheme.primary),
          const m3.SizedBox(width: 10),
          m3.AnimatedSwitcher(
            duration: motion.of(Durations.fast),
            switchInCurve: MotionCurves.enter,
            switchOutCurve: MotionCurves.exit,
            transitionBuilder: (child, animation) =>
                m3.FadeTransition(opacity: animation, child: child),
            child: m3.Text(
              // The key is what makes the switch happen at all: without it
              // AnimatedSwitcher sees the same widget type and just updates the
              // text in place.
              subtitle,
              key: m3.ValueKey(subtitle),
              style: AppTheme.subtitle(context),
            ),
          ),
        ],
      ),
    );
  }
}
