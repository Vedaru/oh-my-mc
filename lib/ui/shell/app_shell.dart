import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../motion/motion.dart';
import 'shell_icons.dart';

/// One navigation destination. Derived from [Routes], so a route and its pane
/// item cannot disagree about the path.
class ShellDestination {
  const ShellDestination({
    required this.location,
    required this.label,
    required this.icon,
  });

  final String location;
  final String Function(AppLocalizations l10n) label;
  final IconData icon;
}

/// The destinations, in pane order.
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

/// The application shell: a Fluent `NavigationView` whose selection follows the
/// router rather than its own state.
///
/// The single decision this widget makes is that **the router is the source of
/// truth for navigation state**. `NavigationView` would happily keep its own
/// selected index and drift from the URL after a deep link, a back gesture or a
/// programmatic `context.go()`; taking the index from [location] and treating
/// `onChanged` as a request removes the possibility of the two disagreeing.
class AppShell extends StatelessWidget {
  const AppShell({required this.location, required this.child, super.key});

  /// The current location, from `GoRouterState.uri.path`.
  final String location;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = destinationsFor(l10n);
    final selected = _selectedIndex(destinations, location);

    return NavigationView(
      // The title bar is ours (the app draws its own drag area and window
      // buttons), so the pane does not try to paint one.
      titleBar: const _ShellTitleBar(),
      pane: NavigationPane(
        selected: selected,
        onChanged: (index) => context.go(destinations[index].location),
        items: [
          for (final destination in destinations)
            PaneItem(
              key: ValueKey(destination.location),
              icon: Icon(destination.icon),
              title: Text(destination.label(l10n)),
              // Required even though `paneBodyBuilder` ignores it: Fluent's
              // `NavigationPane.effectiveItems` filters out items whose body is
              // null, and `selectedItem` then indexes an empty list - a
              // RangeError on the first frame, not a cosmetic issue.
              body: const SizedBox.shrink(),
            ),
        ],
      ),
      // The router owns the body, so the pane items carry no body of their own.
      // Without this, NavigationView would render a `PaneItem.body` (empty) and
      // the routed page would never appear.
      paneBodyBuilder: (item, body) => child,
      // The page change is already animated by `appPage`; letting
      // NavigationView animate its own content swap double-animates one
      // navigation.
      transitionBuilder: (child, animation) => child,
    );
  }

  /// Maps a location to a pane index.
  ///
  /// A prefix test, not equality: `/instances/:id` is a child route and must
  /// highlight the Instances item, which is the whole reason this is a function
  /// with a test rather than an `indexOf`. An unknown path falls back to 0 so a
  /// stale deep link still highlights something sane.
  static int _selectedIndex(
    List<ShellDestination> destinations,
    String location,
  ) {
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
}

/// The app's own title bar.
///
/// Fluent's default `NavigationView` bar shows an app name and a back button;
/// neither is wanted here. This one is deliberately minimal — a drag area, the
/// app name, and a per-screen subtitle — because the window controls are native
/// (the `window_manager` side draws them) and duplicating them in Flutter would
/// give the user two close buttons.
class _ShellTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const _ShellTitleBar();

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final motion = MotionScope.of(context);
    final theme = FluentTheme.of(context);
    final location = GoRouterState.of(context).uri.path;
    final subtitle = routeTitle(l10n, location);

    return DragToMoveArea(
      child: SizedBox(
        height: preferredSize.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(ShellIcons.instance, size: 16, color: theme.accentColor),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: motion.of(Durations.fast),
                switchInCurve: MotionCurves.enter,
                switchOutCurve: MotionCurves.exit,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Text(
                  // The key is what makes the switch happen at all: without it
                  // AnimatedSwitcher sees the same widget type and just updates
                  // the text in place.
                  subtitle,
                  key: ValueKey(subtitle),
                  style: theme.typography.caption,
                ),
              ),
              const Spacer(),
              Text(l10n.appTitle, style: theme.typography.caption),
            ],
          ),
        ),
      ),
    );
  }
}
