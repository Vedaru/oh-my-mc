// Enforces the import law from docs/PLAN-M1-M4.md §2, which a Dart lint cannot
// express: content code must never import the in-SDK Material library, because
// Flutter 3.47 ships a second, type-incompatible `material_ui` package that
// `material_3_expressive`, `go_router` and `animations` already use.
//
//   dart run tool/check_imports.dart
//
// Exits 1 with a list of violations, 0 when clean.
library;

import 'dart:io';

/// Imports that are banned outright, everywhere in `lib/`.
const _globallyBanned = <String, String>{
  'package:flutter/material.dart':
      'Flutter 3.47 ships material_ui separately; mixing them creates two '
      'incompatible theme/localization trees. Import '
      'package:material_ui/material_ui.dart instead.',
  'package:flutter/cupertino.dart':
      'Use package:cupertino_ui/cupertino_ui.dart for the same reason.',
};

/// Imports banned outside an allow-list, with the files permitted to use them.
///
/// These reach the in-SDK Material copy transitively rather than by naming
/// `package:flutter/material.dart`, so the exact-string check above cannot see
/// them. `flutter_localizations` does `import 'package:flutter/material.dart'`
/// itself and installs `GlobalMaterialLocalizations`, whose type comes from that
/// copy - importing it to get `GlobalWidgetsLocalizations` would reintroduce the
/// second tree the law exists to keep out.
const _restricted = <String, ({String reason, Set<String> allowed})>{
  'package:flutter_localizations/flutter_localizations.dart': (
    reason:
        'Pulls the in-SDK Material localizations (and with them the second '
        'Material tree). Only the localization bootstrap may import it, and only '
        'for GlobalWidgetsLocalizations.',
    allowed: {'lib/l10n/l10n.dart'},
  ),
};

/// Layers that must stay Flutter-free so the engine is unit-testable.
const _pureDartLayers = <String>['lib/core/'];

const _flutterPrefixes = <String>[
  'package:flutter/',
  'package:material_ui/',
  'package:cupertino_ui/',
];

final _importPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

Future<void> main(List<String> argv) async {
  final root = Directory(argv.isNotEmpty ? argv.first : '.');
  final lib = Directory('${root.path}/lib');
  if (!lib.existsSync()) {
    stderr.writeln('no lib/ directory under ${root.absolute.path}');
    exit(64);
  }

  final violations = <String>[];

  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceFirst('${root.path}/', '');
    final source = entity.readAsStringSync();

    for (final m in _importPattern.allMatches(source)) {
      final uri = m.group(1)!;
      final line = _lineOf(source, m.start);

      final ban = _globallyBanned[uri];
      if (ban != null) {
        violations.add('$rel:$line  banned import "$uri"\n    -> $ban');
        continue;
      }

      // gen-l10n emits `AppLocalizations.localizationsDelegates`, which names the
      // SDK Material/Cupertino delegates. We never use that list (l10n.dart builds
      // its own), and the file is regenerated on every build, so it cannot be
      // hand-fixed. Exempted from this rule only - test/l10n/delegate_tree_test.dart
      // asserts that nothing we wrote references those delegate types.
      final isGenerated = rel.startsWith('lib/l10n/generated/');
      final restricted = isGenerated ? null : _restricted[uri];
      if (restricted != null && !restricted.allowed.contains(rel)) {
        violations.add(
          '$rel:$line  restricted import "$uri"\n'
          '    -> ${restricted.reason}\n'
          '    -> allowed only in: ${restricted.allowed.join(', ')}',
        );
        continue;
      }

      final isPureLayer = _pureDartLayers.any(rel.startsWith);
      if (isPureLayer && _flutterPrefixes.any(uri.startsWith)) {
        violations.add(
          '$rel:$line  "$uri" in a pure-Dart layer\n'
          '    -> lib/core must not depend on Flutter; inject the host instead.',
        );
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('import law OK (${_countDart(lib)} files checked)');
    return;
  }

  for (final v in violations) {
    stdout.writeln(v);
    stdout.writeln('');
  }
  stdout.writeln('${violations.length} import violation(s)');
  exit(1);
}

int _countDart(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .length;

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;
