import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/account/skin.dart';

/// The skin rect maths, without a picture: getting the head wrong is invisible in a
/// diff and obvious on screen (a corner of an arm where a face should be).
void main() {
  Future<ui.Image> texture(int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    return recorder.endRecording().toImage(width, height);
  }

  test('the face is the 8x8 block at (8,8) of a 64x64 skin', () async {
    final image = await texture(64, 64);
    expect(SkinGeometry.face(image), const ui.Rect.fromLTRB(8, 8, 16, 16));
    expect(SkinGeometry.hasOverlay(image), isTrue);
  });

  test('an HD skin is the same layout at double scale', () async {
    final image = await texture(128, 128);
    expect(SkinGeometry.face(image), const ui.Rect.fromLTRB(16, 16, 32, 32));
    expect(
      SkinGeometry.faceOverlay(image),
      const ui.Rect.fromLTRB(80, 16, 96, 32),
    );
  });

  test('a 64x32 skin has no hat layer to draw', () async {
    // Reading (40,8) on an old skin lands in the leg region: drawing it would put a
    // player's trousers on their head.
    final image = await texture(64, 32);
    expect(SkinGeometry.hasOverlay(image), isFalse);
    expect(SkinGeometry.face(image), const ui.Rect.fromLTRB(8, 8, 16, 16));
  });
}
