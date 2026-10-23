import '../../core/diagnostics/crash_analyzer.dart';
import '../../l10n/l10n.dart';

/// The words for a [Diagnosis].
///
/// Lives in the UI layer on purpose: a crash sentence is user-facing text, and text
/// that is not in the ARB files is text that stays English in a Chinese UI. The core
/// analyzer only decides *what* happened; this decides how to say it.
class CrashCopy {
  const CrashCopy({required this.title, required this.body});

  final String title;
  final String body;

  factory CrashCopy.of(Diagnosis diagnosis, AppLocalizations l10n) {
    final mod = diagnosis.modName;
    final java = diagnosis.requiredJava;
    final code = diagnosis.exitCode ?? 0;

    return switch (diagnosis.kind) {
      DiagnosisKind.outOfMemory => CrashCopy(
        title: l10n.diagOutOfMemoryTitle,
        body: l10n.diagOutOfMemoryBody,
      ),
      DiagnosisKind.outOfMetaspace => CrashCopy(
        title: l10n.diagOutOfMetaspaceTitle,
        body: l10n.diagOutOfMetaspaceBody,
      ),
      // Two shapes: "needs Java 17" when the class-file version was readable, and
      // the vaguer sentence when it was not.
      DiagnosisKind.javaTooOld => CrashCopy(
        title: java == null
            ? l10n.diagJavaTooOldTitle
            : l10n.diagJavaTooOldNamedTitle(java),
        body: java == null
            ? l10n.diagJavaTooOldBody
            : l10n.diagJavaTooOldNamedBody(java),
      ),
      DiagnosisKind.javaMissing => CrashCopy(
        title: l10n.diagJavaMissingTitle,
        body: l10n.diagJavaMissingBody,
      ),
      DiagnosisKind.modConflict => CrashCopy(
        title: l10n.diagModConflictTitle,
        body: l10n.diagModConflictBody,
      ),
      DiagnosisKind.modMismatch => CrashCopy(
        title: l10n.diagModMismatchTitle,
        body: l10n.diagModMismatchBody,
      ),
      DiagnosisKind.missingDependency => CrashCopy(
        title: l10n.diagMissingDependencyTitle,
        body: l10n.diagMissingDependencyBody,
      ),
      DiagnosisKind.mixinFailed => CrashCopy(
        title: mod == null
            ? l10n.diagMixinFailedTitle
            : l10n.diagMixinFailedNamedTitle(mod),
        body: mod == null
            ? l10n.diagMixinFailedBody
            : l10n.diagMixinFailedNamedBody(mod),
      ),
      DiagnosisKind.archMismatch => CrashCopy(
        title: l10n.diagArchMismatchTitle,
        body: l10n.diagArchMismatchBody,
      ),
      DiagnosisKind.graphicsDriver => CrashCopy(
        title: l10n.diagGraphicsDriverTitle,
        body: l10n.diagGraphicsDriverBody,
      ),
      DiagnosisKind.networkFailure => CrashCopy(
        title: l10n.diagNetworkFailureTitle,
        body: l10n.diagNetworkFailureBody,
      ),
      DiagnosisKind.corruptInstall => CrashCopy(
        title: l10n.diagCorruptInstallTitle,
        body: l10n.diagCorruptInstallBody,
      ),
      DiagnosisKind.unknown => CrashCopy(
        title: l10n.diagUnknownTitle('$code'),
        body: l10n.diagUnknownBody,
      ),
    };
  }
}
