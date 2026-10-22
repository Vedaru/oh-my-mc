import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/l10n/l10n.dart';
import 'package:oh_my_mc/ui/motion/motion.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';

/// Mounts one screen the way [AppRoot] would, for tests that own their container.
///
/// One theme is installed, matching production: [AppTheme.material] is the only
/// theme in the app, so a harness that installed an extra layer would test a
/// tree the app never builds.
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
