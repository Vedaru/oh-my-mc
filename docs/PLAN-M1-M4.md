# Implementation Plan — M1 → M4 (core engine, motion foundation, first real screens)

> **Superseded in part.** `docs/PLAN-M3.4-M5.md` audits this document against the code and
> corrects it: M2's planner and downloader were never connected, natives are never extracted,
> and no state layer exists. Read this file for design *rationale* (§0 traps, §3 motion
> architecture), and read the newer file for *status and next steps*.

**Status:** proposed, ready to execute
**Builds on:** `docs/PLAN.md` (M0 + M0.5 complete)
**Date:** 2026-10-21

This document is the *execution* plan for the next four milestones. It exists because
probing the actual installed packages invalidated several claims in `docs/PLAN.md` §2 and §6.
Those corrections are listed first, because every later decision depends on them.

Everything marked **[verified]** below was executed in this sandbox (compile probe,
`flutter test`, or package source read). Nothing here is inferred from a README.

---

## 0. Corrections to `docs/PLAN.md` (found by probing, not by reading)

### 0.1 The big one: Flutter 3.47 split Material into a separate package

`fluent_ui 4.17.0`, `animations 3.0.0` and `go_router 18.1.1` **all** depend on
`material_ui ^1.x` — the new standalone Material package — not on `package:flutter/material.dart`.
`package:flutter/material.dart` still exists in the SDK (a parallel copy), so both trees compile,
but they are **different type universes**:

```
error • A value of type 'ThemeData' can't be assigned to a variable of type 'ThemeData?'
```

That is `material_ui.ThemeData` vs `flutter/material.dart`'s `ThemeData`. They are unrelated
classes with identical names. **[verified — compile probe]**

Consequence, and it is the single most important decision in this document:

> The content layer imports `package:material_ui/material_ui.dart`.
> Nothing we write imports `package:flutter/material.dart`.

If we mix them, we get two independent `Theme`, `Navigator`, `Overlay` and
`MaterialLocalizations` trees, and theming/transitions silently disagree. Also
`material_ui`'s localizations are its own (`GlobalMaterialLocalizations.delegates`), so mixing
would break zh l10n in one half of the UI only.

**[verified]** `fluent_ui` does *not* collide with `material_ui` on import: it re-exports a
narrow allow-list (`MaterialLocalizations`, `SelectionArea`, `ThemeMode`, …) rather than `*`.
So `import 'package:fluent_ui/fluent_ui.dart'` + `import 'package:material_ui/material_ui.dart'`
in the same file compiles.

### 0.2 `SlideAnimationConfiguration` does not exist

`PLAN.md` §2.1 lists `SlideAnimationConfiguration` among the fork's API. It is not there.
The package's full surface is: `AnimationLimiter`, `AnimationConfiguration`
(`.synchronized` / `.staggeredList` / `.staggeredGrid` / `.toStaggeredList`),
`SlideAnimation`, `FadeInAnimation`, `ScaleAnimation`, `FlipAnimation`.

There is also **no `staggeredColumn`** — the plan's §6.4 uses that name; the real helper is
`AnimationConfiguration.toStaggeredList`. **[verified — source read]**

### 0.3 The fork's stagger step is `duration ~/ 6` by default, not a 40 ms cap

`PLAN.md` §6.1 specifies `Stagger.step = 40ms, maxTotal = 320ms`. The package computes
`delay = delay ?? duration ~/ 6` per item with **no total cap**, so a 200-item grid would
run `200 * 62ms ≈ 12s` of entrance animation. The plan's "capped so long lists don't crawl"
is therefore not something the package gives us — we must pass an explicit `delay` and stop
passing `position` past a budget. **[verified — `animation_configurator.dart`]**

### 0.4 Neither animation package honours reduced motion

`grep -rn "disableAnimations|AccessibilityFeatures|accessibleNavigation"` over both
`flutter_staggered_animations_plus` and `simple_animations` → **zero hits**. Confirmed at
runtime: with `MediaQuery(disableAnimations: true)`, `LoopAnimationBuilder` keeps producing
frames. **[verified]**

So `PLAN.md` §6.3 ("when off, all durations collapse to 0") is not achievable by setting a
flag — `MotionScope` must **wrap** the two engines, not configure them. Design in §3.

### 0.5 `flutter_acrylic` has no `macos/` directory

Its README advertises a macOS column, and `pubspec.yaml` routes macOS to
`default_package: macos_window_utils`, but the package ships only `linux/` and `windows/`
native folders. So Mica/acrylic on macOS arrives via `macos_window_utils`, and macOS blur
must be treated as "best-effort, verify on the user's Mac" — not as a parity requirement.
**[verified]** Windows 10 also lags on window drag with acrylic (upstream note); Windows 11 is fine.

### 0.6 Dark mode does not bridge automatically

`FluentApp` derives a Material theme from the Fluent accent and propagates it correctly:

```
accent=ff0078d4  m3.primary=ff0078d4   ← accent bridges [verified]
```

but `FluentThemeData.brightness` defaults to `light` regardless of `themeMode`, so with
`themeMode: dark` the content layer still sees `Brightness.light` and a translucent
`surface` (`b3ffffff`). The fix is to always pass
`FluentThemeData(brightness: Brightness.dark, …)` in `darkTheme`; then M3 reports
`Brightness.dark` / `surface=111318`. **[verified]**

This is a real trap: it produces a light-on-light UI that a golden test would happily record
as "correct".

**Resolved in M3.2.** `AppTheme` passes `brightness` explicitly to `FluentThemeData` and derives the
Material scheme from the same value, so one seed feeds both. Proven, not assumed: omitting the
argument makes 4 unit tests fail and the dark golden differ by **100% of its pixels**.

---

## 1. Verified baseline (what actually works today)

| Fact | Evidence |
|---|---|
| `FluentApp` + `material_ui` content + `GoRouter` compose and render | widget test, page found |
| `zh_CN` resolves; `cancelButtonLabel` → `取消` | widget test through `FluentApp` locale |
| Fluent accent ⇒ M3 `colorScheme.primary` | widget test, 3 accents |
| `fluent_ui` + `material_ui` imports coexist without ambiguity | `flutter analyze` clean |
| M3 inventory we need all exists in `material_ui`: `Card`, `ListTile`, `Linear/CircularProgressIndicator`, `Switch`, `Slider`, `FilledButton`, `NavigationRail`, `Chip`, `Tooltip`, `SnackBar`, `AnimatedList`, `MaterialPage(Route)` | compile probe |
| `material_ui` can be a direct dependency (1.x resolves, no conflict) | `flutter pub add --dry-run` |
| MC endpoints live: `piston-meta` 200 (278 KB, 51 ms), `meta.fabricmc.net` 200, `api.modrinth.com` 200 | curl |
| `flutter analyze --fatal-infos` clean at HEAD | run |

Known-good toolchain invocation (unchanged from `AGENTS.md`):

```bash
export PATH=/home/openhands/flutter/bin:$PATH PUB_CACHE=/home/openhands/.pub-cache
```

---

## 2. Import law (enforced by CI, not by memory)

| Layer | May import | May **not** import |
|---|---|---|
| `lib/core/**` | `dart:*`, pure pub packages | `flutter/**`, `fluent_ui`, `material_ui` |
| `lib/ui/motion/**` | `flutter/widgets`, the 3 motion packages | `material_ui`, `fluent_ui` |
| `lib/ui/shell/**` | `fluent_ui` | `material_ui` (except via re-export shim) |
| `lib/ui/<screen>/**` | `material_ui` | `package:flutter/material.dart` |

Two tool checks, both cheap and both in the gate:

1. `tool/check_imports.dart` — walks `lib/`, fails on `package:flutter/material.dart` **anywhere**,
   and on `package:flutter/` under `lib/core/`.
2. `tool/check_tokens.dart` — fails on `Duration(` / `Curves.` outside `lib/ui/motion/motion.dart`
   (already planned in `PLAN.md` §9; now it must also allow `motion.dart`'s own internals).

`package:flutter/material.dart` gets a one-line `// ignore` only in generated code, never by hand.

---

## 3. Motion architecture (the "fluent animations" part, made correct)

### 3.1 Why `MotionScope` must wrap, not configure

Since neither engine reads `disableAnimations` (§0.4), the only reliable collapse point is the
widget boundary. `MotionScope` exposes:

```dart
class Motion {
  const Motion({required this.durations, required this.curve, required this.enabled});
  Duration of(Duration nominal);           // returns Duration.zero when !enabled
  bool get enabled;
}
```

and the primitives in `lib/ui/motion/` consult it:

- `StaggerItem` — when disabled, renders `child` with **no** `AnimationConfiguration` at all
  (not "duration zero"), because `AnimationExecutor` starts a 0 ms controller that still costs
  a frame and a `setState`.
- `AmbientLoop` — when disabled, renders the builder's steady-state frame once and does not
  create the ticker. This is the one place we deliberately diverge from the package.
- `PressFeedback`, `Reveal` — `MovieTween` still used for the enabled path; disabled path returns
  the end value directly.

`MediaQuery.disableAnimations` ORs with the user setting; the user setting can only force
*less* motion, never more. **[design rule]**

### 3.2 Stagger budget, not stagger step

Because the package has no cap (§0.3), the wrapper computes the delay:

```
step = min(cfg.step, cfg.maxTotal ~/ max(1, visibleItemCount))
position = min(index, cfg.maxAnimatedIndex)   // default 24
```

Items past the cap render unanimated (already at rest). This gives a bounded entrance
(≤ 320 ms of stagger + one item duration) regardless of list length, and it is testable
as a pure function — put it in `lib/ui/motion/stagger_budget.dart` with unit tests, no widgets.

### 3.3 Tokens

`Durations` / `Curves_` / `Stagger` stay the single source of truth.
Change from `PLAN.md` §6.1: **no** `staggeredColumn` (use `toStaggeredList`), and `Stagger`
gains `maxTotal` + `maxAnimatedIndex` as described above.

---

## 4. Milestones

### M1 — Core MC engine (pure Dart)

No UI, no Flutter imports. This is where launchers actually break, so it lands first and is
tested against **real captured JSON**, trimmed and committed under `test/fixtures/mc/`.

| Task | Deliverable |
|---|---|
| 1.1 | `tool/capture_fixtures.dart` — fetches manifest + 4 version JSONs, trims to the fields we consume, writes fixtures. Re-runnable; the repo keeps the snapshots so tests stay offline. |
| 1.2 | `version_manifest.dart` — fetch/cache/TTL + `MirrorChain` (official → BMCLAPI) |
| 1.3 | `version_json.dart` — full model, **unknown fields preserved** via a `Map<String, dynamic> raw` escape hatch |
| 1.4 | `rules.dart` — `os.name/arch/version` + `features`; `RuleContext` injected |
| 1.5 | `version_resolver.dart` — `inheritsFrom` walk, library dedupe (last wins), arg concat |
| 1.6 | `library_graph.dart` — classpath order, natives extraction (legacy classifiers) |
| 1.7 | `asset_index.dart` — modern objects vs legacy virtual/`map_to_resources` |
| 1.8 | `jvm_args.dart` — placeholder expansion for both `arguments` and `minecraftArguments` |
| 1.9 | `arch_compat.dart` — the macOS-arm64 LWJGL2 blocker (`PLAN.md` §3.5.2) |

**Acceptance (all offline):** golden tests over fixtures for **26.3** (Java 25, no natives),
**1.20.1** (Java 17), **1.12.2** + **1.8.9** (legacy args, natives classifiers, virtual assets),
plus synthetic Forge/Fabric inheritance chains. Assertions: byte-exact argv for a fixed
account/instance, classpath order + dedupe, per-`(os, arch)` natives set, `javaMajor` per
version, asset policy per index type, and that `arch_compat` blocks exactly the LWJGL2 +
macOS-arm64 case.

### M2 — Downloader, Java manager, install pipeline

| Task | Deliverable |
|---|---|
| 2.1 | `Downloader` — priority queue, N workers, `.part` → hash → atomic rename, cancel, retry/backoff |
| 2.2 | `HashCache` — skip re-hash on `(size, mtime)` match |
| 2.3 | `MirrorChain` failover — 3 consecutive failures trip a host out |
| 2.4 | `Stream<DownloadProgress>` aggregate (bytes, files, speed, ETA) |
| 2.5 | `JavaManager` — scan PATH/registry/common dirs, `-XshowSettings:properties`, find-by-major |
| 2.6 | Install pipeline — manifest → version → libraries → assets, resumable |

**Acceptance:** unit tests against a local `HttpServer` (404 → mirror retry, hash mismatch →
one re-download then fail, cancel leaves no `.part`, resume continues from byte offset).
One `@Tags(['network'])` integration test installs real 1.20.1 metadata into a temp dir.

### M3 — Design system + motion foundation + shell

Now the UI layer opens, in this order (each step demos something):

1. `motion.dart` (tokens) → `MotionScope` → `stagger_budget.dart` (+ unit tests) → primitives
2. `app_theme.dart` — one source: Fluent theme + **explicit `brightness` in both** (§0.6),
   accent ⇒ M3 seed. Golden-tested in light *and* dark so the §0.6 trap cannot regress.
3. ✅ **Done.** `l10n.yaml` + `lib/l10n/app_en.arb`, `app_zh.arb`; `AppLocalizations` generated
   into `lib/l10n/generated/` and **committed** (Flutter 3.47 removed synthetic packages, and
   `flutter pub get` regenerates it, so a fresh clone and CI need no extra step). Every string
   goes through it from the first widget, per `PLAN.md` §11.3. One delegate gotcha cost real
   time and is worth recording: `AppLocalizations.localizationsDelegates` also installs
   `GlobalMaterialLocalizations`/`GlobalCupertinoLocalizations`, whose types come from the
   **in-SDK** Material copy rather than `material_ui` - the second tree §2's import law exists
   to prevent. We ship our own list (`lib/l10n/l10n.dart`: `AppLocalizations`,
   `GlobalWidgetsLocalizations`, `FluentLocalizations`), and `tool/check_imports.dart` now
   bans `flutter_localizations` outside that one file.
4. `router.dart` — `GoRouter` inside `FluentApp.router`, one route per `PLAN.md` §7 screen,
   each rendering a placeholder. This proves navigation before any screen is real.
5. `shell/` — `NavigationView` + custom `TitleBar` + `window_manager` sizing/min-size;
   `flutter_acrylic` behind a `WindowEffects` abstraction that no-ops where unsupported (§0.5).
6. Splash → shell `SharedAxisTransition`; log drawer scaffold.

**Acceptance:** widget tests for (a) reduced motion — every primitive collapses and **creates no
ticker**; (b) stagger budget — item 30+ renders at rest, step shrinks for long lists;
(c) dark mode — M3 `brightness` is `dark` and `surface` is opaque; (d) navigation — each route
reachable and localized in en + zh (the l10n half is covered now: `test/l10n/` renders the real
app root in both languages and asserts ARB key/translation parity, so a forgotten zh string
fails the suite instead of silently rendering English); (e) goldens for shell in light/dark at 3 keyframes.

### M4 — First real vertical slice: launch screen + instance list

Instance model/store (`instance.json`), staggered grid with `Hero` to detail, play-button state
machine on a fake `LaunchHandle`, log console. This is the first screen the user will actually
look at, so it is the first milestone with a visual sign-off gate.

**Acceptance:** tapping play drives `idle → preparing → running → exited` against a fake process;
200-item grid scrolls without rebuilding off-screen items; goldens reviewed by the user.

---

## 5. Ordering rationale

M1 and M2 are UI-free and fully testable here, so they can proceed while the visual language is
still being decided. M3 is deliberately *narrow* (tokens, theme, motion, shell, l10n, routing)
because every later screen multiplies whatever conventions it sets — and §0.1 means those
conventions include an import law that is painful to retrofit. M4 is the smallest slice that is
worth a human looking at.

The one thing I will not do is start screens before `MotionScope` exists, because the packages
make reduced motion a no-op (§0.4) and retrofitting a collapse point into 8 finished screens is
strictly worse than building on it.

---

## 6. Risks introduced by this plan

| Risk | Mitigation |
|---|---|
| `material_ui` is young (1.8.0) and may churn | it is already a transitive dep of `fluent_ui`/`go_router`/`animations`, so we cannot avoid it; pinning happens via `pubspec.lock`. Import law makes a future switch mechanical. |
| Two Material libraries in the tree bloat the binary and confuse contributors | `tool/check_imports.dart` in the gate; documented in `AGENTS.md`. |
| `simple_animations` ignores reduced motion | we wrap it (§3.1) and test that no ticker is created. |
| Package stagger has no cap | budget computed in our wrapper, unit-tested (§3.2). |
| Dark mode bridge trap (§0.6) | goldens in dark from M3 step 2, before any real screen exists. |
| Fixtures drift as MC matures | `tool/capture_fixtures.dart` is re-runnable; tests pin the snapshot, not the network. |

---

## 7. Definition of done for this phase

`flutter analyze --fatal-infos` clean, `dart format` clean, both import/token checks green, all
new tests passing offline, and: launching the app shows an animated, localized (en/zh),
light+dark shell, navigates to every placeholder route, and respects the reduced-motion toggle
by creating no tickers. No screen in this phase reads the network at build time.
