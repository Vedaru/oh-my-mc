import 'host.dart';
import 'rules.dart';
import 'version_json.dart';

/// Values substituted into `${...}` placeholders.
class LaunchVariables {
  const LaunchVariables({
    required this.authPlayerName,
    required this.versionName,
    required this.gameDirectory,
    required this.assetsRoot,
    required this.assetIndexName,
    required this.authUuid,
    required this.authAccessToken,
    required this.userType,
    required this.versionType,
    required this.nativesDirectory,
    required this.classpath,
    this.launcherName = 'oh my mc',
    this.launcherVersion = '0.1.0',
    this.userProperties = '{}',
    this.authXuid = '',
    this.clientId = '',
    this.gameAssets = '',
  });

  final String authPlayerName;
  final String versionName;
  final String gameDirectory;
  final String assetsRoot;
  final String assetIndexName;
  final String authUuid;
  final String authAccessToken;
  final String userType;
  final String versionType;
  final String nativesDirectory;
  final String classpath;
  final String launcherName;
  final String launcherVersion;
  final String userProperties;
  final String authXuid;
  final String clientId;
  final String gameAssets;
}

/// Expands the placeholders a modern version uses, falling back to the legacy
/// ones so one substitution table serves both eras.
String expandPlaceholders(String input, LaunchVariables vars) {
  if (!input.contains(r'${')) return input;
  return input.replaceAllMapped(_pattern, (m) {
    final key = m.group(1)!;
    return switch (key) {
      'auth_player_name' => vars.authPlayerName,
      'version_name' => vars.versionName,
      'game_directory' => vars.gameDirectory,
      'assets_root' || 'game_assets' => vars.assetsRoot,
      'assets_index_name' => vars.assetIndexName,
      'auth_uuid' => vars.authUuid,
      'auth_access_token' || 'auth_session' => vars.authAccessToken,
      'user_type' => vars.userType,
      'version_type' => vars.versionType,
      'natives_directory' => vars.nativesDirectory,
      'classpath' => vars.classpath,
      'launcher_name' => vars.launcherName,
      'launcher_version' => vars.launcherVersion,
      'user_properties' => vars.userProperties,
      'auth_xuid' => vars.authXuid,
      'clientid' => vars.clientId,
      _ => m.group(0)!,
    };
  });
}

final _pattern = RegExp(r'\$\{([a-zA-Z0-9_]+)\}');

/// Which argument list to render.
enum ArgSide { jvm, game }

/// Renders an argument list for one host.
///
/// @param includeJvmDefaults when false (the default) `arguments.default-user-jvm`
///   is ignored: those entries carry `-Xmx`/GC choices the user owns.
List<String> renderArguments(
  VersionJson version,
  ArgSide side,
  RuleContext host,
  LaunchVariables vars,
) {
  if (version.usesModernArguments) {
    final entries = side == ArgSide.jvm
        ? version.arguments.jvm
        : version.arguments.game;
    return [
      for (final entry in entries)
        if (ruleAllows(entry.rules, host))
          for (final v in entry.value) expandPlaceholders(v, vars),
    ];
  }

  // Legacy: a single space-separated game-arg string, and *no* JVM args in the
  // metadata at all. Up to 1.12.2 Mojang's launcher supplied the JVM block
  // itself, so it has to be synthesized here or the JVM is started with neither
  // a classpath nor a natives directory and cannot find its main class.
  if (side == ArgSide.jvm) {
    return [
      '-Djava.library.path=${vars.nativesDirectory}',
      '-cp',
      vars.classpath,
    ];
  }

  final raw = version.minecraftArguments ?? '';
  return [
    for (final token in raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty))
      expandPlaceholders(token, vars),
  ];
}
