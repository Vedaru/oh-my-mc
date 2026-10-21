import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';

void main() {
  group('StaggerConfig.stepFor', () {
    const config = StaggerConfig();

    test('a short list keeps the full step', () {
      expect(config.stepFor(4), const Duration(milliseconds: 40));
    });

    test('negative or zero counts do not divide by zero', () {
      expect(config.stepFor(0), const Duration(milliseconds: 40));
      expect(config.stepFor(1), const Duration(milliseconds: 40));
    });

    test('a long list shrinks the step to fit the budget', () {
      // 320ms across the 24 animated items = 13.33ms each.
      expect(config.stepFor(40), const Duration(microseconds: 13333));
      expect(config.stepFor(1000), const Duration(microseconds: 13333));
    });

    test('list length past the cap does not shrink the step further', () {
      // Charging the budget for items that render at rest would starve the
      // cascade: a 1000-item list would get a 0.3ms step and no visible stagger.
      expect(config.stepFor(24), config.stepFor(5000));
    });

    test('the step never exceeds the nominal step', () {
      for (final n in [2, 3, 8, 24, 1000]) {
        expect(config.stepFor(n) <= config.step, isTrue, reason: 'n=$n');
      }
    });

    test('step shrinks monotonically as the list grows', () {
      var previous = config.stepFor(2);
      for (final n in [4, 8, 16, 32, 64, 128]) {
        final current = config.stepFor(n);
        expect(current <= previous, isTrue, reason: 'n=$n');
        previous = current;
      }
    });
  });

  group('StaggerConfig.delayFor', () {
    const config = StaggerConfig();

    test('the first item is not delayed', () {
      expect(config.delayFor(0, itemCount: 10), Duration.zero);
    });

    test('items past the cap are not delayed at all', () {
      expect(config.animates(24), isFalse);
      expect(config.delayFor(30, itemCount: 100), Duration.zero);
      expect(config.delayFor(24, itemCount: 100), Duration.zero);
    });

    test('the item just below the cap still animates', () {
      expect(config.animates(23), isTrue);
      expect(config.delayFor(23, itemCount: 100), isNot(Duration.zero));
    });

    test('a negative index is treated as at rest', () {
      expect(config.animates(-1), isFalse);
      expect(config.delayFor(-1, itemCount: 10), Duration.zero);
    });

    test('delay grows with index inside the cap', () {
      final a = config.delayFor(1, itemCount: 10);
      final b = config.delayFor(5, itemCount: 10);
      expect(a < b, isTrue);
    });
  });

  group('StaggerConfig.totalFor (the whole point of the budget)', () {
    const config = StaggerConfig();

    test('a short list finishes inside budget plus one item', () {
      final total = config.totalFor(4);
      expect(total <= config.maxTotal + config.itemDuration, isTrue);
    });

    test('a 200-item grid is still bounded', () {
      final total = config.totalFor(200);
      expect(total <= config.maxTotal + config.itemDuration, isTrue);
      // Concretely: well under a second, not the package's ~12 s.
      expect(total < const Duration(milliseconds: 1000), isTrue);
    });

    test('total is monotonic and then flat past the cap', () {
      final atCap = config.totalFor(24);
      final pastCap = config.totalFor(1000);
      expect(pastCap, atCap);
    });

    test('an empty list has nothing to animate', () {
      expect(config.totalFor(0), Duration.zero);
    });

    test('custom config is respected', () {
      const slow = StaggerConfig(
        step: Duration(milliseconds: 100),
        maxTotal: Duration(milliseconds: 500),
        maxAnimatedIndex: 3,
      );
      // 500ms budget over 3 animated items leaves 166ms, above the 100ms step.
      expect(slow.stepFor(10), const Duration(milliseconds: 100));
      expect(slow.animates(3), isFalse);
      expect(slow.totalFor(10) <= const Duration(milliseconds: 800), isTrue);
    });
  });

  group('Motion', () {
    test('full motion passes durations through', () {
      expect(Motion.full.of(Durations.base), const Duration(milliseconds: 280));
    });

    test('no motion collapses every duration to zero', () {
      for (final d in [
        Durations.xfast,
        Durations.fast,
        Durations.base,
        Durations.slow,
        Durations.ambient,
      ]) {
        expect(Motion.none.of(d), Duration.zero);
      }
    });

    test('disabled motion suppresses item animation', () {
      expect(Motion.none.animatesItem(0), isFalse);
      expect(Motion.full.animatesItem(0), isTrue);
      expect(Motion.full.animatesItem(99), isFalse);
    });

    test('tokens are ordered', () {
      expect(Durations.xfast < Durations.fast, isTrue);
      expect(Durations.fast < Durations.base, isTrue);
      expect(Durations.base < Durations.slow, isTrue);
      expect(Durations.slow < Durations.ambient, isTrue);
    });
  });
}
