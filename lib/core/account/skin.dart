import 'dart:ui' as ui;

/// Where a Minecraft skin's parts are inside its 64×64 texture.
///
/// The head is the only part this launcher draws: an account row is 44 px tall, and the
/// face is what a player recognises. The numbers are the game's own - a skin is a 64×64
/// PNG whose head occupies (8,8)-(16,16), with a hat/overlay layer at (40,8) that a
/// player without a hat leaves transparent.
///
/// Kept as a pure function of the texture size because getting it wrong is invisible in
/// a diff and obvious on screen: a wrong rect shows a corner of an arm.
class SkinGeometry {
  const SkinGeometry._();

  /// The face, without the overlay layer.
  static ui.Rect face(ui.Image image) => _rect(image, 8, 8, 16, 16);

  /// The face's overlay (hats, glasses). Drawn over [face], not instead of it.
  static ui.Rect faceOverlay(ui.Image image) => _rect(image, 40, 8, 48, 16);

  /// Whether this texture has an overlay layer worth drawing.
  ///
  /// Old skins (`64×32`) have no overlay, and reading (40,8) there lands in the leg
  /// region - which is how a launcher shows a player's leg as their hat.
  static bool hasOverlay(ui.Image image) => image.height >= 64;

  /// `x0,y0` is the top-left of the 8×8 face block; `x1,y1` its bottom-right.
  static ui.Rect _rect(
    ui.Image image,
    double x0,
    double y0,
    double x1,
    double y1,
  ) {
    // A skin is 64 px wide; a 128 px "HD" skin is the same layout at double scale, so
    // the rect is derived from the texture rather than assumed.
    final scale = image.width / 64;
    return ui.Rect.fromLTRB(x0 * scale, y0 * scale, x1 * scale, y1 * scale);
  }
}
