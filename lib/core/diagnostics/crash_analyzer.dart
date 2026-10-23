/// What went wrong, in the launcher's vocabulary rather than Java's.
enum DiagnosisKind {
  outOfMemory,
  outOfMetaspace,
  javaTooOld,
  javaMissing,
  modConflict,
  modMismatch,
  missingDependency,
  mixinFailed,
  archMismatch,
  graphicsDriver,
  networkFailure,
  corruptInstall,
  unknown,
}

/// What the user can actually do about it.
///
/// A diagnosis without an action is a riddle: every one of these maps to a control
/// that already exists in the UI.
enum DiagnosisAction {
  raiseMemory,
  chooseJava,
  installJava,
  openMods,
  openLogs,
  openDownload,
  openSettings,
  retry,
}

/// One finding: what went wrong, the evidence, and the fix.
///
/// Deliberately carries no prose. The sentence a user reads is localised, and a
/// hard-coded English string here would leave Chinese users reading half a
/// translated page - which is exactly what happened when this class owned its text.
/// [CrashCopy] in the UI turns a kind into words.
class Diagnosis {
  const Diagnosis({
    required this.kind,
    required this.evidence,
    required this.actions,
    this.modName,
    this.requiredJava,
    this.exitCode,
  });

  final DiagnosisKind kind;

  /// The log line that gave it away, verbatim - the user may want to check it.
  final String evidence;

  final List<DiagnosisAction> actions;

  /// Named when the pattern knows it (a mixin or dependency failure names a mod).
  final String? modName;

  /// Major version the crash implies, for the Java actions.
  final int? requiredJava;

  /// Set for [DiagnosisKind.unknown], where the code is the only fact.
  final int? exitCode;
}

/// Reads a crash out of a log tail.
///
/// The mapping is a list of patterns, not a parser for Java's output: a crash is
/// identified by the exception that killed the process, and the useful information
/// is *which* exception plus which mod. Everything unmapped falls back to
/// [DiagnosisKind.unknown] with the log tail, which is still better than nothing.
abstract final class CrashAnalyzer {
  /// Returns `null` when the log does not look like a crash.
  ///
  /// [lines] is oldest-first, as displayed. The analysis walks from the end: the
  /// fatal exception is the last thing written, while the same words can appear
  /// harmlessly earlier (a mod that *catches* `NoClassDefFoundError` on purpose).
  static Diagnosis? analyze(List<String> lines, {int? exitCode}) {
    final hasCrash = exitCode != null && exitCode != 0;
    if (lines.isEmpty) {
      return hasCrash
          ? Diagnosis(
              kind: DiagnosisKind.unknown,
              exitCode: exitCode,
              evidence: 'exit code $exitCode',
              actions: const [
                DiagnosisAction.chooseJava,
                DiagnosisAction.openLogs,
              ],
            )
          : null;
    }

    final ordered = [
      for (final line in lines.reversed)
        if (line.trim().isNotEmpty) line,
    ];

    // A clean exit is not a crash, however scary the log looks: mods log
    // `NoClassDefFoundError` and `ERROR` lines routinely while probing for optional
    // classes, and diagnosing those would send the user to fix something that works.
    if (!hasCrash && !_looksFatal(ordered)) return null;

    for (final matcher in _matchers) {
      for (final line in ordered) {
        final match = matcher.pattern.firstMatch(line);
        if (match == null) continue;
        final diagnosis = matcher.build(line, match, exitCode);
        if (diagnosis != null) return diagnosis;
      }
    }

    if (!hasCrash) return null;
    return Diagnosis(
      kind: DiagnosisKind.unknown,
      exitCode: exitCode,
      evidence: ordered.first,
      actions: const [DiagnosisAction.openLogs, DiagnosisAction.retry],
    );
  }
}

/// Markers the JVM or the loaders write only when the process is dying.
final _fatalMarkers = RegExp(
  r'has been detected by the Java Runtime Environment|'
  r'FATAL|'
  r'Uncaught exception|'
  r'Crash report (?:saved|complete)|'
  r'Failed to start the minecraft server|'
  r'A fatal error',
  caseSensitive: false,
);

bool _looksFatal(List<String> newestFirst) =>
    newestFirst.take(40).any(_fatalMarkers.hasMatch);

class _Matcher {
  const _Matcher(this.pattern, this.build);

  final RegExp pattern;
  final Diagnosis? Function(String line, RegExpMatch match, int? exitCode)
  build;
}

/// Order matters: the first pattern that matches anywhere in the tail wins, so the
/// most specific and most actionable ones come first.
final _matchers = <_Matcher>[
  // ---------------------------------------------------------------- memory
  // Metaspace before heap: it is an `OutOfMemoryError` too, and the heap pattern
  // would claim it and send the user off to raise -Xmx, which cannot help.
  _Matcher(
    RegExp(r'OutOfMemoryError:\s*(?:Metaspace|Compressed class space)'),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.outOfMetaspace,
      evidence: line,
      actions: const [DiagnosisAction.chooseJava, DiagnosisAction.installJava],
    ),
  ),
  _Matcher(
    RegExp(
      r'OutOfMemoryError.*(?:heap space|unable to create new native thread)',
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.outOfMemory,
      evidence: line,
      actions: const [
        DiagnosisAction.raiseMemory,
        DiagnosisAction.chooseJava,
        DiagnosisAction.openMods,
      ],
    ),
  ),

  // ------------------------------------------------------------------ java
  // Two matchers, because a regex alternation returns the leftmost match, not the
  // most informative one: `version...|UnsupportedClassVersionError` on a line that
  // starts with the class name never looks at the version.
  _Matcher(
    RegExp(
      // Not tied to the rest of the sentence: the JVM's wording changes between
      // versions ("has been compiled by a more recent version" / "only recognizes
      // class file versions"), and the class-file number is the fact that matters.
      r'class file version (\d+)(?:\.0)?',
    ),
    (line, match, _) {
      // Class file 52 = Java 8, 55 = 11, 61 = 17, 65 = 21.
      final needed = int.tryParse(match.group(1) ?? '');
      return Diagnosis(
        kind: DiagnosisKind.javaTooOld,
        evidence: line,
        requiredJava: needed == null
            ? null
            : switch (needed) {
                >= 65 => 21,
                >= 61 => 17,
                >= 55 => 11,
                >= 52 => 8,
                _ => null,
              },
        actions: const [
          DiagnosisAction.chooseJava,
          DiagnosisAction.installJava,
        ],
      );
    },
  ),
  _Matcher(
    RegExp(r'UnsupportedClassVersionError'),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.javaTooOld,
      evidence: line,
      actions: const [DiagnosisAction.chooseJava, DiagnosisAction.installJava],
    ),
  ),
  _Matcher(
    RegExp(
      r'(?:Error: could not open|Error: no such file or directory|'
      r'The system cannot find the file specified).*java|'
      r'java(?:\.exe)? .*: No such file or directory',
      caseSensitive: false,
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.javaMissing,
      evidence: line,
      actions: const [DiagnosisAction.chooseJava, DiagnosisAction.installJava],
    ),
  ),

  // ------------------------------------------------------------------ mods
  _Matcher(
    RegExp(r'Mixin apply for mod (\S+) failed|Mixin apply failed'),
    (line, match, _) => Diagnosis(
      kind: DiagnosisKind.mixinFailed,
      modName: match.group(1),
      evidence: line,
      actions: const [DiagnosisAction.openMods, DiagnosisAction.openLogs],
    ),
  ),
  _Matcher(
    RegExp(
      r'ModResolutionException|Incompatible mod set|Found duplicate mods|'
      r'Duplicate mods? (?:found|for)',
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.modConflict,
      evidence: line,
      actions: const [DiagnosisAction.openMods, DiagnosisAction.openLogs],
    ),
  ),
  _Matcher(
    RegExp(
      r'requires (?:any )?version .* of (?:mod )?([\w-]+).*missing|'
      r'Mod (\S+) requires (?:mod )?(\S+) .*missing',
    ),
    (line, match, _) => Diagnosis(
      kind: DiagnosisKind.missingDependency,
      modName: match.group(1) ?? match.group(3),
      evidence: line,
      actions: const [DiagnosisAction.openMods, DiagnosisAction.openDownload],
    ),
  ),
  _Matcher(
    RegExp(r'NoSuchMethodError|NoClassDefFoundError|ClassNotFoundException'),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.modMismatch,
      evidence: line,
      actions: const [DiagnosisAction.openMods, DiagnosisAction.openDownload],
    ),
  ),

  // ---------------------------------------------------------------- natives
  _Matcher(
    RegExp(
      r'UnsatisfiedLinkError.*(?:lwjgl|glfw|openal)|'
      r'no lwjgl(?:64)? in java\.library\.path',
      caseSensitive: false,
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.archMismatch,
      evidence: line,
      actions: const [DiagnosisAction.openDownload, DiagnosisAction.chooseJava],
    ),
  ),

  // -------------------------------------------------------------- graphics
  _Matcher(
    RegExp(
      r'EXCEPTION_ACCESS_VIOLATION|SIGSEGV|Pixel format not accelerated|'
      r'GLFW error|Could not initialize GLFW|Failed to create (?:window|context)',
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.graphicsDriver,
      evidence: line,
      actions: const [DiagnosisAction.openLogs, DiagnosisAction.openSettings],
    ),
  ),

  // --------------------------------------------------------------- network
  _Matcher(
    RegExp(
      r'java\.net\.(?:UnknownHostException|ConnectException|SocketTimeoutException)|'
      r'Failed to (?:download|fetch) \S+|Connection (?:reset|refused)|'
      r'SSLHandshakeException|ssl',
      caseSensitive: false,
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.networkFailure,
      evidence: line,
      actions: const [DiagnosisAction.retry, DiagnosisAction.openDownload],
    ),
  ),

  // --------------------------------------------------------------- corrupt
  _Matcher(
    RegExp(
      r'ZipException|invalid LOC header|zip END header not found|'
      r'corrupt|CRC32 mismatch',
      caseSensitive: false,
    ),
    (line, _, _) => Diagnosis(
      kind: DiagnosisKind.corruptInstall,
      evidence: line,
      actions: const [DiagnosisAction.openDownload, DiagnosisAction.openLogs],
    ),
  ),
];
