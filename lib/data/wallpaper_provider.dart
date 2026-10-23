import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The wallpaper as a decoded image, or null when there is none to show.
///
/// Decoded here rather than left to `Image.file`'s lazy resolution: the shell paints it
/// once, and an explicit `ui.Image` gives the caller an honest "not ready yet" state
/// instead of a frame that silently has no picture in it. A file that has moved or is
/// not an image is null, never an exception - a wallpaper must not take the window down.
///
/// `autoDispose` is deliberately *not* used: the shell holds it for the whole session,
/// and re-decoding a 12-megapixel photo on every navigation would be felt.
final wallpaperImageProvider = FutureProvider.family<ui.Image?, String>((
  ref,
  path,
) async {
  final file = File(path);
  try {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final image = await decodeImageFromList(bytes);
    // The decoded image is a native resource; tie its lifetime to the provider so a
    // changed wallpaper does not leak the old one.
    ref.onDispose(image.dispose);
    return image;
  } on Object {
    return null;
  }
});
