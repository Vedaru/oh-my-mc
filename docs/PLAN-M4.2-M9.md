# Implementation plan — M4.2 → M9

Continues `docs/PLAN-M4.1.md`. That document closed the argv/launch-path work;
this one covers everything from "the launcher can compute a command line" to
"a user can install, launch, browse mods, and recover from a crash".

Everything below was re-derived from the tree, not copied from the earlier
checklists. Where this file and an older plan disagree, this file wins.

---

## 0. Where the code actually is

Measured, not remembered: `flutter analyze` clean, **447 tests + 1 skipped**,
`flutter build linux --debug` produces a bundle.

### 0.1 Landed this milestone

| Area | Files | Tests |
|---|---|---|
| Launch wiring | `lib/data/launch_factory.dart` | `test/data/launch_factory_test.dart` (15) |
| Launch screen | `lib/ui/launch/launch_screen.dart` | `test/ui/launch_and_instances_test.dart` (22) |
| App entry | `lib/main.dart` (paths, overrides, route table) | `test/widget_test.dart` |
| Motion | `MotionEntrance` in `lib/ui/motion/primitives.dart` | via UI tests |
| Download/install | `lib/data/install_providers.dart`, `lib/ui/download/download_screen.dart` | `test/data/install_providers_test.dart` (12), `test/ui/download_screen_test.dart` (14) |
| Host detection | `lib/core/mc/local_host.dart` | covered via the above |

`prepareInstanceLaunch` is the new seam: `Instance` + `LauncherPaths` +
`AppSettings` → `LaunchOutcome`. It is a pure function of its arguments apart
from reading the version file, so every branch is testable without a JVM.

### 0.2 Defects this milestone found (all were silent)

1. **Playtime was never recorded.** `LaunchSession.endedSession` was set and
   read by nobody; `InstanceListNotifier.recordSession` had no caller. Every
   session was lost. Now recorded in `LaunchController._onEvent` — the one place
   a session ends — instead of by a widget, so navigating away mid-session still
   counts it.
2. **A too-old JVM was reported as "no Java".** `selectRuntime` returns `null`
   when nothing satisfies the requirement, and the factory passed that straight
   to `prepareLaunch`, which then emitted `noRuntime`. The user with Java 8 and a
   1.20.1 instance was told to install Java; they had Java. Now the highest
   available runtime is passed so `checkJava` can say *"needs 17, found 8"*.
3. **Deleting the last instance left the launch screen pointing at it.**
   `_commit` used `selectedId ?? current?.selectedId`, which cannot express
   "clear". Fixed with an explicit `clearSelection` flag.
4. **`offlineUuid` produced malformed UUIDs.** It spliced the hex string at the
   wrong offsets, so the version nibble landed in the wrong group. Caught by
   asserting against a known `OfflinePlayer:Notch` value.
5. **Fluent `NavigationPane` threw on first frame.** `effectiveItems` filters
   out `PaneItem`s whose `body` is null, and `selectedItem` then indexed an empty
   list. Every item now has a `body` even though `paneBodyBuilder` ignores it.
6. **Hand-rolled MD5.** Replaced with `crypto`, already a dependency; a subtly
   wrong hash would give a different identity on every server.

### 0.3 Known gaps (do not pretend otherwise)

- `/download`, `/setup`, `/logs` render a "not built yet" placeholder.
- No mod/loader installer: `LoaderKind` exists in the model, nothing acts on it.
- No Microsoft sign-in. Every launch is offline with a derived UUID.
- The instance detail route (`/instances/:id`) renders the grid, not a detail page.
- Log console is a 2000-line tail with no filtering, search or export.

---

## 1. Guiding constraints

These are not preferences; they are the reason the plan is shaped this way.

1. **PCL is a behaviour reference only.** No code, XAML, string tables or icons
   are copied. Feature parity is the goal; the implementation is ours.
2. **`lib/core/` never imports Flutter.** Everything below `lib/core/` must be
   testable with `dart test` semantics — no `BuildContext`, no `dart:ui`. This is
   enforced by review, and it is why install/launch logic is separated from the
   screens that drive it.
3. **Every user-visible string goes through `AppLocalizations`.** `en` + `zh`
   (`zh_Hans`; `zh_Hant` falls back). The ARB test enforces key parity *and* a
   description on every `en` message, so a new string without a translator note
   fails CI.
4. **Motion is a policy, not a decoration.** All durations/curves live in
   `lib/ui/motion/tokens.dart`; content code never writes a raw `Duration`. The OS
   reduced-motion setting ORs with the user's switch and can only turn motion
   *off*.
5. **A failure must be actionable.** Every error path names what failed *and*
   what the user can do. `LaunchBlocker` carries `message` + `remedy` for exactly
   this reason; a bare "failed" is a bug.

---

## 2. Milestones

Each milestone is independently shippable and has an exit criterion that is a
test, not an opinion.

### M5 — Download & install (the missing half of the launcher)

**Why now:** `VersionInstaller` works and is tested, but nothing in `lib/` calls
it. That is the same "machinery with no caller" problem M3.5 fixed for the
installer internals, one layer up. Until this lands, a user cannot get a version
onto disk from the UI, so the launch screen can only ever report
`missingVersion`.

| Task | Deliverable |
|---|---|
| 5.1 | `VersionManifestService` provider + `installController` (Notifier) with stage progress mirrored from `InstallProgress` | ✅ |
| 5.2 | `/download` screen: version list (release/snapshot toggle), search, "Install" per row | ✅ |
| 5.3 | Progress UI: per-stage bars, byte counters, cancel; cancel must leave no half-tree (`VersionInstaller` already extracts atomically) | ✅ |
| 5.4 | Installed-version detection: read `versions/*/` and mark rows already installed | ✅ |
| 5.5 | Java acquisition: when `noRuntime`/`javaTooOld`, offer the managed download from the UI instead of only a message | ⬜ (moved to M5.5, below) |
| 5.6 | Networking: surface `MirrorChain` choice in `/setup` (official / BMCLAPI / auto) | ⬜ (needs `/setup`; M8) |

**Exit:** from a clean data directory, install 1.20.1 through the UI, then launch
it, with no terminal involved. An integration test drives the installer against a
local `HttpServer` fixture.

#### What M5 actually shipped

- `lib/data/install_providers.dart` — `InstallController` (one install at a time,
  cancel via `CancelToken`, `ref.mounted` guards on every async state write),
  `InstalledVersions` (ids read from `versions/<id>/<id>.json`, so a half-deleted
  directory is not advertised as installed), `VersionListController`.
- `lib/ui/download/download_screen.dart` — one page, not a wizard: toolbar
  (search + snapshot toggle), version rows, and an install panel that stays after
  the install ends so the result is readable.
- `lib/core/mc/local_host.dart` — the single place that asks the platform, using
  `dart:ffi`'s `Abi.current()` rather than substring-matching `Platform.version`.
  `launch_factory.dart` now uses it too, deleting its duplicate `_hostOs`/`_hostArch`.
- Injectables for tests: `installerFactoryProvider`, `manifestServiceFactoryProvider`.

**Two real bugs found by the tests:**

1. `InstallRunning.fraction` used the byte counter only, so every non-download
   phase (natives, assets, verify — up to a minute on a large version) showed a
   determinate bar frozen at the *previous* phase's value. Non-download phases
   now derive from `step/steps`.
2. The speed row rendered `1.0 MB/s/s`: `formatRate()` already appends `/s` and the
   ARB message adds another. The screen now formats with `formatBytes()` and lets
   the message own the unit.

**Test strategy note (worth remembering):** a `testWidgets` body runs in a
fake-async zone, so a real `HttpServer` + `HttpClient` exchange inside it stalls —
`pumpAndSettle` never returns and the install never progresses. So the pipeline is
covered in `test/data/install_providers_test.dart` (plain `test`, real
`HttpServer` via `test/support/mini_world.dart`), and the screen is covered in
`test/ui/download_screen_test.dart` by scripting the *state* (`ScriptedInstallController`).
Each side tests the half it can test honestly.

**Risks:** the manifest/asset index is ~3000 files; the UI must stay responsive
(progress events arrive per chunk — throttle to animation frames, not per chunk).
Java download is ~180 MB and needs a resumable path.

### M6 — Instance detail

**Why now:** the grid is a list of names. PCL's core value is per-instance
configuration, and `Instance` already carries the fields (`memoryMb`, `jvmArgs`,
`gameArgs`, `javaPath`, `isolation`, `loader`) with no UI to set them.

| Task | Deliverable |
|---|---|
| 6.1 | `/instances/:id` route → real detail page (currently the grid) |
| 6.2 | General tab: name, version, loader, isolation — with the isolation switch warning that moving files is not done automatically |
| 6.3 | Java tab: detected runtimes, per-instance override, "test" button that prints `java -version` |
| 6.4 | Memory/JVM tab: heap slider with the same 512–65536 clamp as `settings.dart`, extra JVM args |
| 6.5 | Playtime + last-played summary, "open folder" |
| 6.6 | Delete with confirmation, and the mount-time guarantee that deleting removes the directory |

**Exit:** every `Instance` field is reachable from the UI; a widget test proves
each edit round-trips to the store.

### M7 — Mod loaders

**Why now:** `LoaderKind` is inert. This is the largest remaining feature gap
versus PCL and the one users actually pick a launcher for.

| Task | Deliverable |
|---|---|
| 7.1 | Loader metadata clients: Fabric (meta API), Quilt (meta API), Forge/NeoForge (maven + promotions) — `lib/core/loaders/` |
| 7.2 | Version pairing rules: which loader builds support which MC version |
| 7.3 | Install pipeline: fetch installer/profile JSON, write `inheritsFrom` child version, run the processor chain (Forge needs `installertools` on Java 8) |
| 7.4 | UI: loader picker in the instance create/edit flow |
| 7.5 | Launch verification for each loader against a real install |

**Exit:** fabric, quilt, forge and neoforge each install and reach the main menu
on at least one MC version, verified by an end-to-end script (not a unit test —
this needs the real installer jars).

**Risks:** Forge's processor chain is the hardest thing in the whole project and
its failure modes are opaque. Budget for it; do not schedule it in the same week
as anything else.

### M8 — Mods, resources, worlds

| Task | Deliverable |
|---|---|
| 8.1 | Modrinth + CurseForge search/download (`lib/core/resource/`) |
| 8.2 | Mod list per instance: enable/disable by rename to `.disabled`, delete, dependency check |
| 8.3 | Drag-and-drop `.jar` import with the loader-compatibility check |
| 8.4 | Resource packs + shaderpacks (folder semantics differ: `resourcepacks/` vs `shaderpacks/`) |
| 8.5 | World list with backup-before-delete |

**Exit:** install a mod from search, see it in the list, launch, and confirm the
game loads it.

### M9 — Accounts, crash analysis, polish

| Task | Deliverable |
|---|---|
| 9.1 | Microsoft device-code sign-in, token refresh, offline fallback; replaces `offlineUuid` when signed in |
| 9.2 | Crash analysis: parse `hs_err_pid*.log` and the last 200 log lines into named causes (wrong Java, OOM, missing mod dependency, GL driver) |
| 9.3 | Log console: filter by channel, search, copy diagnostics (Java, memory, argv, version) |
| 9.4 | `/setup`: language, theme, motion, download source, default memory, player name |
| 9.5 | Update check + portable-mode data directory |

**Exit:** a deliberately broken launch (Java 8 + 1.20.1) produces a diagnosis
naming Java, not a stack trace.

---

## 3. Cross-cutting work (each milestone, not a phase)

- **i18n:** new strings land with `en` + `zh` + a description in the same commit.
- **Tests:** every defect above was found by *writing the test that should have
  existed*. Continue that: a bug fix without a regression test is not done.
- **Mutation spot-checks:** for anything with a branch that a test claims to
  cover, invert the branch and confirm a test fails. Two of this milestone's
  defects (playtime, selection clearing) would have been caught this way.
- **No silent `catch`.** Every `catch` either logs to the session log or returns
  a `LaunchBlocker`-style actionable value.

---

## 4. Sequencing rationale

M5 before M6 because the launch screen is currently capped at "version not
installed", and instance settings are meaningless until installing works. M6
before M7 because loader installs need an instance to install *into*, and the
detail page is where that lives. M7 before M8 because most mods are
loader-specific, so a mod browser without loaders serves only vanilla players.
M9 last because accounts and crash analysis are quality multipliers on a launcher
that must first be able to install and launch.

The one ordering that is *not* negotiable: **Forge (7.3) after Fabric (7.1–7.2)**.
Fabric's metadata is simple and proves the inheritance path; Forge's processors
will expose every bug in it, and debugging both at once is how a week disappears.
