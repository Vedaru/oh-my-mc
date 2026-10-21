// Captures trimmed real Minecraft metadata into test/fixtures/mc/ so the core
// engine can be tested offline against the shapes Mojang actually publishes.
//
//   dart run tool/capture_fixtures.dart [--out=<dir>] [--objects=<n>]
//
// Fixtures are trimmed, not faked: library lists and argument arrays are kept
// whole because argv/classpath assertions depend on them. Asset index objects
// are sampled (default 40) because only the policy is under test, not the
// content; the `virtual` / `map_to_resources` flags are preserved because they
// *are* the policy.
library;

import 'dart:convert';
import 'dart:io';

const _versions = <String>[
  '26.3',
  '1.20.1',
  '1.12.2',
  '1.8.9',
  '1.6.4',
  '1.5.2',
];

const _manifestUrl =
    'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';

Future<void> main(List<String> argv) async {
  final out = Directory(_arg(argv, 'out') ?? 'test/fixtures/mc');
  final objectSample = int.parse(_arg(argv, 'objects') ?? '40');
  await out.create(recursive: true);

  final client = HttpClient();
  try {
    final manifest = await _getJson(client, _manifestUrl);
    final all = (manifest['versions'] as List).cast<Map<String, dynamic>>();

    final picked = <Map<String, dynamic>>[];
    for (final id in _versions) {
      final entry = all.where((v) => v['id'] == id).firstOrNull;
      if (entry == null) {
        stderr.writeln('missing version in manifest: $id');
        exit(1);
      }
      picked.add(entry);
    }

    // Keep a small head of the manifest so list-ordering tests have real data
    // without committing 278 KB of release history.
    _write(out, 'version_manifest_v2.json', {
      'latest': manifest['latest'],
      'versions': [...picked, ...all.take(8)],
    });

    for (final entry in picked) {
      final id = entry['id'] as String;
      final versionJson = await _getJson(client, entry['url'] as String);
      _write(out, 'version_$id.json', versionJson);

      final index = versionJson['assetIndex'] as Map<String, dynamic>?;
      if (index != null) {
        final idx = await _getJson(client, index['url'] as String);
        _write(out, 'asset_index_$id.json', _sampleIndex(idx, objectSample));
      }
    }
  } finally {
    client.close(force: true);
  }

  stdout.writeln('fixtures written to ${out.path}');
  for (final f in out.listSync().whereType<File>()) {
    stdout.writeln('  ${f.uri.pathSegments.last}  ${f.lengthSync()} B');
  }
}

/// Samples `objects` but keeps every top-level flag, since `virtual` and
/// `map_to_resources` are what the asset policy branches on.
Map<String, dynamic> _sampleIndex(Map<String, dynamic> idx, int limit) {
  final objects = idx['objects'] as Map<String, dynamic>;
  final keys = objects.keys.toList()..sort();
  final kept = <String, dynamic>{};
  for (final k in keys.take(limit)) {
    kept[k] = objects[k];
  }
  return {...idx, 'objects': kept, '_sampled_total': objects.length};
}

Future<Map<String, dynamic>> _getJson(HttpClient client, String url) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
      return jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } on Object catch (e) {
      if (attempt >= 4) rethrow;
      stderr.writeln('retry $attempt for $url ($e)');
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
  }
}

void _write(Directory dir, String name, Object json) {
  final encoder = const JsonEncoder.withIndent(' ');
  File('${dir.path}/$name').writeAsStringSync('${encoder.convert(json)}\n');
}

String? _arg(List<String> argv, String name) {
  for (final a in argv) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}
