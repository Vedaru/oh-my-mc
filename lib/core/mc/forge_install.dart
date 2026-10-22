import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../instance/instance.dart';
import '../net/cancellation.dart';
import 'install_plan.dart';

/// Forge and NeoForge installation.
///
/// These two are the reason "installing a loader" is not always "writing a profile
/// JSON". Fabric and Quilt publish a complete version JSON, so their install is a
/// file write. Forge and NeoForge publish an **installer jar** instead: it patches
/// the vanilla client, runs a set of processors that decompile/recompile pieces of
/// the game, and only then writes `versions/<id>/<id>.json`. There is no way to
/// reproduce that from metadata - the jar has to run, which means a JVM, which
/// means this must happen after the vanilla version is installed and after Java is
/// resolved.
///
/// Everything except running the process is pure or injectable, so the awkward
/// parts (which build to pick, which path the jar lives at, what the version id is
/// called) are unit tests, and the run itself is behind [InstallerRunner].
class ForgeMeta {
  ForgeMeta({
    HttpClient? client,
    Uri? forgePromotions,
    Uri? forgeMaven,
    Uri? neoForgeMetadata,
    Uri? neoForgeMaven,
  }) : _client = client ?? HttpClient(),
       _forgePromotions =
           forgePromotions ??
           Uri.parse(
             'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json',
           ),
       _forgeMaven =
           forgeMaven ?? Uri.parse('https://maven.minecraftforge.net'),
       _neoForgeMetadata =
           neoForgeMetadata ??
           Uri.parse(
             'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml',
           ),
       _neoForgeMaven =
           neoForgeMaven ?? Uri.parse('https://maven.neoforged.net/releases');

  final HttpClient _client;
  final Uri _forgePromotions;
  final Uri _forgeMaven;
  final Uri _neoForgeMetadata;
  final Uri _neoForgeMaven;

  /// `1.20.1-forge-47.2.0`, which is the directory name Forge's own installer
  /// writes. NeoForge does not repeat the game version - `neoforge-21.1.80` - and
  /// the two must stay distinguishable because both are launch lookup keys.
  static String versionId(
    LoaderKind kind,
    String gameVersion,
    String loaderVersion,
  ) => switch (kind) {
    LoaderKind.forge => '$gameVersion-forge-$loaderVersion',
    LoaderKind.neoforge => 'neoforge-$loaderVersion',
    _ => throw ArgumentError(
      '${kind.name} is not installed by an installer jar',
    ),
  };

  /// The version a modpack author would tell you to use: Forge's "recommended"
  /// promotion, falling back to "latest" for versions that never got a promotion.
  ///
  /// NeoForge has no promotions, so its highest published build whose `21.1` prefix
  /// matches game 1.21.1 is the answer - that prefix *is* the game version in
  /// NeoForge's numbering.
  Future<String> recommendedVersion(
    LoaderKind kind,
    String gameVersion, {
    CancelToken? cancel,
  }) async {
    final text = await _get(
      kind == LoaderKind.forge ? _forgePromotions : _neoForgeMetadata,
      cancel: cancel,
    );
    final version = switch (kind) {
      LoaderKind.forge => _forgePromotion(text, gameVersion),
      LoaderKind.neoforge => _neoForgeNewest(text, gameVersion),
      _ => null,
    };
    if (version == null) {
      throw StateError('${kind.label} has no build for $gameVersion');
    }
    return version;
  }

  /// Forge's promotions file is a flat map of `<game>-<channel>` → version.
  static String? _forgePromotion(String text, String gameVersion) {
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['promos'] is! Map) return null;
    final promos = decoded['promos'] as Map;
    for (final channel in ['recommended', 'latest']) {
      final value = promos['$gameVersion-$channel'];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// `1.21.1` → prefix `21.1.`, so `21.1.80` matches and `20.4.x` does not. A game
  /// version without a patch number is the `.0` line, which is how NeoForge names
  /// it too (`1.21` → `21.0.x`).
  static String? _neoForgeNewest(String xml, String gameVersion) {
    final parts = gameVersion.split('.');
    if (parts.length < 2 || parts[0] != '1') return null;
    final patch = parts.length > 2 ? parts[2] : '0';
    final prefix = '${parts[1]}.$patch.';
    final versions = RegExp(r'<version>([^<]+)</version>')
        .allMatches(xml)
        .map((m) => m.group(1)!.trim())
        .where((v) => v.startsWith(prefix))
        .toList();
    if (versions.isEmpty) return null;
    versions.sort(_compareBuilds);
    return versions.last;
  }

  /// Numeric compare segment by segment: `21.1.80` is newer than `21.1.9`, which a
  /// string sort would get backwards.
  static int _compareBuilds(String a, String b) {
    final left = a.split('.').map(int.tryParse).toList();
    final right = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = left[i] ?? 0;
      final r = right[i] ?? 0;
      if (l != r) return l.compareTo(r);
    }
    return left.length.compareTo(right.length);
  }

  Uri installerUrl(
    LoaderKind kind,
    String gameVersion,
    String loaderVersion,
  ) => switch (kind) {
    // Forge names the artifact after the game *and* the loader, inside a folder
    // that repeats both.
    LoaderKind.forge => _forgeMaven.replace(
      path:
          '/net/minecraftforge/forge/$gameVersion-$loaderVersion/'
          'forge-$gameVersion-$loaderVersion-installer.jar',
    ),
    // NeoForge's repository root is `https://maven.neoforged.net/releases`, so the
    // artifact path is *appended* to it: `replace(path: …)` drops `/releases` and
    // the download 404s - which is what the end-to-end run caught.
    LoaderKind.neoforge => _neoForgeMaven.replace(
      path:
          '${_neoForgeMaven.path}/net/neoforged/neoforge/$loaderVersion/'
          'neoforge-$loaderVersion-installer.jar',
    ),
    _ => throw ArgumentError(
      '${kind.name} is not installed by an installer jar',
    ),
  };

  Future<String> _get(Uri url, {CancelToken? cancel}) async {
    final request = await _client.getUrl(url);
    final response = await request.close();
    cancel?.throwIfCancelled('${url.host}${url.path}');
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        '${url.host}${url.path} answered ${response.statusCode}',
      );
    }
    return text;
  }

  void close() => _client.close(force: true);
}

/// Runs the installer jar. Injected in tests, where there is no JVM and no 5 MB jar
/// to run: the fake writes the version JSON the real installer would have written,
/// which is the contract this class actually depends on.
typedef InstallerRunner = Future<ProcessResult> Function({
  required String java,
  required List<String> arguments,
  required String workingDirectory,
});

/// Downloads and runs a Forge/NeoForge installer.
///
/// The precondition is the one Forge itself has: the vanilla version must already
/// be installed *in the same launcher directory*, because the installer patches
/// `versions/<game>/<game>.jar` in place and writes its libraries relative to that
/// directory. Installing into a per-instance tree would therefore work, but
/// installing vanilla after Forge would not - so the controller installs vanilla
/// first and this class refuses to run without it.
class ForgeInstaller {
  ForgeInstaller({
    ForgeMeta? meta,
    InstallerRunner? runner,
    HttpClient? client,
    this.installerDirName = 'installers',
  }) : _meta = meta ?? ForgeMeta(),
       _run = runner ?? _runProcess,
       _client = client ?? HttpClient();

  final ForgeMeta _meta;
  final InstallerRunner _run;
  final HttpClient _client;
  final String installerDirName;

  Future<String> install({
    required LoaderKind kind,
    required String gameVersion,
    required String loaderVersion,
    required GamePaths paths,
    required String java,
    CancelToken? cancel,
    void Function(String detail)? onStage,
  }) async {
    final id = ForgeMeta.versionId(kind, gameVersion, loaderVersion);
    final vanillaJar = File(paths.versionJar(gameVersion));
    if (!vanillaJar.existsSync()) {
      throw StateError(
        'install $gameVersion before $id: the ${kind.label} installer patches '
        'the vanilla client jar',
      );
    }

    // The installer refuses to work in a directory without `launcher_profiles.json`
    // - "you need to run the launcher first" - which is a real obstacle for a
    // launcher that owns its own game tree. An empty profile file is what a fresh
    // official-launcher directory contains, and writing it is also what lets the
    // installer's own tooling recognise the folder as a game directory.
    final profiles = File('${paths.root}/launcher_profiles.json');
    if (!profiles.existsSync()) {
      await profiles.parent.create(recursive: true);
      await profiles.writeAsString(
        jsonEncode({
          'profiles': <String, Object>{},
          'settings': <String, Object>{},
          'version': 3,
        }),
        flush: true,
      );
    }

    onStage?.call('${kind.label} $loaderVersion');
    final url = _meta.installerUrl(kind, gameVersion, loaderVersion);
    final jarPath = await _download(
      url,
      '${paths.root}/$installerDirName/$id-installer.jar',
      cancel: cancel,
    );
    cancel?.throwIfCancelled('${kind.label} installer');

    onStage?.call('${kind.label} installer');
    // `--installClient <dir>` is the documented headless form; the working
    // directory matters too, because the installer resolves some paths relative to
    // it rather than to the argument.
    final result = await _run(
      java: java,
      arguments: ['-jar', jarPath, '--installClient', paths.root],
      workingDirectory: paths.root,
    );
    cancel?.throwIfCancelled('${kind.label} installer');

    if (result.exitCode != 0) {
      throw StateError(
        '${kind.label} installer exited ${result.exitCode}: '
        '${_tail('${result.stdout}${result.stderr}')}',
      );
    }
    // Exit code 0 is not proof: the processor chain has been known to "succeed"
    // while skipping a step whose output already existed. The version JSON is the
    // single thing the launch pipeline needs, so its absence is the failure.
    if (!File(paths.versionJson(id)).existsSync()) {
      throw StateError(
        '${kind.label} installer wrote no versions/$id/$id.json: '
        '${_tail('${result.stdout}${result.stderr}')}',
      );
    }
    return id;
  }

  Future<String> _download(
    Uri url,
    String destination, {
    CancelToken? cancel,
  }) async {
    final file = File(destination);
    await file.parent.create(recursive: true);
    final request = await _client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
        '${url.host}${url.path} answered ${response.statusCode}',
      );
    }
    final sink = file.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
    cancel?.throwIfCancelled(url.pathSegments.last);
    return file.path;
  }

  /// The last few lines: an installer's failure is at the end of its output, and a
  /// message that starts with the jar's banner says nothing.
  static String _tail(String output, {int lines = 6}) {
    final all = output
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (all.length <= lines) return all.join('\n');
    return all.sublist(all.length - lines).join('\n');
  }

  static Future<ProcessResult> _runProcess({
    required String java,
    required List<String> arguments,
    required String workingDirectory,
  }) => Process.run(
    java,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: false,
  );

  void close() {
    _meta.close();
    _client.close(force: true);
  }
}
