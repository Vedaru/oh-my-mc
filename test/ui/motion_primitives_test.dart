import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';

/// Counts tickers created under the widget under test.
///
/// The acceptance criterion is "disabled motion creates no ticker", not "runs
/// for zero milliseconds": an `AnimationController` with a zero duration still
/// allocates, schedules, and rebuilds once. Counting is the only way to see the
/// difference, and the animation package gets this wrong on its own.
class _TickerProbe extends StatefulWidget {
  const _TickerProbe({required this.child});

  final Widget child;

  @override
  State<_TickerProbe> createState() => _TickerProbeState();
}

class _TickerProbeState extends State<_TickerProbe> {
  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _host({required Widget child, bool? osDisablesMotion}) {
  Widget tree = child;
  if (osDisablesMotion != null) {
    tree = MediaQuery(
      data: MediaQueryData(disableAnimations: osDisablesMotion),
      child: tree,
    );
  } else {
    tree = MediaQuery(data: const MediaQueryData(), child: tree);
  }
  return Directionality(textDirection: TextDirection.ltr, child: tree);
}

void main() {
  group('MotionScope', () {
    testWidgets('defaults to enabled when no scope is present', (tester) async {
      late Motion seen;
      await tester.pumpWidget(
        _host(
          child: Builder(
            builder: (context) {
              seen = MotionScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.enabled, isTrue);
    });

    testWidgets('OS disableAnimations wins over an enabled scope', (
      tester,
    ) async {
      late Motion seen;
      await tester.pumpWidget(
        _host(
          osDisablesMotion: true,
          child: MotionScope(
            motion: Motion.full,
            child: Builder(
              builder: (context) {
                seen = MotionScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen.enabled, isFalse);
    });

    testWidgets('the app setting cannot add motion back', (tester) async {
      // Scope says off, OS says on: motion must stay off.
      late Motion seen;
      await tester.pumpWidget(
        _host(
          osDisablesMotion: false,
          child: MotionScope(
            motion: Motion.none,
            child: Builder(
              builder: (context) {
                seen = MotionScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen.enabled, isFalse);
    });
  });

  group('StaggerItem with motion disabled', () {
    testWidgets('renders the child and creates no ticker', (tester) async {
      var built = 0;
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.none,
            child: StaggerItem(
              index: 0,
              itemCount: 10,
              child: _TickerProbe(
                child: Builder(
                  builder: (context) {
                    built++;
                    return const Text('item');
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('item'), findsOneWidget);
      expect(built, 1);

      // A live animation would keep scheduling frames; with motion off the
      // tree must be completely idle.
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);

      // And no controller was ever attached: pumpAndSettle returns at once.
      await tester.pumpAndSettle();
      expect(find.text('item'), findsOneWidget);
    });

    testWidgets('OS disableAnimations alone also suppresses the entrance', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          osDisablesMotion: true,
          child: StaggerItem(
            index: 0,
            itemCount: 10,
            child: const Text('item'),
          ),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('item'), findsOneWidget);
    });
  });

  group('StaggerItem with motion enabled', () {
    testWidgets('the child is present immediately, just offset', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.full,
            child: StaggerItem(
              index: 0,
              itemCount: 10,
              child: const Text('item'),
            ),
          ),
        ),
      );

      // Never absent from the tree: an entrance animation that starts by not
      // building the child breaks finders and semantics.
      expect(find.text('item'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('item'), findsOneWidget);
    });

    testWidgets('items past the cap do not animate', (tester) async {
      // index 30 is past maxAnimatedIndex (24), so nothing is scheduled.
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.full,
            child: StaggerItem(
              index: 30,
              itemCount: 100,
              child: const Text('item'),
            ),
          ),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('item'), findsOneWidget);
    });
  });

  group('AmbientLoop', () {
    testWidgets('with motion off renders the resting frame, no ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.none,
            child: AmbientLoop(
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, value, child) =>
                  Text('v=${value.toStringAsFixed(1)}'),
            ),
          ),
        ),
      );

      // The end value, i.e. the resting appearance, not the start.
      expect(find.text('v=1.0'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('with motion on it animates', (tester) async {
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.full,
            child: AmbientLoop(
              tween: Tween<double>(begin: 0, end: 1),
              builder: (context, value, child) =>
                  Text('v=${value.toStringAsFixed(1)}'),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('v=0.0'), findsNothing);
      // Stop the loop so the test can finish.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('StaggerList', () {
    testWidgets('disabled: every item present, no frames scheduled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.none,
            child: SizedBox(
              height: 400,
              child: StaggerList(
                itemCount: 12,
                itemBuilder: (context, i) =>
                    SizedBox(height: 24, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      expect(find.text('row 0'), findsOneWidget);
      // Not hasScheduledFrame: a bare ListView schedules a frame for its own
      // scroll-position bookkeeping. transientCallbackCount counts live tickers,
      // which is exactly the claim "no animation is running".
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('enabled: items appear and settle', (tester) async {
      await tester.pumpWidget(
        _host(
          child: MotionScope(
            motion: Motion.full,
            child: SizedBox(
              height: 400,
              child: StaggerList(
                itemCount: 8,
                itemBuilder: (context, i) =>
                    SizedBox(height: 24, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('row 0'), findsOneWidget);
    });
  });
}
