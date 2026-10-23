import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/diagnostics/crash_analyzer.dart';

/// Each case is a log tail taken from a real failure mode, then the sentence and
/// the action the user should get. The point of the analyzer is that these are
/// *actionable*: a wrong diagnosis with a wrong button is worse than none.
void main() {
  Diagnosis? analyze(List<String> lines, {int exitCode = 1}) =>
      CrashAnalyzer.analyze(lines, exitCode: exitCode);

  group('memory', () {
    test('a heap OOM offers more memory', () {
      final diagnosis = analyze([
        '[12:00:00] [main/INFO]: Loading 214 mods',
        '[12:00:03] [Render thread/ERROR]: java.lang.OutOfMemoryError: Java heap space',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.outOfMemory);
      expect(diagnosis?.actions, contains(DiagnosisAction.raiseMemory));
    });

    test('a metaspace OOM points at Java, not at memory', () {
      // Same exception class, completely different fix: raising -Xmx does nothing
      // for metaspace.
      final diagnosis = analyze(['java.lang.OutOfMemoryError: Metaspace']);

      expect(diagnosis?.kind, DiagnosisKind.outOfMetaspace);
      expect(diagnosis?.actions, contains(DiagnosisAction.chooseJava));
      expect(diagnosis?.actions, isNot(contains(DiagnosisAction.raiseMemory)));
    });
  });

  group('java', () {
    test('UnsupportedClassVersionError names the Java it needs', () {
      final diagnosis = analyze([
        'java.lang.UnsupportedClassVersionError: net/minecraft/client/main/Main '
            'has been compiled by a more recent version of the Java Runtime '
            '(class file version 61.0), this version of the Java Runtime only '
            'recognizes class file versions up to 52.0',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.javaTooOld);
      expect(diagnosis?.requiredJava, 17);
      expect(diagnosis?.actions, contains(DiagnosisAction.installJava));
    });

    test('a missing runtime is not reported as a too-old one', () {
      final diagnosis = analyze(['Error: could not open `/opt/java/bin/java`']);

      expect(diagnosis?.kind, DiagnosisKind.javaMissing);
      expect(diagnosis?.actions, contains(DiagnosisAction.chooseJava));
    });
  });

  group('mods', () {
    test('a mixin failure names the mod', () {
      final diagnosis = analyze([
        'org.spongepowered.asm.mixin.transformer.throwables.MixinTransformerError: '
            'An error was encountered in transformation',
        'Mixin apply for mod sodiumextra failed',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.mixinFailed);
      expect(diagnosis?.modName, 'sodiumextra');
      expect(diagnosis?.actions, contains(DiagnosisAction.openMods));
    });

    test('an incompatible mod set is a conflict, not a crash to debug', () {
      final diagnosis = analyze([
        'net.fabricmc.loader.impl.FormattedException: Incompatible mod set!',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.modConflict);
    });
  });

  group('native and graphics', () {
    test('an LWJGL link error is an architecture problem', () {
      final diagnosis = analyze([
        'java.lang.UnsatisfiedLinkError: no lwjgl64 in java.library.path',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.archMismatch);
    });

    test('an access violation is the driver', () {
      final diagnosis = analyze([
        '# A fatal error has been detected by the Java Runtime Environment',
        '# EXCEPTION_ACCESS_VIOLATION (0xc0000005) at pc=0x00007ffb2c1e2f10',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.graphicsDriver);
    });
  });

  group('downloads and damage', () {
    test('a failed fetch is a network problem with a retry', () {
      final diagnosis = analyze([
        'java.net.UnknownHostException: files.minecraftforge.net',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.networkFailure);
      expect(diagnosis?.actions, contains(DiagnosisAction.retry));
    });

    test('a broken jar is a corrupt install with a repair', () {
      final diagnosis = analyze([
        'java.util.zip.ZipException: invalid LOC header (bad signature)',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.corruptInstall);
      expect(diagnosis?.actions, contains(DiagnosisAction.openDownload));
    });
  });

  group('what it must not do', () {
    test('a clean exit with a noisy log is not a crash', () {
      // Mods log plenty of scary words while working normally.
      final diagnosis = CrashAnalyzer.analyze([
        '[12:00:00] [main/WARN]: NoClassDefFoundError while probing optional class',
        '[12:00:01] [main/INFO]: Loaded 12 mods',
      ], exitCode: 0);

      expect(diagnosis, isNull);
    });

    test('the last matching line wins over an earlier harmless one', () {
      // A mod catching NoClassDefFoundError at startup is fine; the OOM that
      // killed the game later is what matters.
      final diagnosis = analyze([
        '[12:00:00] [main/WARN]: NoClassDefFoundError: optional/Foo',
        '[12:30:00] [Render thread/FATAL]: java.lang.OutOfMemoryError: Java heap space',
      ]);

      expect(diagnosis?.kind, DiagnosisKind.outOfMemory);
    });

    test('an unknown crash still says something true', () {
      final diagnosis = analyze([
        '[12:00:00] [main/INFO]: weird',
        'boom',
      ], exitCode: 1);

      expect(diagnosis?.kind, DiagnosisKind.unknown);
      // Never a diagnosis without a way forward.
      expect(diagnosis?.actions, isNotEmpty);
      expect(diagnosis?.evidence, isNotEmpty);
    });

    test('no output plus a non-zero exit is still diagnosed', () {
      final diagnosis = CrashAnalyzer.analyze(const [], exitCode: -1073741819);

      expect(diagnosis?.kind, DiagnosisKind.unknown);
      expect(diagnosis?.exitCode, -1073741819);
      expect(diagnosis?.actions, contains(DiagnosisAction.chooseJava));
    });

    test('a diagnosis always carries evidence to quote', () {
      final diagnosis = analyze([
        'java.lang.OutOfMemoryError: Java heap space',
      ]);

      expect(
        diagnosis?.evidence,
        'java.lang.OutOfMemoryError: Java heap space',
      );
    });
  });
}
