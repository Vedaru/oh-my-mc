import 'dart:convert';
import 'dart:io';

import 'package:oh_my_mc/core/mc/asset_index.dart';
import 'package:oh_my_mc/core/mc/version_json.dart';

/// Loads the captured Mojang metadata in `test/fixtures/mc/`.
///
/// These are real (trailing-trimmed) responses, so tests exercise the shapes
/// Mojang actually ships rather than hand-written ideals. They are committed,
/// so nothing here touches the network.
Directory get fixtureDir => Directory('test/fixtures/mc');

Map<String, dynamic> loadJson(String name) =>
    jsonDecode(File('${fixtureDir.path}/$name').readAsStringSync())
        as Map<String, dynamic>;

VersionJson loadVersion(String id) =>
    VersionJson.fromJson(loadJson('version_$id.json'));

AssetIndex loadAssetIndex(String versionId) =>
    AssetIndex.fromJson(loadJson('asset_index_$versionId.json'));

/// Version ids captured by `tool/capture_fixtures.dart`.
const capturedVersions = <String>[
  '26.3',
  '1.20.1',
  '1.12.2',
  '1.8.9',
  '1.6.4',
  '1.5.2',
];
