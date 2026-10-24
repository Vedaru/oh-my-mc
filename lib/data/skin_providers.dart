import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A skin texture, decoded once per URL and kept for the session.
///
/// The texture is a 64×64 PNG on `textures.minecraft.net`, which is a plain CDN: no
/// auth, no rate limit worth worrying about. Cached because an account row rebuilds on
/// every scroll tick and a decode per frame would be a visible stutter.
///
/// Null is a legitimate answer - an offline account has no skin, a texture can 404 after
/// a player changes it - and the widget falls back rather than showing a broken box.
final skinTextureProvider = FutureProvider.family<ui.Image?, String>((
  ref,
  url,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (bytes.isEmpty) return null;
    final image = await decodeImageFromList(Uint8List.fromList(bytes));
    ref.onDispose(image.dispose);
    return image;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
});
