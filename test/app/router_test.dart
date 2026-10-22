import 'package:animations/animations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oh_my_mc/app/app_root.dart';
import 'package:oh_my_mc/app/providers.dart';
import 'package:oh_my_mc/app/router.dart';
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/data/settings.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';

/// Renders the route's path as visible text, so a test can assert *which* route
/// resolved without depending on any screen's design.
Widget labelledScreens(BuildContext context, GoRouterState state) =>
    Text('route:${state.uri.path}');

/// Mounts the real app root around the route table under test.
///
/// Returns the container so a test can change settings and prove the app reacts.
/// The router is deliberately *not* returned: [AppRoot] builds it, and returning
/// a second instance here would let a test navigate a router that is not the one
/// on screen. Use [liveRouter] instead.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  String initialLocation = Routes.launch,
  AppSettings settings = AppSettings.defaults,
  Motion? motion,
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWith(
        (ref) => MemorySettingsStore(settings),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: AppRoot(
        initialLocation: initialLocation,
        screens: labelledScreens,
        overrideMotion: motion,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return container;
}

/// Finds the live router from the mounted FluentApp rather than trusting the
/// local one, which would let a bug where AppRoot ignores [initialLocation] pass.
/// A context *inside* the localized subtree.
///
/// `find.byType(MaterialApp)` resolves to the app's own element, which sits above
/// the `Localizations` widget it installs - reading `l10n` there throws, which is
/// exactly the wiring bug the extension is designed to make loud.
BuildContext localizedContext(WidgetTester tester) =>
    tester.element(find.text('route:${Routes.launch}'));

GoRouter liveRouter(WidgetTester tester) {
  final app = tester.widget<m3.MaterialApp>(find.byType(m3.MaterialApp));
  return app.routerConfig! as GoRouter;
}

void main() {
  testWidgets('every route in the table is reachable', (tester) async {
    await pumpApp(tester);
    final router = liveRouter(tester);

    for (final path in [
      Routes.launch,
      Routes.instances,
      Routes.download,
      Routes.setup,
      Routes.logs,
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(
        find.text('route:$path'),
        findsOneWidget,
        reason: '$path did not render',
      );
    }
  });

  testWidgets('an instance deep link resolves to the detail route', (
    tester,
  ) async {
    await pumpApp(tester);

    liveRouter(tester).go(Routes.instanceDetail('abc123'));
    await tester.pumpAndSettle();

    expect(find.text('route:/instances/abc123'), findsOneWidget);
  });

  testWidgets('the detail route is a child, so back returns to the list', (
    tester,
  ) async {
    await pumpApp(tester, initialLocation: Routes.instances);
    // Pushing, not going: `go` replaces the stack and there would be nothing to
    // pop. This is what tapping an instance tile does.
    liveRouter(tester).push(Routes.instanceDetail('abc123'));
    await tester.pumpAndSettle();
    expect(find.text('route:/instances/abc123'), findsOneWidget);

    liveRouter(tester).pop();
    await tester.pumpAndSettle();
    expect(find.text('route:${Routes.instances}'), findsOneWidget);
  });

  testWidgets(
    'an unknown location lands on the home grid instead of crashing',
    (tester) async {
      await pumpApp(tester, initialLocation: '/definitely/not/a/route');
      await tester.pumpAndSettle();

      expect(find.text('route:${Routes.instances}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initialLocation is honoured', (tester) async {
    await pumpApp(tester, initialLocation: Routes.logs);
    expect(find.text('route:${Routes.logs}'), findsOneWidget);
  });

  group('page transitions', () {
    testWidgets('full motion animates: both pages are mounted mid-flight', (
      tester,
    ) async {
      await pumpApp(tester, motion: Motion.full);
      liveRouter(tester).go(Routes.instances);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('route:${Routes.launch}'),
        findsOneWidget,
        reason: 'the outgoing page should still be on screen mid-transition',
      );
      expect(find.text('route:${Routes.instances}'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('route:${Routes.launch}'), findsNothing);
    });

    testWidgets('the rail is outside the transition, so it never fades', (
      tester,
    ) async {
      // The shell used to be wrapped around each screen, so the page transition
      // owned the tab bar too: switching tabs faded and slid the whole window.
      // A `ShellRoute` builds the rail once, above the transition. Two signals
      // pin that: one rail exists mid-flight (there used to be one per page),
      // and no transition widget is above it.
      await pumpApp(tester, motion: Motion.full);
      liveRouter(tester).go(Routes.download);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('route:${Routes.launch}'),
        findsOneWidget,
        reason: 'the page itself must still animate',
      );
      expect(find.byType(m3.NavigationRail), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(m3.NavigationRail),
          matching: find.byType(SharedAxisTransition),
        ),
        findsNothing,
        reason: 'the rail must not be animated by the page transition',
      );
    });

    testWidgets('reduced motion settles in one frame, with no transition', (
      tester,
    ) async {
      // The point of collapsing the duration rather than swapping in
      // NoTransitionPage: one code path. This asserts the *effect*, so it still
      // fails if someone reintroduces a fixed duration.
      await pumpApp(tester, motion: Motion.none);
      liveRouter(tester).go(Routes.instances);

      await tester.pump();

      expect(find.text('route:${Routes.instances}'), findsOneWidget);
      expect(
        find.text('route:${Routes.launch}'),
        findsNothing,
        reason: 'reduced motion must not keep the old page around',
      );
    });

    testWidgets('the OS accessibility setting turns motion off by itself', (
      tester,
    ) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      // Motion is on by design; the OS flag overrides it. MotionScope can only
      // ever remove motion, never add it.
      await pumpApp(tester);
      liveRouter(tester).go(Routes.setup);
      await tester.pump();

      expect(find.text('route:${Routes.setup}'), findsOneWidget);
      expect(find.text('route:${Routes.launch}'), findsNothing);
    });

    testWidgets('no app setting can turn motion off', (tester) async {
      // The old `/setup` toggle is gone; a page change still animates, so the
      // transition has to be allowed to finish before the old page is gone.
      await pumpApp(tester);
      liveRouter(tester).go(Routes.download);
      await tester.pumpAndSettle();

      expect(find.text('route:${Routes.download}'), findsOneWidget);
      expect(find.text('route:${Routes.launch}'), findsNothing);
    });
  });

  group('routeTitle', () {
    testWidgets('maps every route to a nav label', (tester) async {
      await pumpApp(tester);
      final l10n = localizedContext(tester).l10n;
      expect(routeTitle(l10n, Routes.launch), l10n.navLaunch);
      expect(routeTitle(l10n, Routes.instances), l10n.navInstances);
      expect(routeTitle(l10n, Routes.download), l10n.navDownload);
      expect(routeTitle(l10n, Routes.setup), l10n.navSetup);
      expect(routeTitle(l10n, Routes.logs), l10n.navLogs);
    });

    testWidgets('an instance detail path titles as the instances list', (
      tester,
    ) async {
      await pumpApp(tester);
      final l10n = localizedContext(tester).l10n;

      expect(
        routeTitle(l10n, Routes.instanceDetail('abc')),
        l10n.navInstances,
        reason: 'the detail screen belongs to the instances section',
      );
    });

    testWidgets('a query string does not confuse the title', (tester) async {
      await pumpApp(tester);
      final l10n = localizedContext(tester).l10n;

      expect(routeTitle(l10n, '${Routes.setup}?tab=java'), l10n.navSetup);
    });
  });

  testWidgets('appPage is the only transition source (shared axis)', (
    tester,
  ) async {
    // A guard against a screen quietly building its own MaterialPageRoute: if
    // every route goes through appPage, this finder sees one per page.
    await pumpApp(tester);
    expect(find.byType(SharedAxisTransition), findsWidgets);
  });
}
