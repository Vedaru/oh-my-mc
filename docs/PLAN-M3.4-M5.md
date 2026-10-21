# Implementation Plan — M3.4 → M5 (shell, first screens, real launch)

Continues `docs/PLAN-M1-M4.md` (M1–M3.3). This file re-states only what changed since, and
closes the gap between "the plan says M2 is done" and what the code actually does.

Everything below was checked against the tree at `4a99fd3`, not taken from the previous
document's checklist. Where the two disagree, this file wins.

---

## 0. What the previous plan got wrong

The M1–M4 document is accurate about *design decisions* and optimistic about *completion*.
Four claims did not survive inspection.

### 0.1 M2 is two half-systems that were never connected

`FileDownloader` (16 tests, real `HttpServer`) and `planInstall` → `InstallPlan` (20 tests) both
exist and both work in isolation. **Nothing in `lib/` calls either one.** The only caller of
`FileDownloader` in the entire repo is `tool/smoke_download.dart`.

So "install pipeline" exists as *a planner that emits a list* and *a downloader that executes
a list*, with no code that goes manifest → resolver → plan → downloader → verified tree. That
glue is not a refactor; it is the feature, and it is the single largest thing standing between
the current state and a launcher that can launch.

### 0.2 Natives are planned but never extracted

`library_graph.dart` correctly computes `NativeArchive{file, exclude}` per `(os, arch)`.
`install_plan.dart` counts natives bytes into the `InstallStage.natives` bucket. `launch_plan.dart`
accepts a `nativeArchives` list.

But: `GamePaths.natives(id)` is **never called**, `virtualAssets` and `legacyResources` are
**never called**, and `package:archive` is imported by **zero files** despite being a dependency.
Because natives are never unpacked to a directory, `launch_plan` has no real natives path to
point `-Djava.library.path` at, and legacy `virtual`/`map_to_resources` asset layouts produce a
plan whose objects live under `assets/objects` while the game looks for them by name.

This is not cosmetic. LWJGL needs the `.so`/`.dll` present in the natives dir, or 1.12.2 and
older fail at window creation. It is exactly the class of bug that "the build is green" hides.

### 0.3 There is no state layer at all

`flutter_riverpod` is a dependency with **zero importers**. There is no `lib/data/`, no
`lib/app/`, no `Instance` model, no settings persistence (`shared_preferences` also unused), and
`lib/ui/shell/` is an empty directory.

`main.dart` is a `StatelessWidget` that hardcodes `Motion.full` and renders
`Text(appTitle)` inside a bare `NavigationView`. Every choice the `/setup` screen is supposed to
control — language, theme mode, motion — is currently a constructor parameter that only tests
pass.

### 0.4 Sixteen dependencies are declared and unused

Of the 18 non-SDK runtime dependencies, **16 have zero importers** in `lib/`:
`flutter_riverpod`, `go_router`, `window_manager`, `flutter_acrylic`, `animations`, `dio`,
`json_annotation`, `freezed_annotation`, `shared_preferences`, `flutter_secure_storage`,
`file_picker`, `oauth2`, `process_run`, `system_info2`, `url_launcher`, `lucide_icons`.
Only `simple_animations` and `flutter_staggered_animations_plus` are actually used.

That is not a defect to fix in one sweep (each arrives with the milestone that needs it), but the
plan below says **which milestone** each one becomes real, so none of them silently rot into
"declared for two years, never used".

---

## 1. Verified baseline

What is true today, measured rather than assumed:

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed` | clean, 50 files |
| `flutter analyze --fatal-infos` | clean |
| `dart run tool/check_imports.dart` | clean, 25 files |
| `dart run tool/check_tokens.dart` | clean |
| `flutter test` | **248 tests green** |
| Gate enforced where | Forgejo `gate` job runs all five; GitHub `ci-desktop` runs its own |

Probes run for this plan (each a throwaway test, deleted after):

| Probe | Result |
|---|---|
| `GoRouter` installed via `FluentApp.router(routerConfig:)` | **works**; routes resolve, `go()` navigates |
| `AppLocalizations` reachable *below* the router's `Navigator` | **works**; `context.l10n` resolves in page bodies |
| `SharedAxisTransition` as `CustomTransitionPage.transitionsBuilder` | **works**; both pages mounted mid-transition |
| `MotionScope.of(context).enabled` readable inside `pageBuilder` | **works**, so the transition can be chosen per navigation |
| Zero-duration `CustomTransitionPage` under `Motion.none` | **settles in one pump** (`A=0 B=1`), i.e. reduced motion costs no frame |
| `sha256sum` on the macOS runner | **absent** — now hashed via python3 in both publishers |

**Two reduced-motion variants work.** Keeping `CustomTransitionPage` with
`transitionDuration: motion.of(Durations.slow)` collapses to zero and still settles in a single
frame, so there is no need to branch on page *type*. One code path, one page class, duration is
the only variable — which is also what makes the reduced-motion test assert something real (the
duration is zero, not the widget is different).

---

## 2. Decisions taken here (so they are not re-litigated per screen)

1. **Router owns page transitions; widgets do not.** A screen never constructs a
   `PageRoute`. `lib/app/router.dart` builds every route through one `_page()` helper that reads
   `MotionScope` and the current axis, so "reduced motion" and "which direction" are decided in
   one place. Without this, 8 screens drift into 8 transition styles.
2. **`MotionScope` moves up, above `MaterialApp`/`FluentApp`.** It already works from the root in
   `main.dart`, but the shell must be able to *change* it from `/setup`, so the scope's value
   becomes a provider read in the app root rather than a constant.
3. **Settings persistence lands with the shell, not with `/setup`.** The shell is the first thing
   that has to *remember* something (last route, language, motion). Building `/setup` first would
   mean writing the preference mechanism twice.
4. **Installer glue lands before any install UI.** `M3.5` below is a pure-Dart milestone with no
   widgets, because the moment an install screen exists it will be blamed for whatever the
   missing glue got wrong.
5. **No new dependency without a named milestone.** Item 0.4 is the cautionary tale.

---

## 3. Milestones

### M3.4 — Shell + router (UI, needs design signoff)

Blocks on: user's visual decisions for the title bar, nav pane and splash. The *structural* work
below can proceed independently and is what I can do without deciding how anything looks.

| Task | Deliverable | Depends on user |
|---|---|---|
| 3.4.1 | `lib/app/router.dart` — 8 routes from `PLAN.md` §7, one `_page()` helper, `GoRouter` as a provider so `/instances/:id` can be reached by id | no |
| 3.4.2 | Route table test: every route reachable, each renders its placeholder, back/forward, unknown route → `/launch` | no |
| 3.4.3 | Transition test: full motion ⇒ mid-transition both pages mounted; `Motion.none` ⇒ settles in one pump | no |
| 3.4.4 | `lib/app/app_root.dart` — `ProviderScope` + settings-driven `MotionScope`/`themeMode`/`locale`; `main.dart` shrinks to bootstrap | no |
| 3.4.5 | `NavigationView` shell: pane items bound to routes, selection reflects `GoRouterState` (a deep link must highlight the right item) | **yes** |
| 3.4.6 | Custom title bar + `window_manager` min-size; `WindowEffects` abstraction so acrylic no-ops where unsupported | **yes** |
| 3.4.7 | Splash → shell via `SharedAxisTransition`; log drawer scaffold | **yes** |

Acceptance: route table test green; reduced-motion transition test green; `NavigationView`
selection follows a programmatic `go()`; no screen imports `go_router` to build its own page.

### M3.5 — Installer glue (pure Dart, no UI) ← the real M2 completion

The milestone that makes the launcher capable of installing something.

| Task | Deliverable |
|---|---|
| 3.5.1 | `VersionInstaller`: manifest lookup → `version_resolver` (inheritsFrom chain) → `planInstall` → `FileDownloader.download` → stage-by-stage progress |
| 3.5.2 | **Natives extraction** — unzip into `GamePaths.natives(id)`, honouring `extract.exclude`; idempotent; refuses path traversal |
| 3.5.3 | **Legacy asset layouts** — `virtual` → `assets/virtual/<id>/*`, `map_to_resources` → `resources/*`; makes `virtualAssets`/`legacyResources` real |
| 3.5.4 | Java resolution inside the pipeline: `java_requirement` → `JavaManager.findByMajor` → download if missing |
| 3.5.5 | `verifyInstall` — every path in the plan exists with the right hash; returns the missing list rather than throwing |
| 3.5.6 | Cancel propagates downloader → extraction → leaves no half-unpacked natives dir |

Acceptance: local `HttpServer` fixture serves a **synthetic** version chain with natives and a
`virtual` asset index; assert final tree byte-for-byte (file set, hashes, natives contents,
virtual copies). Cancel mid-extraction leaves no natives dir. `@Tags(['network'])` test installs
real 1.20.1 into a temp dir and asserts `verifyInstall` is empty.

Why synthetic for the main test: the fixture must exercise natives + virtual assets *together*,
and no single real version has both. 1.12.2 has natives, 1.6.4 has `virtual` — a synthetic merge
covers both in one pass, and the network test covers the "real metadata still parses" concern.

### M4 — Launch screen + instance list (first vertical slice)

| Task | Deliverable |
|---|---|
| 4.1 | `Instance` model + `InstanceStore` over `instance.json`; one instance per version dir, plus a default |
| 4.2 | `LaunchHandle` abstraction: real process behind it, fake in tests |
| 4.3 | Launch screen: instance picker, account chip stub, play/stop, staged progress |
| 4.4 | Instance grid with `StaggerItem`, `Hero` to detail, 200-item scroll without rebuilding off-screen items |
| 4.5 | Play-button state machine `idle → preparing → running → exited` on a fake handle |
| 4.6 | Log console wired to the handle's stream |

Acceptance: state-machine test green; `Motion.none` ⇒ grid renders at rest (no tickers);
goldens in light+dark; 200 items scroll.

### M5 — Real launch end-to-end

| Task | Deliverable |
|---|---|
| 5.1 | Offline auth (`OfflineUser`, deterministic UUID) |
| 5.2 | `Process.start` with the real argv from `assembleLaunchPlan`, streamed stdout/stderr |
| 5.3 | Stop/kill semantics; exit code surfaced |
| 5.4 | **`LaunchBlocker`** surfacing — `arch_compat` refusal and `missingNatives` become a localized dialog before spawn |
| 5.5 | Playtime tracking |
| 5.6 | Device-code MSA auth (needs `oauth2`; first real use) |

Acceptance: on Windows x64 CI, install 1.20.1 offline and launch with a stub main class →
assert argv contains every expected token, exit 0. macOS arm64 asserts the LWJGL2 case is
*blocked*, not launched.

---

## 4. Dependency ledger (when each unused dep becomes real)

So a dep never sits unused for two milestones without a reason on record.

| Dep | Becomes used in |
|---|---|
| `go_router` | M3.4.1 |
| `flutter_riverpod` | M3.4.4 |
| `window_manager` | M3.4.6 |
| `flutter_acrylic` | M3.4.6 |
| `animations` | M3.4.1 (transitions) |
| `archive` | M3.5.2 (natives) |
| `shared_preferences` | M3.4.4 (settings) |
| `json_annotation` + `freezed_annotation` + `build_runner` | M4.1 (`Instance`) — first model with codegen |
| `process_run` | M5.2 — or drop it if `dart:io Process` suffices; decide at implementation |
| `system_info2` | M3.5.4 / M5.4 (arch + memory defaults) |
| `url_launcher` | M5.6 (device-code flow) |
| `oauth2` | M5.6 |
| `file_picker` | M4.1 (import) |
| `flutter_secure_storage` | M5.6 (token storage) |
| `lucide_icons` | **design decision** — only if the user's icon set wants it |
| `dio` | **candidate for removal** — `FileDownloader` is `dart:io` based and works; adding a second HTTP stack would be churn |

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| Router and `NavigationView` disagree about the selected item | 3.4.5 acceptance is exactly `go()` ⇒ pane highlight, tested |
| Two Material trees leak into a screen via a third-party widget | import law already bans the SDK paths; `material_ui` is only imported by `app_theme.dart`, keep it that way |
| Natives extraction zip-slip | explicit refusal of `..`/absolute entries, tested with a malicious archive |
| Reduced motion regressing when a screen adds its own animation | transition logic lives only in `router.dart`; token check bans raw durations outside the motion layer |
| Design signoff becomes the critical path | 3.4.1–3.4.4 are design-free and land first |
| `process_run` vs `dart:io` becoming a rewrite | decided at M5.2 with a 30-minute probe, not now |

---

## 6. Immediate next step

M3.4.1–3.4.4 — router, app root, settings, and their tests. No visual decisions required, and
each is independently verifiable. 3.4.5–3.4.7 wait for the user's shell design.
