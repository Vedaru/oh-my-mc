import 'host.dart';

/// Port of the launcher's rule evaluation (`rules` arrays on libraries and on
/// individual argument entries).
///
/// Semantics that matter, and that a naive "any allow matches" gets wrong: an
/// entry with no rules is allowed; otherwise evaluation starts at *deny* and
/// every matching rule overwrites the verdict, so `[allow, disallow osx]` means
/// "everywhere except macOS".
bool ruleAllows(List<Rule>? rules, RuleContext ctx) {
  if (rules == null || rules.isEmpty) return true;
  var allowed = false;
  for (final rule in rules) {
    if (_ruleMatches(rule, ctx)) {
      allowed = rule.action == RuleAction.allow;
    }
  }
  return allowed;
}

bool _ruleMatches(Rule rule, RuleContext ctx) {
  if (rule.os != null && !_osMatches(rule.os!, ctx)) return false;
  final features = rule.features;
  if (features != null) {
    for (final entry in features.entries) {
      if (ctx.feature(entry.key) != entry.value) return false;
    }
  }
  return true;
}

bool _osMatches(OsRule os, RuleContext ctx) {
  if (os.name != null && os.name != ctx.os.mcName) return false;
  // Mojang writes `arch: x86` meaning 32-bit; a 64-bit host must not match.
  if (os.arch != null && os.arch != ctx.arch.mcName) return false;
  final range = os.versionRange;
  if (range != null) {
    final v = ctx.osVersion;
    // An unknown OS version cannot satisfy a declared range.
    if (v == null) return false;
    if (range.min != null && compareVersions(v, range.min!) < 0) return false;
    if (range.max != null && compareVersions(v, range.max!) > 0) return false;
  }
  return true;
}

/// Compares dotted numeric versions ("10.0.17134" vs "10.0.9"). Non-numeric
/// segments compare as strings so a malformed version cannot throw.
int compareVersions(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final sa = i < pa.length ? pa[i] : '0';
    final sb = i < pb.length ? pb[i] : '0';
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    final cmp = (na != null && nb != null)
        ? na.compareTo(nb)
        : sa.compareTo(sb);
    if (cmp != 0) return cmp;
  }
  return 0;
}

enum RuleAction {
  allow,
  disallow;

  static RuleAction? fromJson(String? s) => switch (s) {
    'allow' => RuleAction.allow,
    'disallow' => RuleAction.disallow,
    _ => null,
  };
}

class Rule {
  const Rule({required this.action, this.os, this.features});

  factory Rule.fromJson(Map<String, dynamic> json) => Rule(
    action: RuleAction.fromJson(json['action'] as String?) ?? RuleAction.allow,
    os: json['os'] == null
        ? null
        : OsRule.fromJson(json['os'] as Map<String, dynamic>),
    features: (json['features'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v == true),
    ),
  );

  final RuleAction action;
  final OsRule? os;
  final Map<String, bool>? features;

  Map<String, dynamic> toJson() => {
    'action': action.name,
    if (os != null) 'os': os!.toJson(),
    if (features != null) 'features': features,
  };
}

class OsRule {
  const OsRule({this.name, this.arch, this.versionRange});

  factory OsRule.fromJson(Map<String, dynamic> json) => OsRule(
    name: json['name'] as String?,
    arch: json['arch'] as String?,
    versionRange: json['versionRange'] == null
        ? null
        : VersionRange.fromJson(json['versionRange'] as Map<String, dynamic>),
  );

  final String? name;
  final String? arch;
  final VersionRange? versionRange;

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (arch != null) 'arch': arch,
    if (versionRange != null) 'versionRange': versionRange!.toJson(),
  };
}

class VersionRange {
  const VersionRange({this.min, this.max});

  factory VersionRange.fromJson(Map<String, dynamic> json) =>
      VersionRange(min: json['min'] as String?, max: json['max'] as String?);

  final String? min;
  final String? max;

  Map<String, dynamic> toJson() => {
    if (min != null) 'min': min,
    if (max != null) 'max': max,
  };
}

/// Parses a `rules` array, tolerating absence.
List<Rule>? parseRules(Object? json) {
  if (json is! List) return null;
  return [
    for (final r in json)
      if (r is Map<String, dynamic>) Rule.fromJson(r),
  ];
}

List<Map<String, dynamic>> rulesToJson(List<Rule>? rules) => [
  if (rules != null)
    for (final r in rules) r.toJson(),
];
