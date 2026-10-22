import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart' as m3e;
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';

/// Mounts one screen the way [AppRoot] would, for tests that own their container.
///
/// The two theme layers are both installed here because the screens use both:
/// `Theme.of` for the Material widgets and `M3ETheme.of` for the expressive ones.
/// A harness that installed only the first would pass while every `M3E*` widget
/// threw or fell back to a default scheme.
Future<void> pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen, {
  Locale locale = const Locale('en'),
  Motion motion = Motion.full,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: m3.MaterialApp(
        locale: locale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        theme: AppTheme.material(Brightness.light),
        builder: (context, child) => m3e.M3ETheme(
          data: AppTheme.expressive(Brightness.light),
          autoTheming: false,
          child: child!,
        ),
        home: MotionScope(
          motion: motion,
          child: m3.Scaffold(
            body: m3.SafeArea(
              child: Padding(
                padding: const m3.EdgeInsets.all(16),
                child: screen,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
