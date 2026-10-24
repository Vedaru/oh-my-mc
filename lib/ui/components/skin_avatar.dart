import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as m3;

import '../../core/account/skin.dart';
import '../../data/skin_providers.dart';

/// A player's face, drawn from their skin.
///
/// Deliberately the *head* and not the whole skin: an account row answers "which
/// identity am I starting as", and a face is what a player recognises. It is painted with
/// `drawImageRect` from the 64×64 texture rather than shipped as an image, because the
/// only source is the player's own upload.
class SkinAvatar extends ConsumerWidget {
  const SkinAvatar({
    this.skinUrl,
    this.size = 28,
    this.fallbackLabel,
    super.key,
  });

  final String? skinUrl;
  final double size;

  /// Shown when there is no skin: the account's initial.
  ///
  /// A generic person icon for every offline account makes three identities look like
  /// one; a letter is the cheapest thing that tells them apart, and it is honest - an
  /// offline account is a name.
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = m3.Theme.of(context).colorScheme;
    final url = skinUrl;
    final image = url == null
        ? null
        : ref.watch(skinTextureProvider(url)).value;

    return m3.Container(
      width: size,
      height: size,
      decoration: m3.BoxDecoration(
        color: scheme.surfaceContainerHigh,
        // MD3's small shape: this is the same 8 dp corner the row's own leading icon
        // slot uses, so a head and an icon occupy one column without disagreeing.
        borderRadius: m3.BorderRadius.circular(size * 0.25),
      ),
      clipBehavior: m3.Clip.antiAlias,
      child: image == null
          // No skin is a state, not an error: an offline account has never had one.
          ? m3.Center(
              child: m3.Text(
                _initial,
                style: m3.TextStyle(
                  fontSize: size * 0.44,
                  fontWeight: m3.FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : m3.CustomPaint(
              painter: _FacePainter(image),
              size: m3.Size(size, size),
            ),
    );
  }
}

/// The first character of the account's name, uppercased; `?` when there is none.
extension on SkinAvatar {
  String get _initial {
    final label = fallbackLabel?.trim() ?? '';
    if (label.isEmpty) return '?';
    return label.characters.first.toUpperCase();
  }
}

/// Paints the face rect of a skin, scaled to the box, plus its hat layer.
class _FacePainter extends m3.CustomPainter {
  const _FacePainter(this.texture);

  final ui.Image texture;

  @override
  void paint(m3.Canvas canvas, m3.Size size) {
    final paint = m3.Paint()..filterQuality = m3.FilterQuality.none;
    final target = m3.Offset.zero & size;
    canvas.drawImageRect(texture, SkinGeometry.face(texture), target, paint);
    if (SkinGeometry.hasOverlay(texture)) {
      canvas.drawImageRect(
        texture,
        SkinGeometry.faceOverlay(texture),
        target,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.texture != texture;
}
