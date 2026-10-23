# AGENTS.md

Project: **oh my mc** (`oh_my_mc`) — a Flutter/Dart Minecraft launcher (fluent motion UI, PCL-class features).
Package id `io.ohmy`. Full plan: `docs/PLAN.md`. This file records *hard-won environment knowledge* — read it
before changing the toolchain, because several things here are non-obvious and will silently break.

## Toolchain: how Flutter is installed here (READ THIS FIRST)

The host is **arm64** (`uname -m` → `aarch64`, Debian 13 trixie). **Flutter publishes no arm64 Linux SDK** —
`releases_linux.json` contains zero `arm` archives. The working setup is a hand-assembled hybrid:

- Flutter root: `/home/openhands/flutter` (extracted from the **x64** tarball).
- `bin/cache/dart-sdk` is a **symlink** to `/home/openhands/dartsdk3515/dart-sdk` (native arm64, **Dart 3.13.5**).
  The original x64 SDK was moved to `bin/cache/dart-sdk-x64` — do not delete it, and do not point the symlink
  back at it.
- `bin/cache/flutter_tools.snapshot` was rebuilt natively (delete the snapshot + stamp, then run `flutter`
  once and let `shared.sh` recompile). A x64 snapshot fails with
  *"Snapshot not compatible with the current VM configuration"*.
- `bin/cache/artifacts/engine/linux-arm64/` was populated manually from
  `https://storage.googleapis.com/flutter_infra_release/flutter/<engine-hash>/linux-arm64/artifacts.zip`.
  `const_finder.dart.snapshot` was copied in from `linux-x64` (arch-independent kernel code).
  `font-subset` **does not exist for arm64** → always pass `--no-tree-shake-icons` when building on arm64.
- **Dart patch version must match the engine exactly.** 3.13.6 causes `flutter_tester` to abort with
  *"Invalid SDK hash"*. 3.13.5 is correct for Flutter 3.47.7.

Always export before running flutter/dart:

```bash
export PATH=/home/openhands/flutter/bin:$PATH PUB_CACHE=/home/openhands/.pub-cache
```

If `bin/cache` is ever wiped, redo the whole dance. Don't spend time re-deriving it.

## Verified commands

| Command | Status |
|---|---|
| `flutter analyze` | clean |
| `flutter test` | passes (native arm64 `flutter_tester`) |
| `flutter build linux --release --no-tree-shake-icons` | produces `build/linux/arm64/release/bundle/oh_my_mc`, ELF64 **aarch64** |
| `flutter build linux --target-platform linux-x64` | **fails** — *"cross-building only supported on Linux x64 hosts"* |

So x64 artifacts only come from x64 runners (`docs/PLAN.md` §3.5.1); this sandbox can only build arm64 Linux.

## System packages installed (needed for Linux desktop builds)

`libgtk-3-dev`, `pkg-config`, `cmake`, `ninja-build`, `clang`, `libsecret-1-dev` (required by
`flutter_secure_storage_linux`), `unzip` (Flutter needs it to extract engine artifacts).

Gotcha: `libpng-dev` demands `libpng16-16t64=1.6.48-1+deb13u5` while `…u6` was preinstalled →
install with `sudo apt-get install -y --allow-downgrades libpng16-16t64=1.6.48-1+deb13u5 libpng-dev`.

Gotcha: if a build fails with `file INSTALL cannot copy ... to "/usr/local/oh_my_mc"`, a stale
`build/linux/**/CMakeCache.txt` pinned `CMAKE_INSTALL_PREFIX=/usr/local`. Fix: `rm -rf build/linux`. Do not
put `--install-prefix=/usr/local`.

No `DISPLAY` → no windowed runs here. Visual verification goes through the
screenshot harness instead:

```
flutter test test/dbg_shots_test.dart --run-skipped --update-goldens
```

There is a second harness for the install paths, tagged `e2e` and also skipped by
default:

```
flutter test test/e2e --tags e2e --run-skipped
E2E_TREE=/tmp/tree flutter test test/e2e --tags e2e --run-skipped   # reuse a tree
```

It installs 1.20.1, 1.6.4 (legacy `virtual` assets), Fabric, Quilt, Forge and
NeoForge against the *real* services, provisions a JRE from Mojang's catalog, and
launches an isolated instance. It found four bugs no local server could:
Fabric/Quilt nest the build under `loader` (the fixture had it flat, so the parser
looked right), NeoForge's maven root has a `/releases` path segment that
`Uri.replace(path:)` silently dropped, an inheriting version has no client jar of
its own (`jar` must resolve to the base id), and an isolated instance was reading
its version from its own tree while the installer only ever writes the shared one.
Treat a local fixture as a hypothesis: mirror the real payload's shape, and run
this harness when a service could have changed.

Writes 1440×900 PNGs of every screen to `test/shots/` in ~3 s (git-ignored).
The harness is tagged `shots` and `dart_test.yaml` skips it by default, because
its goldens are text-bearing pages laid out with host fonts: comparing them on
Windows or macOS diffs every pixel and proves nothing. `--run-skipped` is what
opts back in.

Two traps that made the harness look like it "hung forever" (it did):

- **`await Directory.systemTemp.createTemp()` inside `testWidgets` never
  returns.** The body runs in a fake-async zone where real I/O futures are never
  advanced, so the test stalls with no output until the runner times out. Every
  real filesystem or network await needs `await tester.runAsync(() => ...)` —
  which returns a nullable, hence the `(await ...)!`.
- Only `pump`/`pumpAndSettle` are legal outside `runAsync`; do not try to move the
  `expectLater(matchesGoldenFile)` into it or the frame is not the one captured.

## CI

`.github/workflows/ci.yml` — `analyze` job (format check, `flutter analyze --fatal-infos`, `flutter test`) gates a
3-target build matrix. Notes:
- `tool/verify_binary_arch.dart --file=<bin> --expect=<linux-x64|windows-x64>` parses ELF/PE headers and exits
  non-zero on mismatch. macOS uses `lipo -archs` instead and asserts arm64 present **and** x86_64 absent.
- `--fatal-infos` is on, so an info-level lint fails CI. Run it locally before pushing.
- The macOS job needs `flutter config --enable-macos-arm64-only`, otherwise release builds are universal.
- `dart format --set-exit-if-changed` is enforced — and note `dart format` will happily reflow a brace-less
  `if (...) return x;` into a multi-line form that then trips `curly_braces_in_flow_control_structures`.
  Always use braces.

## Dependency gotcha

`build_runner` must stay at **`^2.16.2`**. `>=2.17.1` needs `build >=5.0.0 <5.1.0`, but `riverpod_generator`
needs `build <5.0.0` → unsatisfiable. Don't "upgrade" it.

## Where the plan lives

`docs/PLAN.md` (product scope, targets, §7 screens), `docs/PLAN-M1-M4.md` (§0 package traps and
the motion architecture — still the rationale of record), `docs/PLAN-M3.4-M5.md` (audits the older
plan against the code), `docs/PLAN-M4.2-M9.md` (up to M5.5, plus the defect list that milestone
found), and `docs/PLAN-M6-M9.md` (**current status and next steps**: M6→M9, and the only plan whose
§0 measurements are current).

## Widget-test trap: a page taller than the test viewport

`ListView` does not build off-screen children, so a `find.text(...)` for a row
below 600 px finds **nothing** and reads as "the widget is broken" while the
widget is fine. `setup_screen_test.dart` now sets `tester.view.physicalSize`
(1400×2600) for exactly this reason. Prefer a tall viewport over
`scrollUntilVisible` unless the scroll behaviour is what is under test — a
scrolled-to assertion cannot tell "renders late" from "never renders".

## Uncommitted-defect queue (as of `PLAN-M6-M9.md` §0.3)

Still open, do not assume otherwise: instance delete does not remove its
directory; `ManagedJavaRuntime.majorVersion` hardcodes `HostArch.x86_64`; the
heap clamp is 16384 in the UI but 65536 in `settings.dart`; `jvmArgs`/`gameArgs`
have no editor; instance creation hardcodes `1.20.1` + vanilla; `window_manager`
is never initialised and `flutter_acrylic` is never imported. (The committed
golden-diff PNGs that used to sit under `test/ui/failures/` are gone: that
directory and `test/shots/` are now git-ignored.)

## App shell traps (M3.4)

- **`find.byType(FluentApp)` gives a context above `Localizations`.** Reading
  `context.l10n` from it throws a null-check on the generated `of()` — which is the
  intended loud failure, but it means a test must take its context from a widget
  *inside* a page. `test/app/router_test.dart` has `localizedContext` for this.
- **Never pass a fresh closure as `AppRoot.screens` on every build.** `_AppState`
  compares it by identity, so a new closure per build rebuilds `GoRouter` and
  resets navigation to `/launch`. Everything a screen can change (theme, locale,
  motion) flows through `FluentApp`'s own config instead, precisely so the router
  is not rebuilt.
- **Riverpod 3.4 has no `overrideWithValue`.** Use
  `provider.overrideWith((ref) => value)`.
- **Language changes go through `appSettingsProvider.notifier`, not a constructor
  argument.** Tests that re-pump `OhMyMcApp(locale: ...)` to switch language are
  testing a mechanism no user can reach and will now fail.
- **One transition source: `appPage` in `lib/app/router.dart`.** A screen that
  builds its own `PageRoute` opts out of reduced motion silently. The reduced
  motion mechanism is a zero *duration*, not a different page class, so there is
  one code path — verified to settle in a single pump.

## Architecture rules

- `lib/core/**` must not import `package:flutter` (it must stay pure-Dart testable).
- All durations/curves come from `lib/ui/motion/motion.dart`; no inline `Duration(` / `Curves.` elsewhere.
- Respect reduced motion via `MotionScope` (collapses durations to 0).
- Every user-visible string goes through `AppLocalizations` (en + zh_Hans). No hardcoded UI text.
- **The shell owns the `Scaffold`.** `AppShell` is the only widget that introduces `Material` for a
  page. Without it an `InkWell` asserts on first paint and every `Text` without an explicit style
  inherits `MaterialApp`'s debug error style - 48 px, red, yellow double underline - so a missing
  ancestor looks like a styling disaster rather than a one-line structural bug.
  `test/ui/shell_material_test.dart` pins it per route.
- **Screens use `PageBody` / `PageTitle`**, never their own outer padding. That is what keeps the six
  pages on one grid: 24 px page padding, a 1040 px content cap, and one title style.
- **The rail is fixed-width with the label under the icon** (`NavigationRailLabelType.all`). Do not
  switch it back to `extended:` (216 px spent on short labels) and do not make it collapsible (the
  body's constraints would then depend on a control inside the rail). No divider between rail and
  page: they are one surface, separated by tone.
- **Launch owns version selection** (PCL's operation logic). The launch page's picker lists every
  instance and links to management; `/instances` is a *management* route, not a rail item. A second
  tab that only chooses what the launch page already chooses is two doors to one room.
- **An instance is a section list, not one long page.** One page per thing you can look at (概览, 模组,
  资源包, 光影, 存档, 服务器, 数据包, 设置), the way Prism's instance window is arranged. The kinds are
  not interchangeable - a mod is switched off by renaming its jar, a pack by editing `options.txt`, a
  world only deletes, a data pack belongs to one world - so a single list with a kind filter is a list
  that has to explain itself. Sections use `SectionDrawer` (an MD3 `NavigationDrawer`), the same
  control 设置 uses; do not hand-roll a column of rows for a section list.
- **A card is one filled surface**: `surfaceContainerLow`, 16 px radius, no outline; only a selected
  item carries a border. Boxed cards on a dark surface read as unrelated panels.
- **No shadows, no glows.** Material 3 expresses elevation as *tone*: a raised surface is
  `surfaceContainerLow → surfaceContainer → surfaceContainerHigh` from one neutral ramp. Dialogs and
  menus have their elevation zeroed in `AppTheme.material` for the same reason. A `BoxShadow` in
  `lib/ui/` is a bug: use the next container tone instead.
- **Motion has no switch.** Animation is part of the design; `MotionScope` is always `Motion.full` and
  only the OS accessibility flag can turn it off. Do not add a settings toggle for it.
- **Accent colours are a setting** (`AppSettings.accent` → `AppTheme.seedFor`). Every colour comes from
  the seeded `ColorScheme`; status hues stay fixed (see `AppTheme.status`).
- **`material_ui` (`m3`) is the only style package.** `material_3_expressive` (`m3e`) was removed in
  `PLAN-M11` W7 — do not reintroduce it, and do not import `package:flutter/material.dart` (a second tree).
  If a control needs a variant `material_ui` lacks, add a wrapper in `lib/ui/components/`, never an
  inline workaround at the call site.

## `lib/ui/components/` — the design-system seam

Screens import these, not raw `m3` controls, so a later design-system change is a one-file edit each:

| Component | Wraps | Why it exists |
|---|---|---|
| `AppButton` | `m3.Filled/Outlined/TextButton` | `AppButtonStyle` / `AppButtonSize` absorb the old `M3EButton*` enums |
| `AppTextField` | `m3.TextField` + `InputDecoration` | outlined, single/multi-line |
| `AppSwitch` | `m3.Switch` + `Semantics` | `m3.Switch` has **no** `semanticLabel` |
| `AppSlider` | `m3.Slider` + `Semantics` | `m3.Slider` has **no** `semanticLabel` |
| `AppRadioGroup<T>` | `m3.RadioGroup` + `m3.Radio` in `InkWell` rows | `RadioListTile` **asserts** under a `DecoratedBox` with a background |
| `AppDialog` | `m3.AlertDialog` | `title` is also the semantic label |
| `AppTheme.status(context)` | fixed hues | MD3 has no success/warning/info; these must not follow the accent |

Two `material_ui` facts that cost real time here:

- `RadioGroup` is **not** re-exported by `material_ui`; it comes from `package:flutter/widgets.dart`.
  `Radio.groupValue`/`Radio.onChanged` are deprecated after Flutter 3.32 — put state on `RadioGroup`.
- `m3.Slider.onChangeEnd` reports the **released** value (unlike `m3e`, which reported the stale prop).
  Do not resurrect the `_dragging`-reads-in-`onChangeEnd` workaround.

## Motion: informative, not decorative

Motion has two jobs and they are reviewed differently. *Style* motion (entrances, page transitions,
ambience) lives in `lib/ui/motion/` and is unchanged by design changes. *Informative* motion states a
fact the user could not otherwise read, and is the only kind a screen may add on its own:

| Primitive | Says | Use for |
|---|---|---|
| `Skeleton` + `SkeletonBlock` | "content of this shape is coming" | any region whose layout is known while loading |
| `AnimatedCount` | "this number is moving to *that* value" | memory size, download percentage |
| `Emphasis` | "the control heard the press" | the one primary action on a screen |
| `AppendHighlight` | "this row just arrived" | appended log lines, warnings especially |
| `AmbientLoop` | "still working, no progress to report" | a pulsing dot while a launch runs |
| `MotionRespectingProgressBar` | "working, length unknown" | an indeterminate phase |
| `StaggerItem`/`StaggerList`/`MotionEntrance` | "this is a list, that is a page" | entrance only |

### Releases

- **Windows ships an installer, not a zip.** `packaging/windows/oh-my-mc.iss`
  (Inno Setup) turns the Flutter release folder into
  `oh-my-mc-<version>-windows-x64-setup.exe`: double-click, choose a directory,
  done, with a stable `AppId` so an upgrade replaces the previous install.
- **It is built on GitHub's Windows runner.** Flutter cannot cross-compile to
  Windows from Linux, and this instance has no Windows host, so
  `.github/workflows/release-windows.yml` is GitHub-only; the Forgejo runner cannot
  do it. Push a `v*` tag (or run it by hand) and the .exe is attached to the
  release.
- The Windows release path is `build/windows/x64/runner/Release` and the binary is
  `oh_my_mc.exe` (`windows/CMakeLists.txt`'s `BINARY_NAME`); the Inno script and
  the workflow both hardcode those, and the workflow fails early if the exe is
  missing rather than inside ISCC.

### Lists

A list is scanned, not read: Material's list anatomy fixes the slots and asks for
them to stay put.

- Every row goes through `ListRow` (`lib/ui/components/list_row.dart`): leading
  icon, label, optional supporting text, optional trailing text, optional trailing
  action. Do not hand-roll a row - the whole point is that row 7 lines up with row
  1, and a one-off `Row` is how that stops being true.
- **One action per row.** The row is the primary action; a second action is the
  trailing icon button. Never repeat a labelled button down a list: four "open
  folder" buttons read as four controls, not as four items.
- The label and the supporting visual sit in the same place in every row. No
  key/value rows, no floating numbers in the middle, no per-row button chrome.
- Leading icons are `onSurfaceVariant` and, when several rows are the same kind of
  thing, each gets its own cue (a palette for resource packs, not four puzzle
  pieces).
- A section heading may carry one line of description under it (`_Section`), which
  is where the reader meets the explanation - not in a tooltip or a footnote.

Rules that are enforced, not stylistic:

- **Skeleton where the shape is known, spinner where it is not.** A spinner above a list that will be
  rows is a wasted opportunity; a skeleton in a one-line check is noise.
- **A running progress bar never reaches 1.0.** `download_screen.dart` clamps both the bar and the
  percentage (`_displayFraction`); only the finished state may say 100%.
- **Motion off must cost nothing.** Every primitive returns its end state (or the plain child) and
  schedules no frames; `test/ui/motion_informative_test.dart` asserts this with
  `transientCallbackCount == 0`, not with a duration check.
- `flutter_animate` and `skeletonizer` may only be imported by `lib/ui/motion/primitives.dart`
  (`tool/check_imports.dart` enforces it): both build controllers unconditionally, so a call site
  would silently break reduced motion.
- Never animate an initial backfill (a log opened with 500 lines): animation there delays the first
  useful frame and communicates nothing.

## PCL parity contract

`docs/PCL-PARITY.md` is the behavioural contract: PCL 2's structure (启动 / 下载 / 设置,
version card as selector, 版本设置 as the per-version hub), the user flow we mirror,
the current gap table and the ordered backlog. Two rules from it bind new code:

- **Download ⇒ playable.** Every install path ends by making the result launchable
  (`InstanceListController.ensureForVersion`); the user never registers what they
  just downloaded.
- **The version card is the selector**, and per-version settings live in
  `/instances/:id`, never in the global `/setup` page.
- **The card opens 版本列表, a dialog** - not an anchored dropdown. The list is
  also where a version is configured (a gear per row) and where versions are
  created or managed, and a popup menu can only switch: it cannot carry primary
  and secondary actions per row, and it sizes itself to its widest row, so it
  floated as a 240 px sliver under a 500 px card.
- **One primary action per state.** Idle: 启动游戏. Preparing: the same button
  says 正在启动… and is disabled. Running: it is *gone*, and 停止 is the filled
  button. A disabled launch button sitting next to a stop button for the whole
  session made the page's most prominent control a no-op.
- **Nothing switchable while a game runs.** The version card's list is locked
  (`session.isBusy`): switching underneath a live session would show one version's
  output under another version's card, and the stop button would point at neither.
  The chevron is hidden too - an affordance that does nothing is worse than none.
- **The console shows the launch summary, not the argv.** A Minecraft classpath is
  100-200 entries and several kilobytes; printing it pushed the game's own output
  off the screen. One line goes to the console (`launch: java · N classpath
  entries · main`), the exact command line goes to `<data>/logs/launch-*.log`
  with `--accessToken` masked.
- **Catalogue installs name their destination.** A mod goes to `mods/`, a resource
  pack to `resourcepacks/` (and is switched on in `options.txt`), a data pack into one
  *world* - which is why the flow asks for the world first. A download button that
  silently picks a target is a download into the wrong place.
- **A port mapping takes its port from the game's LAN announcement**, never from a
  setting: the game picks a random port per session. `LanDiscovery` listens on the
  game's own multicast (224.0.2.60:4445) for `[MOTD]…[/MOTD][AD]port[/AD]`.
- **The update check is on demand and silent on failure.** A request to GitHub on
  every launch is a privacy answer the user did not give, and offline/rate-limited
  must read as "could not reach the feed", never as a broken install. `appVersion` in
  `lib/app/version.dart` is asserted against `pubspec.yaml` by a test, because a stale
  constant means missing every update.
- **The game owns `options.txt` and `servers.dat`; the launcher edits the field it
  was asked to change.** `OptionsTxt` rewrites one key in place and keeps every other
  line (the game rewrites the file on exit, so a wholesale rewrite loses settings), and
  `servers.dat` is NBT that has to round-trip. Resource packs are the only content kind
  with a launcher-writable enabled state; Iris keeps the active shader in its own
  config, so that row has no toggle rather than one that lies.
- **A clone is always an isolated instance.** A shared instance's "game directory" is
  the launcher-wide one, so copying it is a self-copy; the clone gets its own
  `minecraft/` and skips `libraries/`, `assets/`, `versions/`, `logs/`.
- **Widget tests never touch the real disk through a screen.** Real file I/O does not
  complete inside `pumpAndSettle`'s fake clock, so screens that read files take their
  data layer from a provider (`gameContentProvider`) and the disk behaviour is pinned by
  a core test against a temp tree.
- **User-facing text lives in the ARB files, never in `lib/core`.** `Diagnosis`
  carries a kind plus parameters; `CrashCopy` (UI) turns it into a sentence. The
  inverse - an English sentence in core - put the literal `版本设置` inside an English
  dialog, because the core cannot see the locale.
- **A diagnosis needs evidence and an action, and the action must be reachable.**
  Every `DiagnosisAction` routes to an existing screen; `retry` is only rendered when
  a callback exists, because a button that does nothing is worse than no button.
- **Do not diagnose a clean exit.** Mods log `NoClassDefFoundError`/`ERROR` while
  probing for optional classes, so the analyzer requires a non-zero exit code or a
  JVM/loader fatal marker before it looks at the patterns.
- **Mod search filters come from the instance.** `McTarget.fromInstance` reads the
  loader off the instance, not out of its `versionId` (which is the *game* version);
  reading the id calls every Fabric instance vanilla. A vanilla instance gets an
  explanation instead of a search box, because a field that can only return
  unloadable mods is a control that lies.
- **Dependencies: `required` only, breadth-first, visited-set.** Optional
  dependencies are suggestions; installing them silently is how a launcher ships a
  mod list nobody asked for. A cycle is common enough that a naive recursion hangs.
  `tool/smoke_modrinth.dart` resolves Iris (which needs Sodium) against the real
  API - run it when the response shapes are in doubt.
- **A pack import creates the instance first, then unpacks into it** (`inspect` →
  `create` → `import`): the instance id is the directory name, so it has to exist,
  and the pack's own name is what the instance should be called. Pack paths are
  refused when they escape the game directory.
- **Logs are files, and the page reads them.** `ProcessLaunchHandle` writes every
  console line to `<data>/logs/launch-<timestamp>-<version>.log` (stderr prefixed
  with `! ` so the errors filter survives a restart) and the full argv too; the
  Logs page lists those files newest-first and opens the newest when nothing is
  live. A console that only exists in memory cannot answer "why did it crash
  yesterday", which is the only reason a log page exists.
- **One console, one surface.** The launch page is card → actions → console, and
  the console is the page's body (`Expanded`, not content-sized): a bordered box
  inside a card is two frames for one panel, and a console that grows its first
  line reflows the page.
- **Isolation separates the game directory, not the install.** `versions/`,
  `libraries/` and `assets/` always come from the shared tree (`paths.gamePaths`),
  because they are content-addressed and identical; only `--gameDir` and the
  process working directory move to `<data>/instances/<id>/minecraft`. A version
  dropped into an instance tree by hand is not an install and will not launch.
- **The instance grid is home**; there is no Launch tab. `/launch` is the running
  view (log, stop, version settings) that a Play navigates to.
- **An install that cannot be watched reads as a broken button.** The download
  panel shows one phase at a time and only exists while the install runs, so a
  resume started elsewhere had no feedback at all. `InstallLog` keeps a ring of
  timestamped lines (phase changes plus every 10% of bytes) in memory and appends
  them to `<data>/logs/install.log`; the panel renders the tail and the launch
  page's repair button jumps to that panel instead of running an invisible install.
- **An install is not finished because its JSON exists.** `versions/<id>/<id>.json`
  is written before the libraries, so a killed install looks complete to every
  "is it installed" check. `InstallJournal` writes `versions/<id>/.installing`
  before the first byte and removes it only when verification is clean; both
  `InstalledVersions` and the download row treat a marked version as *not
  installed*, which is what keeps the resume clickable after a restart.
- **A loader is not always a profile.** Fabric/Quilt publish a version JSON
  (install = write it); Forge/NeoForge publish an installer jar that must run with a
  JVM. The installer path also writes `launcher_profiles.json` first and trusts
  `versions/<id>/<id>.json` over the exit code, because the installer exits 0 even
  when it prints "There was an error during installation".
- **Java: own runtime first.** A version that runs elsewhere usually fails here
  because *that* launcher shipped the JVM, so the scan looks inside Prism/official
  launcher/JetBrains/sdkman layouts, the launcher downloads its own runtime on
  demand, and `/setup` → Java accepts extra directories (`AppSettings.javaDirs`).

## Ship targets (decided — do not "helpfully" add more)

**windows-x64, linux-x64, macos-arm64.** No Windows arm64, no Linux arm64. macOS is arm-only via
`flutter config --enable-macos-arm64-only`.

This is grounded, not arbitrary: Flutter publishes **zero** arm64 archives in `releases_linux.json` and
`releases_windows.json` (only `releases_macos.json` has arm64). So arm64 Windows/Linux cannot even be built in CI.

Consequence: the LWJGL3 `natives-linux-arm64` classifier patch that the plan used to need is **gone**. Don't
re-add it. `arch_compat` only has to handle the macOS-arm64 case below.

## Download layer (`lib/core/net/`)

- **Mirror rewrites are only safe where the mapping is deterministic.** `piston-data` object
  URLs carry a SHA-1 but not the version id, so they are deliberately *not* rewritten — a
  mirror guess here 404s quietly. `versionJson` rewrites from `/v1/packages/<sha>/<id>.json`
  to `/version/<id>/json`, which is the only way to get the id back.
- **A dropped connection mid-body must delete its `.part`.** Resuming from a truncated
  partial file appends new bytes to a corrupted tail; the result passes a size check and fails
  at class-load time with an unrelated error. Caught by the truncated-response test.
  `.part` files are kept for *transport* failures (refused/timeout) and discarded for
  *integrity* failures (hash mismatch) and mid-body aborts.
- **Range support is per-host, not per-mirror.** Both `libraries.minecraft.net` and BMCLAPI's
  `/maven/` returned 206 to a `Range` request when probed. A server that ignores Range
  replies 200 with the whole body — the downloader detects that and restarts rather than
  appending, so resumption is never assumed.
- **HTTP Range probing gotcha:** `curl -r 0-100` without `-L` against BMCLAPI's `/maven/`
  hangs (the redirect is followed but the range is dropped). Probe with `-L`, and do not
  conclude "mirror is down" from a single timeout.
- **`HttpClientResponse.detachSocket` fails after headers are written** ("Headers already
  sent"). Test servers simulating a truncated response must detach with
  `writeHeaders: false` and hand-write the status line.

## Java management

- **`java -XshowSettings:properties -version` prints to stderr, not stdout.** Read both.
  This single call yields `java.version`, `os.arch` and `java.vendor` in stable
  `key = value` form, so version parsing never has to guess from a path.
- **`os.arch` vocabulary differs per platform:** macOS/Linux arm64 reports `aarch64`,
  Windows may say `amd64`, and a missing key means a truncated dump — assume 64-bit rather
  than declaring the runtime 32-bit and unusable.
- **Windows paths need `\`, not `/`.** Building `$JAVA_HOME/bin/java.exe` produces a mixed
  separator path that Windows tolerates in some APIs but not in `Process.run`. Found by test.
- Runtime choice prefers an **exact** major match over a newer one: mods assume the declared
  Java, and "Java 21 instead of 17" is a common source of confusing mod failures.

### Mojang runtime catalog (verified against the live JSON, not assumed)

Source: `https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json`
→ per-platform component list → a per-runtime **manifest** URL with ~420 entries.
`version_json.javaVersion.component` is already exactly the catalog key (`jre-legacy`,
`java-runtime-gamma`, …), so no heuristic mapping is needed.

- **Platform keys are `linux`, `linux-i386`, `windows-x64`, `windows-x86`, `windows-arm64`,
  `mac-os`, `mac-os-arm64`, `gamecore`.** Note `mac-os`, not `osx` — do not build the key from
  `HostOs.mcName`.
- **arm64 has real gaps:** `mac-os-arm64` and `windows-arm64` list `java-runtime-alpha`,
  `-beta`, `jre-legacy` as **empty arrays** (`-delta`/`-gamma`/`-epsilon` are present). An
  arm64 Mac + a pre-1.13 version is therefore a genuine refusal, not a downloadable case.
- **`downloads.lzma` exists for 126 of 133 files** (all except `lib/modules` and friends).
  Using it cuts the transfer from 95.2 MB to ~67.8 MB. Windows manifests have **no `link`
  entries**; Linux/macOS have 208, all under `legal/`, with `..`-relative targets.
- **The LZMA-alone header's 8-byte size field is `-1`.** The decompressed length must come from
  `downloads.raw.size`; `archive`'s `LzmaDecoder.decode` needs an explicit length and returns
  an empty buffer if it is not supplied. Decode via
  `reset(positionBits: props~/9~/5, literalPositionBits: props~/9%5, literalContextBits: props%9, resetDictionary: true)`
  then `decode(InputMemoryStream(bytes.sublist(13)), rawSize)`.
- **macOS manifests root the tree at `jre.bundle/Contents/Home/`** — resolve the executable
  from the manifest, never assume `<root>/bin/java`.
- Measured decode/hash throughput (aarch64, 34 MB sample set): Dart `archive` LZMA ~30 MB/s;
  pure-Rust `lzma-rs` ~32 MB/s (**1.08×**, i.e. no reason to add Rust); Rust+C `liblzma`
  ~55 MB/s (1.9×, needs a C dependency). Dart `crypto` SHA-1 is 78 MB/s vs Rust 552 MB/s — but
  hash off the UI isolate (`Isolate.run`) before reaching for FFI, and `HashCache` already skips
  unchanged files. Ship targets are windows-x64/linux-x64/macos-arm64, so native code would mean
  three unbuildable-here artifacts.

## Test-environment facts

- **This sandbox has no Java at all** (`java: command not found`, no `/usr/lib/jvm`). Java
  probing tests therefore inject a `runProcess` double; nothing here can launch a real game.
- **The sandbox has live network access.** An "offline" test that relies on a real URL failing
  will silently pass the download and fail the assertion. Tests that need failure point at
  `http://127.0.0.1:1/…` instead (`deadUri()` in `version_manifest_test.dart`).
- Fixture-based tests are the default; `tool/smoke_download.dart` is the only thing that
  touches the network, and it is run by hand (`dart run tool/smoke_download.dart 1.20.1
  [--mirror]`).

## Motion layer (`lib/ui/motion/`)

- **Neither engine can be switched off by configuration.** Verified in source:
  `AnimationExecutor` always constructs an `AnimationController` and merely sets
  `value = 1.0` when its limiter is inactive, and `LoopAnimationBuilder` always
  starts a ticker. So "reduced motion" is a **wrapper** concern — the primitives
  return the child / resting frame and never build the engine widget at all.
  Assert this with `tester.binding.transientCallbackCount == 0`, not with a
  zero-duration check, or you will pass while still allocating a controller.
- **`hasScheduledFrame` is the wrong assertion for anything containing a
  `ListView`.** A bare list schedules frames for its own scroll bookkeeping, so
  the test fails on a tree that is genuinely idle. Use `transientCallbackCount`
  when the claim is "no animation is running".
- **Charge the stagger budget over the items that actually animate, not over the
  list length.** `maxTotal ~/ itemCount` looks right and is badly wrong: a
  1000-item list gets a 0.3 ms step, i.e. no visible cascade. Divide by
  `min(itemCount, maxAnimatedIndex)` instead. Caught by the monotonicity test.
- **The disabled path must render the *end* state.** `AmbientLoop` passes
  `tween.end` to the builder when motion is off; passing `begin` would show the
  start of the animation forever.
- **Token rule is scoped to `lib/ui/`, not all of `lib/`.** `lib/core/net` has
  `Duration` values for HTTP timeouts and retry backoff. Routing those through
  motion tokens would make "reduce animations" disable a download timeout.
  `tool/check_tokens.dart` therefore only inspects `lib/ui/`, excluding
  `lib/ui/motion/` itself.
- **Both gate scripts must be proven to fail.** A checker that never fires is
  indistinguishable from a clean tree. `check_tokens` was verified by planting a
  `Duration(milliseconds:)` in `lib/ui/` and confirming exit 1.

## Minecraft / platform facts that shape the code

- **Library dedupe must key on `group:artifact:classifier`, never `group:artifact`.**
  `netty-transport-native-epoll` ships `linux-x86_64` *and* `linux-aarch_64`
  entries that both carry only `{"action":"allow","os":{"name":"linux"}}`.
  Collapsing them drops the arch the host needs. (Found by test; fixed.)
- **Never detect LWJGL 2 by path.** LWJGL 3's artifact `lwjgl` lives at
  `org/lwjgl/lwjgl/3.4.3/…`, so a `org/lwjgl/lwjgl/` path prefix matches *both*.
  Use the Maven group: LWJGL 2 = `org.lwjgl.lwjgl`, LWJGL 3 = `org.lwjgl`.
  (Found by test on 26.3; fixed.)
- **Rule semantics are deny-by-default for a rules array with no `allow`.**
  Mojang never emits a lone `disallow` (verified across all 6 fixtures), but a
  hand-written modloader file could — strict reading is the safe one.
- Feature-gated args (`--demo`, quick play) use a *single* `allow` rule with no
  base-case allow, so a missing feature must evaluate to false.

- **MC ≤ 1.12.2 cannot run on arm64 at all** — they need LWJGL 2, which has no arm64 natives on any OS
  (verified: 1.12.2's manifest lists only `natives-linux|osx|windows`). Since macOS is our only arm64 target,
  this means those versions are unlaunchable on Apple Silicon: block with a clear message *before* the Play button.
- **macOS arm64 + MC ≥ 1.13 is fine** — `natives-macos-arm64` is already in the manifest; no patching.
- **x64 targets need no library patching at all.**
- Legacy versions use `minecraftArguments` (string) + `natives` classifiers; modern use `arguments.jvm/game`.
  Both shapes are already captured as fixtures targets in the plan.

## UI traps (M4.2 launch screen + instance grid)

- **`PaneItem.body` must be non-null even with `paneBodyBuilder`.** Fluent's
  `NavigationPane.effectiveItems` filters out items with a null `body`, and
  `selectedItem` then indexes an empty list → `RangeError` on the first frame. Every
  pane item passes `body: const SizedBox.shrink()`.
- **Do not wrap individual children of a `Column` in animation widgets.** It breaks
  `Expanded`/`Flexible` (`Incorrect use of ParentDataWidget`). `MotionEntrance`
  therefore animates the whole column as one unit and returns the bare tree when
  motion is off.
- **`pumpAndSettle` never returns while `ProgressRing` is on screen.** The launch
  screen shows one while running, by design. Busy-state tests use
  `pump()` + `pump(150ms)`; that also drains Fluent's 100 ms button hover timer,
  which otherwise trips the framework's pending-timer assertion.
- **Playtime is recorded by `LaunchController`, not by the screen.** It runs on
  `LaunchEnded` with the process's own uptime, so navigating away mid-session still
  records it exactly once. Do not add a second listener; it would double-count.
- **`AppSettings.playerName` drives the offline UUID.** `offlineUuid` must be
  version-3 / RFC-4122 (`md5('OfflinePlayer:<name>')` with the nibbles patched at
  hex offsets 12 and 16). `test/data/launch_factory_test.dart` pins a known value —
  a subtly wrong hash silently changes the user's identity on every server.
- **Java selection must never collapse "too old" into "missing".** `selectRuntime`
  returns null when nothing satisfies the requirement; the factory then passes the
  *highest* runtime so `checkJava` can report `javaTooOld` with the required major.
  Passing null gives the user an unfixable "no Java" message on a machine that has
  Java.

## Framework gotchas (probed, will silently break you)

- **Flutter 3.47 split Material into `material_ui`.** `fluent_ui`, `animations` and `go_router` all
  depend on `package:material_ui`; `package:flutter/material.dart` is a *separate parallel copy*.
  `material_ui.ThemeData` and `flutter/material.dart`'s `ThemeData` are unrelated classes — assigning
  one to the other is a compile error, and mixing them gives two independent theme/localization trees.
  **Rule: content code imports `package:material_ui/material_ui.dart`; never `package:flutter/material.dart`.**
  Add `material_ui` as a direct dep. `fluent_ui` does not collide on import (narrow re-export allow-list),
  so `fluent_ui` + `material_ui` in one file is fine.
- **`FluentApp` + `material_ui` content + `GoRouter` works** (`FluentApp.router(routerConfig:)`), and
  zh_CN resolves through `FluentApp` locale (`cancelButtonLabel` → `取消`).
- **Fluent accent → M3 primary works**, BUT **dark mode does not bridge**: `FluentThemeData.brightness`
  is independent of `themeMode`, so `themeMode: dark` still gives content `Brightness.light` and a
  translucent `surface` (`b3ffffff`) → light-on-light. Always pass
  `FluentThemeData(brightness: Brightness.dark, ...)` in `darkTheme`. Golden-test dark explicitly.
- **Neither animation package honours reduced motion.** No hits for `disableAnimations` /
  `AccessibilityFeatures` in `flutter_staggered_animations_plus` or `simple_animations`;
  `LoopAnimationBuilder` keeps ticking under `disableAnimations: true`. `MotionScope` must *wrap*
  (skip the widget entirely), not pass a zero duration.
- **The stagger package has no total cap**: default `delay = duration ~/ 6` per item. Cap it in our wrapper.
- **`flutter_acrylic` ships no `macos/` dir** (macOS routes to `macos_window_utils`); treat macOS blur
  as best-effort. Windows 10 lags on window drag with acrylic.

## Reference repos — important gotchas

- `The-ring-io/flutter_staggered_animations` 1.1.1 is Dart 2 only (`sdk >=2.17.0 <3.0.0`) → **unusable**.
  Use `flutter_staggered_animations_plus ^1.0.4` (same API). Keep the import isolated in
  `lib/ui/motion/stagger.dart` so it can be vendored (MIT, ~200 LOC) if the fork dies.
- `felixblaschke/simple_animations` 5.3.0 requires Dart `^3.12.0` and **Flutter ≥3.44**.
- `material-components/material-components-flutter` contains **docs only** (no Dart source) — design reference, not a dep.
- `Meloong-Git/PCL` has a **restrictive non-OSI license** (《PCL 分发有限许可》). Reimplement behavior only;
  never copy code/XAML/strings/assets.

## Verified API facts

- `pub.dev` has **no usable Minecraft-launch package** (`minecraft_launcher_lib`, `mcauth`, `minecraft_ping` don't
  exist). Implement the launch pipeline in `lib/core/mc` ourselves.
- Mojang endpoints reachable: `piston-meta.mojang.com`, `launchermeta.mojang.com`,
  `bmclapi2.bangbang93.com` (mirror base), `meta.fabricmc.net`, `api.modrinth.com`.
- Latest release at time of writing: **26.3** (Java 25, 114 libs, `arguments.jvm/game` style).
  1.20.1 → Java 17, 88 libs. 1.12.2 → Java 8, 39 libs, 5 native libs, legacy args.
- Mojang's Java runtime manifest covers `linux`, `linux-i386`, `mac-os`, `mac-os-arm64`, `windows-arm64`,
  `windows-x64`, `windows-x86` — so the JRE is never our arm64 problem. LWJGL is.

## CI (two systems, by necessity)

* **Forgejo** (`.forgejo/workflows/ci.yml`) builds `linux-x64` and runs the gate.
  No arm64 build exists anywhere any more: `linux-arm64` is **not a ship target** (see
  "Ship targets"), so `.forgejo/workflows/arm64.yml` was deleted rather than parked
  behind `workflow_dispatch`. Both runners are Linux: `glibc` = aarch64,
  `glibc-amd64` = x86_64. No macOS/Windows runner exists.
* **GitHub** (`.github/workflows/ci.yml`) builds `windows-x64` + `macos-arm64`. Those jobs clone
  `https://git.vedaru.cn/Vedaru/oh-my-mc.git` (public, anonymous clone works) so both systems build
  the same commit. Push to both remotes: `git push forgejo master && git push github master`.
  They also publish into a **GitHub** `rolling` release via `publish_github_release.sh`, because the
  workflow artifacts expire in 14 days and require a login: without this, Windows and macOS had no
  public download at all. Linux is published separately on the Forgejo instance (its builds are
  Linux jobs there), and each release body links the other. The two publishers share every rule -
  target-scoped replacement, commit in the asset name, body rebuilt from attached assets, upload
  read back by name - so parallel matrix jobs cannot clobber each other.
* Heavy logic lives in `tool/ci/*.sh`, not YAML, so it can be run and tested locally:
  * `fetch_flutter_sdk.sh <dest> [ver]` — 1.5 GB tarball, retries + resumes + mirrors (CN mirror is
    ~8-22 MB/s and reachable; a bare curl died at 7 min with "Recv failure: Connection reset by peer").
  * `assemble_arm64_toolchain.sh <dest> [ver]` — the hybrid SDK recipe above, automated.
    **This is dev-sandbox bootstrap only, not a CI or release path**: it exists because this
    container is aarch64 and no arm64 Linux SDK is published. `linux-arm64` is not shipped, so
    nothing in CI calls it. Keep it for the local build loop; do not wire it into a workflow.
  * `publish_release.sh` is race-safe in two ways, both learned from the drift it
    replaced: it **adopts** a release another job created a moment earlier
    instead of failing on the create race, and it deletes only assets matching
    its own target. Two jobs therefore converge on one release without any
    inter-job file passing (which this instance cannot do - no
    `actions/upload-artifact`, since the action source is github.com).
  * `publish_github_release.sh <root> <target> <sha>` — the same contract for the GitHub mirror
    (`windows-x64`, `macos-arm64`), on `GH_TOKEN` = the workflow's own `GITHUB_TOKEN`, so no
    hand-made secret is needed. Uploads go to **`uploads.github.com`**, not `api.github.com` - the
    REST path answers 404 for assets, which reads like a permissions problem and is not.
  * `package_linux.sh <root> <target>` / `publish_release.sh <root> <target> <sha>` — ONE rolling
    release tagged `rolling`, holding `oh-my-mc-linux-x64-<commit>.tar.gz`. Each build job
    uploads into it independently (no `actions/upload-artifact` on this instance). The script
    **never deletes the release**, and only deletes assets whose name contains its own target, so
    one failing job cannot remove the other architecture's good artifact. Assets carry their
    commit in the name so a leftover from an older commit is visible rather than passed off as
    current.

### Traps that cost real time
* **`flutter build linux --release` fails on arm64 with "font-subset utility is
  missing"** unless you pass `--no-tree-shake-icons`. The engine ships
  `font-subset` only for `linux-x64`; the arm64 artifacts directory has none.
  No CI job passes the flag, because no shipped Linux target is arm64 — this is
  purely a **local build-loop** constraint. Note this also means this
  dev sandbox (aarch64) cannot do a plain `flutter build linux --release` at all,
  even though `flutter doctor` reports the Linux toolchain as fine - the check
  the doctor performs is not the one the icon tree-shaker needs.
* **The `glibc` (aarch64) runner is down, and no repo fix exists for it.**
  Since 2026-10-21 every job on `runs-on: glibc` fails in exactly **1s**, including
  a throwaway `run: 'echo hello'`, so the container is never created and no step
  runs. It was green on `4bee9c9a` (71s) with a byte-identical workflow.
  `continue-on-error: true` is **not honoured** (job still concludes `failure`),
  so a build cannot be kept green while the runner is dead - do not try.
  This no longer costs anything: `linux-arm64` is not a ship target, so the
  `arm64.yml` workflow was deleted instead of being kept dispatch-only. The dead
  `glibc` label is still worth knowing about, because it is the reason a future
  "just add an arm64 Linux build" idea cannot be implemented on this instance.
  Diagnostic ladder that actually discriminates (in order): is the failure
  duration ~1s (never started) vs minutes (real build failure); does a
  `run: 'echo hello'` job on that label fail too; do gate/`build-linux-x64` on
  `glibc-amd64` pass on the same commit; is `ci.yml` identical to the last green
  commit. There is **no log endpoint** in this Forgejo API (only
  `/actions/tasks`), and web log pages require a session login that a token
  cannot supply - so probe workflows that write their findings to an issue
  comment are the only way to see what a job saw.
* **The runner image avoids the SDK download, but a stale `dist/` does not.**
  CI installs nothing; each job's `flutter` comes from the image. The old
  per-job `fetch_flutter_sdk.sh` / `assemble_arm64_toolchain.sh` paths are only
  reachable by hand now, so they are not on any CI critical path - do not
  re-add them when a build "seems slow", the download was removed deliberately.
* **Publishing a GitHub release needs `permissions: contents: write`.** Without it the
  default `GITHUB_TOKEN` is read-only and release creation answers 403 *"Resource not
  accessible by integration"*, which reads like a bad token rather than a missing
  permission. Also: asset uploads live on **`uploads.github.com`**; posting to
  `api.github.com/repos/{o}/{r}/releases/{id}/assets` answers 404 and looks like a
  permissions bug too.
* **`sha256sum` does not exist on macOS** (GNU coreutils). Anything shared with the
  macOS job must hash via `python3`/`shasum`. The python3 form is byte-identical to
  `sha256sum` output, so the `.sha256` files stay comparable across targets.
* `tar -tzf ... | grep -q NAME` under `set -o pipefail` **fails on a good archive**: grep exits at the
  first match, tar takes SIGPIPE, pipeline status is non-zero. Capture the listing first.
* The Forgejo release API returns `{"message":"repo is empty"}` until the first push lands.
* Job logs are not in the REST API. Fetch them from the web UI:
  `https://git.vedaru.cn/<owner>/<repo>/actions/runs/<n>/jobs/<i>/logs`.
* `assert s.count(x)` against YAML written by hand is fragile — rewrite the file instead of patching it.

## Launch traps (M4.1)

* **Versions before 1.13 carry no `arguments.jvm` at all.** Mojang's launcher
  supplied the JVM block itself in that era, so `renderArguments(..., ArgSide.jvm)`
  returned `[]` — and the resulting argv was `java <mainClass> <gameArgs>`, which
  a real JVM rejects with `Could not find or load main class`. Verified by running
  that exact argv against Temurin 17. The synthesized block must contain
  `-Djava.library.path` **and** `-cp`; both are needed, and `-cp` must carry the
  joined classpath as a single argv entry.
* **An existing test asserted the bug.** `legacy versions render no jvm arguments
  of their own` expected `isEmpty`, and `launch_plan_test` asserted
  `plan.args.first == mainClass` for 1.12.2. Both were true statements about
  broken behaviour. When a test's *name* says "and still gets natives", check
  whether it is documenting a gap rather than a contract.
* **Classpath entries come out of `buildLibraryGraph` as maven-relative paths.**
  Joining them directly hands the JVM `com/google/gson/...`, which it resolves
  against the *process* CWD — not the game directory. Always route through
  `buildClasspath`, which also appends the client jar (last, so modloader-patched
  libraries keep first-wins precedence).
* **A test using an absolute temp root cannot detect a missing `p.absolute`.**
  `p.absolute` is a no-op on an absolute path, so the assertion passes either way.
  The regression test must use a relative `GamePaths('relative-mc')`. Found by
  mutation: the first version of this test survived deletion of the call.
* **`logging.client.argument` is `-Dlog4j.configurationFile=${path}`, and the
  metadata names the file separately in `logging.client.file.id`.** Substituting
  the *directory* for `${path}` makes log4j fail silently and the game exits with
  no diagnostic. Use `p.join(loggingConfigs, file.id)`.
* **`javaTooOld` must be fatal.** It is tempting to treat every blocker except
  "no runtime" as a warning; launching 1.20.1 on Java 8 does start a process and
  then dies with `UnsupportedClassVersionError`, which is a much worse user
  experience than refusing. `javaMajorMismatch` (newer than declared) *is* a
  warning — the game runs, only mods that assume the major are at risk.
* **`tool/verify_launch.dart` is the only check that proves the argv is real.**
  Unit tests assert what we *believe* the JVM accepts; this runs a real JDK
  against a real install with the main class swapped for a stub. It caught the
  log4j bug that every unit test passed over. Run it after touching
  `launch_service.dart`:
  `dart run tool/verify_launch.dart <jdk-home> <mc-dir>`.

## Installer traps (M3.5)

* **`FileDownloader.download(concurrency:)` was ignored** — the loop awaited each
  task in turn. A modern version is ~3000 small assets, so the difference is
  minutes. Fixed with a bounded worker pool that still runs priority *bands* in
  sequence (metadata before libraries before assets). The concurrency test needs
  a server-side delay plus a count of in-flight requests; without the delay a
  serial implementation passes because localhost is too fast to overlap.
* **`ZipDecoder` returns an empty `Archive` for bytes that are not a zip** rather
  than throwing. A truncated download or a mirror's HTML error page therefore
  produced a *silently empty* natives directory and a "successful" install. Check
  for the `PK` header and a non-empty entry list explicitly.
* **Asset index keys are attacker-influenced.** The index is a downloaded file and
  its keys were joined straight into a path, so a poisoned index could write
  outside the game directory. `safeRelativeEntryName` is now shared by natives
  extraction and asset materialization. The `p.isWithin` re-check after
  normalisation is genuinely unreachable given the name guard — it is kept as
  defence in depth, which means removing it does **not** fail a test. Do not
  read its survival as "untested logic is fine"; the name guard is what is
  tested.
* **The client jar lands under the *child's* directory** when a modloader profile
  omits `jar`. Only a profile that sets `jar` points at the parent. Assertions
  about jar location get this backwards easily.
* **`resources.download.minecraft.net` is hardcoded in `AssetObject.url`**; a test
  cannot intercept it. `urlWithBase(base)` plus `planInstall(assetBaseUrl:)` and
  `VersionInstaller.install(assetBaseUrl:)` exist so the synthetic fixture never
  touches the network. Mirror support will want the same seam.
* **A test that writes to a fixed `/tmp` path is self-poisoning**: the first
  failing run leaves the file, and the next run's `existsSync() == false`
  assertion passes for the wrong reason. Use the per-test temp dir.
* **`dart_test.yaml` `exclude_tags` cannot be overridden from the command line**
  (`--tags network` still excludes it, and `-x ""` is rejected). Gate the network
  test on an env var instead, and keep it in the normal suite so `flutter test`
  still compiles it — otherwise the file rots silently.
