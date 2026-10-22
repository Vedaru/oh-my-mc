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
/// Launch is first and Instances second: the launcher opens on the thing the
/// user does most, and an instance list is a management screen, not a home.
List<ShellDestination> destinationsFor(AppLocalizations l10n) => [
  ShellDestination(
    location: Routes.launch,
    label: (l) => l.navLaunch,
    icon: ShellIcons.forRoute(Routes.launch),
  ),
  ShellDestination(
    location: Routes.instances,
    label: (l) => l.navInstances,
    icon: ShellIcons.forRoute(Routes.instances),
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
/// The rail is permanently [m3.NavigationRail.extended] on purpose. The collapsible variants animate their own width, which would make
/// the body's constraints depend on a control inside the rail - a layout that
/// works until someone collapses it on a narrow window. A launcher is not short
/// of horizontal space at its minimum window size, so labels are always visible
/// and the body is always [Expanded].
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

    return m3.Column(
      children: [
        const _ShellHeader(),
        m3.Expanded(
          child: m3.Row(
            children: [
              m3.NavigationRail(
                extended: true,
                minExtendedWidth: 216,
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

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final motion = MotionScope.of(context);
    final scheme = m3.Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.path;
    final subtitle = routeTitle(l10n, location);

    return m3.Container(
      height: height,
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainer,
        border: m3.Border(
          bottom: m3.BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      padding: const m3.EdgeInsets.symmetric(horizontal: 16),
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
          const m3.Spacer(),
          m3.Text(
            l10n.appTitle,
            style: AppTheme.caption(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
