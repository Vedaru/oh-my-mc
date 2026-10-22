# M4 implementation notes — launch path

Split out of `PLAN-M3.4-M5.md` §M4 because that section mixed the launch path
(no visual decisions) with the launch screen and instance grid (all visual
decisions). Only the first half is scheduled here; the UI half stays blocked on
a design direction.

## Why this pair of tasks

`docs/PLAN-M3.4-M5.md` put the `LaunchHandle` abstraction in M4.2 and the real
process in M5.2. Reading `launch_service` before writing a handle showed that the
*command line itself* was wrong for every version before 1.13, so there was
nothing worth wrapping. Fixing the argv first, then wrapping it, is the order
that avoids writing a handle around a broken plan.

## What was broken (all found by this milestone, none by a failing test)

1. **Pre-1.13 versions had no `-cp` and no `-Djava.library.path`.** Their metadata
   has no `arguments.jvm`; the vanished Mojang launcher used to add that block.
   `renderArguments(ArgSide.jvm)` returned `[]`, so the argv was
   `java net.minecraft.client.main.Main --username …`. A real Temurin 17 given
   that argv exits 1 with `Could not find or load main class`. 1.12.2, 1.8.9,
   1.6.4 and 1.5.2 were all unrunnable, and two tests asserted this as correct.
2. **Classpath entries were maven-relative.** `buildLibraryGraph` yields
   `com/google/gson/2.10/gson-2.10.jar`; joined straight into `-cp` the JVM
   resolves it against the process CWD, not the game directory.
3. **The client jar was never on the classpath.** Nothing added
   `versions/<id>/<id>.jar`, so even a correct library set had no main class.
4. **`-Dlog4j.configurationFile` pointed at a directory.** The metadata names the
   file in `logging.client.file.id` (`client-1.12.xml`) and separately templates
   `${path}`; substituting `assets/log_configs` made log4j fail silently. Only the
   real-JVM check caught this one.

Defects 2–4 were found by writing `tool/verify_launch.dart` and reading its
output, not by reasoning.

## Files

| File | Role |
|---|---|
| `lib/core/mc/launch_service.dart` | `prepareLaunch`, `buildClasspath`, `LaunchRequest`, `LaunchReady`/`LaunchRefused` |
| `lib/core/mc/jvm_args.dart` | `ArgSide.jvm` now synthesizes the legacy block |
| `lib/core/mc/launch_plan.dart` | `assembleLaunchPlan(separator:)` — the mutable global is opt-out, not the only path |
| `lib/core/mc/arch_compat.dart` | `BlockerCode` gained `noRuntime`, `javaMajorMismatch`, `missingFiles` |
| `tool/verify_launch.dart` | real JDK + real install + stub main class |
| `test/core/launch_service_test.dart` | 18 tests, all offline |

## Design decisions

* **`prepareLaunch` returns a sealed `LaunchOutcome`, not a nullable plan.** The
  caller must handle refusal explicitly; a `null` plan gets `!`-ed eventually.
* **Blockers are split fatal vs advisory.** Fatal: `noRuntime`, `missingFiles`,
  `javaTooOld`, `lwjgl2OnArm64Mac`, `allLibrariesFiltered`,
  `missingNativeForHost`. Advisory: `javaMajorMismatch` — a newer Java runs the
  game, so refusing would be wrong; the user is told because mods may assume the
  declared major.
* **Missing files are checked before spawning.** Handing the JVM a classpath whose
  entries do not exist costs the user a wall of `ClassNotFoundException`; naming
  the count and first missing file costs one `existsSync` per entry.
* **The client jar goes last on the classpath**, matching the vanilla launcher.
  Metadata order in front means a modloader's patched library wins, because
  classpath resolution is first-wins.
* **`separator` is a parameter with the global as fallback.** The global stays for
  the existing tests; new code must pass it, so a test for one OS cannot leak into
  another via mutable state.

## Acceptance

* `flutter test` — **341 passed, 1 skipped**; `flutter analyze` — clean.
* `tool/verify_launch.dart` against Temurin 17 and a real 1.20.1 install
  (3630 files): 11/11 checks pass, JVM exit 0, every one of the 53 classpath
  entries exists on disk.
* Mutation sweep, each restored byte-identical afterwards:

  | Mutation | Tests failing |
  |---|---|
  | drop the client jar from the classpath | 3 |
  | `paths.libraryFile(rel)` without `p.absolute` | 1 (after strengthening — see below) |
  | legacy JVM block → `const []` | 5 |
  | log4j points at the directory | 1 |
  | `javaTooOld` not fatal | 1 |

  The second mutation initially survived: the regression test used an absolute
  temp root, where `p.absolute` is a no-op. The test now uses a relative
  `GamePaths`. Recorded in `AGENTS.md` because the same trap will recur for
  `assetsRoot` and `gameDir`.

## Deliberately not done

* **No `Process.start` yet.** Streaming stdout/stderr, stop/kill and exit codes
  are the next slice; `prepareLaunch` is the input to them.
* **No offline UUID derivation.** `LaunchRequest` takes a uuid so the auth slice
  can supply one; `OfflineUser` is M5.1.
* **No UI.** Not one pixel, because the visual direction is still unanswered.
