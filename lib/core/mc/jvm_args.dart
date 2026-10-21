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

  // Legacy: a single space-separated string. Split on whitespace because no
  // placeholder value may contain a space that survives as one token — paths
  // are passed as separate argv entries by the caller, not concatenated.
  final raw = version.minecraftArguments ?? '';
  if (side == ArgSide.jvm) return const [];
  return [
    for (final token in raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty))
      expandPlaceholders(token, vars),
  ];
}

/// The memory/GC block a modern version suggests, purely for pre-filling the
/// settings UI. Returns `[]` for versions that do not declare one.
List<String> suggestedJvmDefaults(VersionJson version, RuleContext host) => [
  for (final entry in version.arguments.defaultUserJvm)
    if (ruleAllows(entry.rules, host))
      for (final v in entry.value)
        expandPlaceholders(
          v,
          const LaunchVariables(
            authPlayerName: '',
            versionName: '',
            gameDirectory: '',
            assetsRoot: '',
            assetIndexName: '',
            authUuid: '',
            authAccessToken: '',
            userType: '',
            versionType: '',
            nativesDirectory: '',
            classpath: '',
          ),
        ),
];
