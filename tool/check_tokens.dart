// Enforces docs/PLAN.md §6.1 / §9: durations and curves live in one place.
//
//   dart run tool/check_tokens.dart
//
// A lint cannot express this, so it is a script in the gate. The rule is blunt
// on purpose - one file owns motion vocabulary, everything else asks for it by
// name. Without it, "reduced motion" silently stops working the moment someone
// writes a bare `Duration(milliseconds: 150)`.
library;

import 'dart:io';

/// Where the rule applies. Network timeouts and retry backoff in `lib/core` are
/// not UI motion and must not be pushed through these tokens — conflating the
/// two is how "reduced motion" ends up disabling a download timeout.
const _scope = 'lib/ui/';

/// The motion library itself owns the vocabulary, so it is exempt.
const _motionLayer = 'lib/ui/motion/';

/// Raw constructs that must not appear outside the motion layer.
final _banned = <String, RegExp>{
  'Duration(milliseconds:': RegExp(r'Duration\s*\(\s*milliseconds\s*:'),
  'Duration(seconds:': RegExp(r'Duration\s*\(\s*seconds\s*:'),
  'Curves.': RegExp(r'\bCurves\.'),
};

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
    if (!rel.startsWith(_scope) || rel.startsWith(_motionLayer)) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // A file may opt out for a single line with a trailing marker, which
      // keeps the escape hatch visible in review.
      if (line.contains('// motion-token-ok')) continue;
      for (final entry in _banned.entries) {
        if (!entry.value.hasMatch(line)) continue;
        violations.add(
          '$rel:${i + 1}  raw ${entry.key} in $_scope\n'
          '    -> import package:oh_my_mc/ui/motion/motion.dart and use a token.',
        );
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('motion tokens OK (${_countDart(lib)} files checked)');
    return;
  }

  for (final v in violations) {
    stdout.writeln(v);
    stdout.writeln('');
  }
  stdout.writeln('${violations.length} token violation(s)');
  exit(1);
}

int _countDart(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .length;
