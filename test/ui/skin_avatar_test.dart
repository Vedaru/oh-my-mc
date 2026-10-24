import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as m3;
import 'package:oh_my_mc/data/skin_providers.dart';
import 'package:oh_my_mc/ui/components/skin_avatar.dart';
import 'package:oh_my_mc/ui/theme/app_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: m3.MaterialApp(
          theme: AppTheme.material(m3.Brightness.dark),
          home: m3.Scaffold(body: m3.Center(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an account with no skin shows its initial, not a broken image', (
    tester,
  ) async {
    await pump(tester, const SkinAvatar(fallbackLabel: 'survival'));

    // Uppercased first character: three offline accounts must not look like one.
    expect(find.text('S'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a name that is not latin still gets one character', (
    tester,
  ) async {
    await pump(tester, const SkinAvatar(fallbackLabel: '史蒂夫'));
    expect(find.text('史'), findsOneWidget);
  });

  testWidgets('a skin is painted from the texture, not shipped as an image', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 64, 64),
      ui.Paint()..color = const ui.Color(0xFFB58863),
    );
    final texture = await tester.runAsync(
      () => recorder.endRecording().toImage(64, 64),
    );

    await pump(
      tester,
      const SkinAvatar(skinUrl: 'https://textures.example/skin'),
      overrides: [
        skinTextureProvider.overrideWith((ref, url) async => texture),
      ],
    );
    // The provider's future resolves on a later frame.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(m3.CustomPaint), findsWidgets);
    expect(find.text('?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
