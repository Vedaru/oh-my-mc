# Implementation plan — M4.2 → M9

Continues `docs/PLAN-M4.1.md`. That document closed the argv/launch-path work;
this one covers everything from "the launcher can compute a command line" to
"a user can install, launch, browse mods, and recover from a crash".

Everything below was re-derived from the tree, not copied from the earlier
checklists. Where this file and an older plan disagree, this file wins.

**Current position:** M5 ✅ · **M5.5 (Java acquisition) is next** · M6-M9 pending.

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

- `/setup`, `/logs` render a "not built yet" placeholder.
- No mod/loader installer: `LoaderKind` exists in the model, nothing acts on it.
- No Java provisioning: `JavaManager` can only *find* a JVM; `noRuntime` and
  `javaTooOld` are dead ends for the user. `JavaSource.managed` exists in the
  model but nothing ever produces one. That is M5.5.
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
| 5.5 | Java acquisition: when `noRuntime`/`javaTooOld`, offer the managed download from the UI instead of only a message | ⬜ (moved to **M5.5**, next section) |
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
Java download is ~96 MB raw / \~68 MB over the wire (measured, see M5.5) and
needs a resumable path.

### M5.5 — Java runtime acquisition (user-prioritized; pulled ahead of M6)

**Why now:** the user asked for the Java downloader first. It is also the last
thing standing between M5 and its exit criterion: `prepareLaunch` refuses with
`noRuntime`/`javaTooOld`, and today the launcher can only *say so*. Every
launcher that expects a non-technical user to play Minecraft must ship a JRE,
because the machine's Java is either absent (fresh Windows), wrong (Java 8 for
1.20+, or 21 where mods expect 17), or present but not on `PATH`.

**Source of runtimes:** Mojang's own runtime catalog, not Temurin/Adoptium.

`https://launchermeta.mojang.com/v1/products/java-runtime/<sha>/all.json`
(unauthenticated, no API key, same CDN family the launcher already downloads
from). Per platform it lists components — `jre-legacy` (8), `java-runtime-alpha`
(16), `-beta`/`-gamma` (17), `-delta` (21), `-epsilon` (25) — each with a
version name and a **manifest** URL. The version JSON already carries
`javaVersion.component`, which is exactly this key, so the mapping needs no
guessing: `version.javaVersion.component` → catalog entry → file manifest.

This is strictly better than downloading a Temurin archive:

- **No new trust root.** It is the same host/CDN and the same SHA-1 verification
  path the installer already uses; Temurin would add a second vendor, a second
  redirect-following code path and its own checksum scheme.
- **Exactly what the game expects.** Mojang builds these for Minecraft; the
  `jre-legacy` component is the 8u202 build the game was tested against.
- **Per-file granularity and LZMA.** The catalog manifest is ~420 entries
  (`file`/`directory`/`link`) with per-file `raw` and (usually) `lzma` objects.
  Verified against the live catalog: 126 of 133 files offer `lzma`, whose total
  is **12.6 MB instead of 39.5 MB** — 27 MB saved per runtime, which matters most
  to exactly the users who need a bundled JRE.

**Measured, not assumed** (this host, aarch64, `17.0.15` catalog entry):

| Fact | Measurement |
|---|---|
| JRE size, raw | 95.2 MB across 133 files (`lib/modules` alone is 55.5 MB, raw-only) |
| JRE size, with LZMA objects | 67.8 MB (LZMA saves 27.0 MB) |
| LZMA decode, Dart `archive` | 34.3 MB → **1159 ms** (~30 MB/s) |
| LZMA decode, Rust `lzma-rs` (pure Rust) | **1073 ms** (~32 MB/s) — 1.08× |
| LZMA decode, Rust + C `liblzma` (`xz2`) | **622 ms** (~55 MB/s) — 1.9× |
| SHA-1, Dart `crypto` | **78 MB/s** |
| SHA-1, Rust `sha1` | **552 MB/s** — 7× |
| LZMA-alone header | 1 byte props + 4 dict + 8 size; **size field is `-1`**, so the length must come from the manifest's `raw.size`, not the header |

Measured against the real `linux` / `java-runtime-gamma` (17.0.15) manifest and
its real objects (`lib/server/libjvm.so`, `lib/ct.sym`, `bin/jar`, …), on
aarch64 Linux: Dart via `archive`'s `LzmaDecoder`, Rust 1.98 via `lzma-rs` 0.3
(pure) and `xz2` 0.1 (C `liblzma` 5.8.1). Nothing here is a guess about what the
catalog "probably" contains — the 126/133 LZMA ratio, the 208 `legal/*` links and
the arm64 gaps are all read off the live JSON.

#### Native code decision (asked for explicitly)

The user asked to use a "faster language like Rust or Go" for decoding. The
measurements say: **not worth a native dependency, and the case rests on the
hashes, not on LZMA.**

- A pure-Rust rewrite of the same algorithm is only **1.08× faster** — noise.
  The 1.9× win comes from linking C `liblzma`, i.e. shipping a C library, which
  is an FFI-and-packaging burden, not a "faster language" win. Dart's `archive`
  is already within 1.9× of optimized C for this workload.
- In context, 1.2 s of decoding is spent **once per runtime install, behind a
  network transfer of tens of MB** that takes far longer than the decode. It is
  not on a hot path, and it is not what the user waits for.
- The real CPU-shaped problem is **SHA-1 at 78 MB/s**, because it runs over
  *every* asset and library on *every* install (~3000 files, a few hundred MB on
  a modded 1.20.1) — measured 7× slower than Rust. But even that must not become
  an FFI call: moving the hash to `Isolate.run` keeps the UI responsive and lets
  the hash overlap the network, and the existing `HashCache` already skips
  re-hashing unchanged files. Rust would make a correct design faster; it would
  not make an incorrect design correct.
- Cost of Rust here is real and lands on the user: `flutter build` no longer
  suffices for any target (`cargo` + a platform toolchain per OS), four native
  artifacts (Windows x64, macOS arm64, Linux x64 that CI builds alone), a
  `dart:ffi` binding to keep in sync with the Dart fallback, and **no ability to
  test any of it on this host** for Windows/macOS — the exact kind of
  unverifiable code path that `docs/PLAN.md` §1 exists to avoid.

So M5.5 stays pure Dart, and the decode runs off the UI isolate. If profiling
later shows hashing dominating a real install, the escape hatch is
`Isolate.run` first (free), then a native SHA-1 as a separate, benchmark-gated
milestone — not as a prerequisite for Java downloads.

| Task | Deliverable |
|---|---|
| 5.5.1 | `lib/core/mc/java_catalog.dart`: pure parsing of `all.json` + a runtime manifest into `JavaRuntimeDescriptor` / `JavaFileEntry` (`type`, `target` for links, `executable`, `downloads.raw/lzma`). Platform key from `(HostOs, HostArch)`, including the gaps below. Pure `dart:convert` value types so every platform is testable from one machine. |
| 5.5.2 | Component selection: `version.javaVersion.component` → catalog component; when absent, derive from major (8→`jre-legacy`, 16→`alpha`, 17→`gamma`, 21→`delta`, 25→`epsilon`) and fall back to the nearest *available* component when the platform's list is empty. Must handle the measured gaps: `mac-os-arm64`/`windows-arm64` have **no** `jre-legacy` and no `alpha`/`beta`, so an arm64 mac and a pre-1.13 version is a genuine refusal, not a silent wrong download. |
| 5.5.3 | `lib/core/mc/java_provisioner.dart`: plan → download → verify → **stage into `<data>/runtimes/<component>-<version>.staging/`** → probe → atomically rename. Mirrors `VersionInstaller`'s staging discipline: a cancel or a failure must never leave a half-runtime that `JavaManager.scan` later advertises. |
| 5.5.4 | LZMA decode via `archive`'s `LzmaDecoder` (`reset(positionBits/literalPositionBits/literalContextBits, resetDictionary: true)`, then `decode(input, manifestRawSize)`; skip the 13-byte alone-header). Verified byte-identical against `libjvm.so` (23.1 MB) and `bin/jar`. Run under `Isolate.run`; fall back to `downloads.raw` when a file has no `lzma` object. |
| 5.5.5 | Post-extract layout: `link` entries (208 `legal/*` links) become copies of their target on Windows and real symlinks elsewhere; mark `executable: true` entries `+x` on POSIX. macOS: the manifest's root is `jre.bundle/Contents/Home/`, so the executable path must be resolved from the manifest, not assumed to be `<root>/bin/java`. |
| 5.5.6 | `JavaManager` integration: `managedRoots: [<data>/runtimes/*]` in `defaultJavaSearchPaths` (already supported), so a provisioned runtime is found by the ordinary `scan` and probed like any other. `JavaSource.managed` is already in the model and already breaks ties in `selectRuntime`. |
| 5.5.7 | `lib/data/java_providers.dart`: `JavaCatalogController` (fetch/cache/offline-stale) + `JavaInstallController` (one at a time, `CancelToken`, `ref.mounted` guards, `DownloadProgress` mirrored per file). Reuse `FileDownloader`/`MirrorChain`/`HashCache` — no second download stack. |
| 5.5.8 | UI: on `LaunchRefused` with `noRuntime`/`javaTooOld`, the launch screen offers **"Download Java 17"** with progress and cancel, then retries the launch. `/setup` gets a managed-runtime list (installed versions, delete, "download another"). |
| 5.5.9 | i18n: `javaDownload*`, `javaDownloadProgress`, `javaDownloadFailed`, `javaUnavailableOnPlatform`, `javaManagedInstalled`, `javaDelete`, `javaDeleteConfirm` — en + zh + `@description` in the same commit. |

**Exit (tests, not opinions):**

- A local `HttpServer` fixture serves a catalog + a two-file JRE manifest whose
  `lzma` objects were produced from real bytes; the test asserts the extracted
  tree byte-for-byte, including one `link`, one `executable`, and one
  raw-only file.
- Provisioning into a temp `<data>` then `JavaManager(managedRoots: …).scan()`
  with a scripted `JavaProbe` finds the runtime with `source: JavaSource.managed`
  and the right major — and `prepareLaunch` for a Java-17 version then returns
  `LaunchReady` instead of `LaunchRefused`.
- Cancel mid-download leaves **no** `runtimes/` entry and no staging directory.
- Archive-bomb / path-traversal guards: manifest entry named `../../x`, a
  `lzma` payload that decodes to fewer bytes than `raw.size`, and `raw.size`
  larger than a sane cap are all refused (reuse `safeRelativeEntryName`).
- Platform-gap test: `(osx, arm64)` + `jre-legacy` reports
  `javaUnavailableOnPlatform` rather than downloading an x86 JRE.

**Risks:** 96 MB per runtime (67 MB on the wire) per major version; a user with
three versions needs three runtimes, so `/setup` must show total disk used and
offer deletion. The catalog has no `windows-arm64` Java 8 at all. Mojang may
retire `-alpha`/`-beta`; selection therefore keys off *what the catalog offers*
rather than an assumed list.

---

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

M5 before M5.5 because the provisioner's whole job is to satisfy a launch
refusal that only exists once installs work. M5.5 before M6 because it is what
makes M5's exit criterion ("install 1.20.1 through the UI, then launch it") true
on a machine with no Java — without it that criterion silently depends on the
developer's own JDK. M5.5 is also the user's explicit priority. M6 before M7
because loader installs need an instance to install *into*, and the detail page
is where that lives. M7 before M8 because most mods are
loader-specific, so a mod browser without loaders serves only vanilla players.
M9 last because accounts and crash analysis are quality multipliers on a launcher
that must first be able to install and launch.

The one ordering that is *not* negotiable: **Forge (7.3) after Fabric (7.1–7.2)**.
Fabric's metadata is simple and proves the inheritance path; Forge's processors
will expose every bug in it, and debugging both at once is how a week disappears.
