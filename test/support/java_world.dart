import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:oh_my_mc/core/mc/java_provisioner.dart';
import 'package:oh_my_mc/core/net/mirror.dart';

/// A provisioner pinned to the official source only, so a mirror cannot answer
/// in place of the test server.
JavaProvisioner testProvisioner() => JavaProvisioner(
  mirrors: MirrorChain(order: const [DownloadSource.official]),
);

/// LZMA-alone objects produced by a real LZMA encoder (Python's `lzma` module,
/// which writes the same 13-byte header Mojang does: properties `0x5D` and an
/// uncompressed-size field of `-1`).
///
/// Embedded rather than generated: `archive` can only decode LZMA, so a fixture
/// generated in Dart at test time would prove nothing about real objects. These
/// are the real bytes, and the decoded content is asserted below.
abstract final class JavaFixtures {
  /// `bin/java` — a shell script, compressed. Long enough that the compressed
  /// object is genuinely smaller, as it is for real runtime files.
  static String get javaRaw {
    final line = '#!/bin/sh\nexec "\$JAVA_HOME/lib/jvm" "\$@"\n${'x' * 200}\n';
    return line * 12;
  }

  static const javaB64 =
      'XQAAgAD//////////wARiEJGPfQWNHMKDaQ7D2UcupgDDxCGHzxMiLI/9n2TWwMivPnJ/4nSwY+0'
      'cvnq+nwrxc+b9Xi9JpnH4KDp8bJVEQwe//0gpgA=';

  /// `legal/java.base/LICENSE` — the link target, compressed.
  static String get licenseRaw {
    final line =
        '(c) OpenJDK licence text, all rights reserved.\n${'y' * 80}\n';
    return line * 10;
  }

  static const licenseB64 =
      'XQAAgAD//////////wAUGMEiAjFiWfC7I//hIBIM86A0bH9aDsMZ88H5bS72j9nGhLfYqN19'
      'ARIYSc9PuKMGdPZoUQEqkEYGKQnJKAOtP/9iaUAA';

  /// `lib/modules` — the one large file Mojang never compresses. Trimmed to a
  /// few KB here; the point is that it has no `lzma` object at all.
  static String get modulesRaw => List.filled(400, 'MODULES-RAW-ONLY').join();
  static String get modulesB64 => base64Encode(utf8.encode(modulesRaw));

  static Uint8List javaBytes() => base64Decode(javaB64);
  static Uint8List licenseBytes() => base64Decode(licenseB64);
  static Uint8List modulesBytes() => base64Decode(modulesB64);
}

/// A catalog document shaped exactly like `all.json`, including the arm64
/// platforms whose `jre-legacy`/`alpha` arrays are empty in the real file.
Map<String, dynamic> catalogJson({
  List<Map<String, dynamic>>? linuxLegacy,
  List<Map<String, dynamic>>? macArmGamma,
}) => {
  'linux': {
    'jre-legacy': linuxLegacy ?? [_build('8u202')],
    'java-runtime-alpha': [_build('16.0.1.9.1')],
    'java-runtime-gamma': [_build('17.0.15')],
    'java-runtime-delta': [_build('21.0.7')],
    'java-runtime-epsilon': [_build('25.0.1')],
    // A component this launcher does not know about must be ignored, not
    // allowed to win selection.
    'minecraft-java-exe': [_build('14')],
  },
  'windows-x64': {
    'jre-legacy': [_build('8u51')],
    'java-runtime-gamma': [_build('17.0.15')],
  },
  'mac-os': {
    'jre-legacy': [_build('8u74')],
    'java-runtime-gamma': [_build('17.0.15')],
  },
  // Real arm64 manifests list these components but publish nothing for them.
  'mac-os-arm64': {
    'jre-legacy': const <Map<String, dynamic>>[],
    'java-runtime-alpha': const <Map<String, dynamic>>[],
    'java-runtime-beta': const <Map<String, dynamic>>[],
    'java-runtime-gamma': macArmGamma ?? [_build('17.0.15')],
    'java-runtime-delta': [_build('21.0.7')],
  },
  'windows-arm64': {
    'jre-legacy': const <Map<String, dynamic>>[],
    'java-runtime-gamma': [_build('17.0.15')],
  },
};

Map<String, dynamic> _build(String versionName, {String? url}) => {
  'availability': {'group': 0, 'progress': 100},
  'manifest': {
    'sha1': 'a' * 40,
    'size': 1024,
    'url': url ?? 'https://example.invalid/$versionName/manifest.json',
  },
  'version': {'name': versionName, 'released': '2025-05-19T08:24:16+00:00'},
};

/// A runtime file manifest with one compressed file, one raw-only file, one
/// directory, one `link` with a `..`-relative target, and an executable bit.
Map<String, dynamic> runtimeManifestJson({
  required String baseUrl,
  bool includeExecutable = true,
  String javaPath = 'bin/java',
  String modulesPath = 'lib/modules',
  // Real shape: `legal/java.compiler/LICENSE -> ../java.base/LICENSE`, i.e. a
  // sibling package's copy of a licence file that exists in java.base.
  String linkTarget = '../java.base/LICENSE',
  String linkPath = 'legal/java.compiler/LICENSE',
  // The file the link points at. Defaults to the sibling package that
  // `../java.base/LICENSE` resolves to, so a test that moves the whole tree
  // (the macOS bundle) only has to move this one too.
  String? licensePath,
  Map<String, Map<String, dynamic>>? overrides,
}) {
  final java = JavaFixtures.javaBytes();
  final license = JavaFixtures.licenseBytes();
  final modules = JavaFixtures.modulesBytes();

  Map<String, dynamic> object(List<int> bytes, String name) => {
    'sha1': _sha1Of(bytes),
    'size': bytes.length,
    'url': '$baseUrl/$name',
  };

  return {
    'files': {
      'bin': {'type': 'directory'},
      'lib': {'type': 'directory'},
      javaPath: {
        'type': 'file',
        if (includeExecutable) 'executable': true,
        'downloads': {
          'raw': {
            'sha1': _sha1Of(utf8.encode(JavaFixtures.javaRaw)),
            'size': utf8.encode(JavaFixtures.javaRaw).length,
            'url': '$baseUrl/java.raw',
          },
          'lzma': object(java, 'java.lzma'),
        },
      },
      modulesPath: {
        'type': 'file',
        // Raw only, exactly like the real `lib/modules`: no `lzma` object.
        'downloads': {'raw': object(modules, 'modules.raw')},
      },
      licensePath ?? 'legal/java.base/LICENSE': {
        'type': 'file',
        'downloads': {
          'raw': {
            'sha1': _sha1Of(utf8.encode(JavaFixtures.licenseRaw)),
            'size': utf8.encode(JavaFixtures.licenseRaw).length,
            'url': '$baseUrl/license.raw',
          },
          'lzma': object(license, 'license.lzma'),
        },
      },
      linkPath: {'type': 'link', 'target': linkTarget},
      // An entry kind this launcher does not implement: must be skipped, and
      // the install must still succeed.
      'weird-entry': {'type': 'quantum-file'},
      ...?overrides,
    },
  };
}

String _sha1Of(List<int> bytes) => sha1.convert(bytes).toString();

/// A server that serves the catalog, a manifest, and the raw/LZMA objects.
class JavaWorld {
  JavaWorld._(this._server);

  static Future<JavaWorld> start({
    Map<String, dynamic>? catalog,
    Map<String, dynamic>? manifest,
  }) async {
    final world = JavaWorld._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    if (catalog != null) world.publishCatalog(catalog);
    if (manifest != null) world.publishManifest(manifest);
    world._server.listen(world._handle);
    return world;
  }

  final HttpServer _server;

  final Map<String, List<int>> files = {};
  bool failEverything = false;

  /// Held open so a test can cancel a transfer that is genuinely in flight.
  Future<void>? stall;

  int get port => _server.port;
  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  void publishCatalog(Map<String, dynamic> catalog) {
    files['/all.json'] = utf8.encode(jsonEncode(catalog));
  }

  void publishManifest(Map<String, dynamic> manifest) {
    files['/manifest.json'] = utf8.encode(jsonEncode(manifest));
  }

  /// Publishes the three objects a [runtimeManifestJson] refers to.
  void publishObjects() {
    files['/java.lzma'] = JavaFixtures.javaBytes();
    files['/license.lzma'] = JavaFixtures.licenseBytes();
    files['/modules.raw'] = JavaFixtures.modulesBytes();
    files['/java.raw'] = utf8.encode(JavaFixtures.javaRaw);
    files['/license.raw'] = utf8.encode(JavaFixtures.licenseRaw);
  }

  Future<void> _handle(HttpRequest request) async {
    final stall = this.stall;
    if (stall != null) await stall;
    final bytes = files[request.uri.path];
    if (failEverything || bytes == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.add(bytes);
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
