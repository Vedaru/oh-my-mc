import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import '../ui/motion/motion.dart';
import '../ui/shell/app_shell.dart';

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

  /// 版本设置 → Mod 管理. A child of the detail route, so the rail keeps the
  /// instance section selected and Back is the browser's own history.
  static const instanceModsSegment = 'mods';

  static String instanceMods(String id) =>
      '/instances/$id/$instanceModsSegment';
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
  String initialLocation = Routes.instances,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    // An unknown location is a deep link from a stale bookmark or a typo, never a
    // crash: drop the user on the launch screen, which is always valid.
    onException: (context, state, router) => router.go(Routes.instances),
    routes: [
      // The rail belongs to the *shell*, not to the page.
      //
      // It used to be wrapped around each screen's widget, which meant the page
      // transition owned it too: switching tabs faded and moved the whole
      // window, tab bar included, because the transition sat above it. A
      // `ShellRoute` builds the rail once and hands the router only the content,
      // so a transition moves the page and nothing else.
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          _route(Routes.launch, screens),
          // The detail route is a *relative* child (`:id`), which is what makes
          // `/instances/<id>` resolve. A child repeating its parent's segment
          // would be a second, competing table.
          _route(
            Routes.instances,
            screens,
            routes: [
              _route(':id', screens, routes: [_route(':mods', screens)]),
            ],
          ),
          _route(Routes.download, screens),
          _route(Routes.setup, screens),
          _route(Routes.logs, screens),
        ],
      ),
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
///  * **Slide, never a fade.** See [PageSlideTransition].
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
}) {
  final motion = MotionScope.of(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: motion.of(Durations.slow),
    reverseTransitionDuration: motion.of(Durations.slow),
    transitionsBuilder: (context, animation, secondary, child) =>
        PageSlideTransition(
          animation: animation,
          secondaryAnimation: secondary,
          child: child,
        ),
  );
}

/// Slides a page in. Never fades it.
///
/// A fade is an `Opacity` over the whole page, so every frame of the move
/// re-rasterises the window offscreen. At this app's 2x device pixel ratio a
/// fullscreen page is ten megapixels, and that is the difference between smooth
/// in a tile and jittery fullscreen. A translation is composited from the
/// page's own raster, which the [RepaintBoundary] keeps valid for the move.
class PageSlideTransition extends StatelessWidget {
  const PageSlideTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = MotionScope.of(context);
    // The incoming page travels a little; the outgoing one drifts the other way
    // at half the distance, so a change reads as one surface moving rather than
    // a sheet landing on top.
    return SlideTransition(
      position: _drift(
        secondaryAnimation,
        MotionCurves.exit,
        const Offset(-0.02, 0),
      ),
      child: SlideTransition(
        position: _drift(animation, motion.curve, const Offset(0.04, 0)),
        child: RepaintBoundary(child: child),
      ),
    );
  }

  static Animation<Offset> _drift(
    Animation<double> parent,
    Curve curve,
    Offset from,
  ) => Tween<Offset>(
    begin: from,
    end: Offset.zero,
  ).chain(CurveTween(curve: curve)).animate(parent);
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
