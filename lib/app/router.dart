import 'package:animations/animations.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import '../ui/motion/motion.dart';

/// The app's routes.
///
/// Strings, not an enum, because a route is also a URL fragment and a deep link
/// target; keeping one representation avoids a second mapping table that can
/// drift.
abstract final class Routes {
  static const launch = '/launch';
  static const instances = '/instances';
  static const download = '/download';
  static const setup = '/setup';
  static const logs = '/logs';

  /// Instance detail. [instanceDetail] builds a concrete path.
  static const instanceDetailPattern = '/instances/:id';

  static String instanceDetail(String id) => '/instances/$id';
}

/// Builds the app's [GoRouter].
///
/// [screens] supplies the widget for each route. It is a function rather than a
/// map of widgets because a screen must be rebuilt with its route arguments, and
/// because the real screens are not written yet - the shell can be complete while
/// every route still renders a placeholder, and the route table test can then
/// assert navigation without asserting any visual design.
///
/// [initialLocation] exists for tests and for restoring the last screen.
GoRouter createRouter({
  required Widget Function(BuildContext context, GoRouterState state) screens,
  String initialLocation = Routes.launch,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    // An unknown location is a deep link from a stale bookmark or a typo, never a
    // crash: drop the user on the launch screen, which is always valid.
    onException: (context, state, router) => router.go(Routes.launch),
    routes: [
      _route(Routes.launch, screens),
      // The detail route is a *relative* child (`:id`), which is what makes
      // `/instances/<id>` resolve. A child repeating its parent's segment would
      // be a second, competing table.
      _route(Routes.instances, screens, routes: [_route(':id', screens)]),
      _route(Routes.download, screens),
      _route(Routes.setup, screens),
      _route(Routes.logs, screens),
    ],
  );
}

GoRoute _route(
  String path,
  Widget Function(BuildContext, GoRouterState) screens, {
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  pageBuilder: (context, state) =>
      appPage(context, state: state, child: screens(context, state)),
  routes: routes,
);

/// The single place a page transition is chosen.
///
/// Two decisions live here and nowhere else:
///
///  * **Direction.** The app is a flat, five-item nav pane, so every transition
///    is horizontal. A screen that wants a different axis would have to argue for
///    it here rather than inventing its own page class in a widget file.
///  * **Reduced motion.** Per `PLAN-M1-M4.md` §3, neither animation package
///    honours `MediaQuery.disableAnimations`, so `MotionScope` resolves the policy
///    and the duration is collapsed to zero here. Verified: a zero-duration
///    `CustomTransitionPage` settles in a single pump, so this costs no frames and
///    needs no second page class.
///
/// A screen must never construct its own `PageRoute`; doing so silently opts out
/// of both decisions.
Page<void> appPage(
  BuildContext context, {
  required GoRouterState state,
  required Widget child,
  SharedAxisTransitionType type = SharedAxisTransitionType.horizontal,
}) {
  final motion = MotionScope.of(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: motion.of(Durations.slow),
    reverseTransitionDuration: motion.of(Durations.slow),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: type,
          child: child,
        ),
  );
}

/// Title for the current route, for the window/title bar.
///
/// Returns a localized label so the shell never hardcodes a screen name.
String routeTitle(AppLocalizations l10n, String location) {
  final path = Uri.parse(location).path;
  return switch (path) {
    Routes.instances => l10n.navInstances,
    Routes.download => l10n.navDownload,
    Routes.setup => l10n.navSetup,
    Routes.logs => l10n.navLogs,
    _ when path.startsWith(Routes.instances) => l10n.navInstances,
    _ => l10n.navLaunch,
  };
}
