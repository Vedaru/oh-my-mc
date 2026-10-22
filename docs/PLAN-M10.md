# Design & motion overhaul — fluent_ui → Material 3 Expressive (M10)

Supersedes `PLAN.md` §6 (motion & design) and the shell/theme parts of §7. Feature
scope is unchanged: **functional parity with PCL 2, pre-2.99**. This document only
changes *what the app is built out of* and *how it moves*.

**Position:** M0–M6.5 landed and green; this is a strike at the visual layer before
M7 (loaders) adds more screens to migrate. **Every number below was measured in this
tree at `4145071` + working tree, 2026-10-22.**

---

## 0. Where the code is

| Gate | Result |
|---|---|
| `flutter test` | **578 passing, 2 skipped** (the 2 are the `shots` golden harness) |
| `dart run tool/check_imports.dart` | `import law OK (62 files checked)` |
| `dart run tool/check_tokens.dart` | `motion tokens OK (62 files checked)` |
| `dart` files importing `package:fluent_ui` | **17 in `lib/`**, **11 in `test/`** |

### 0.1 Why this migration is not cosmetic

`fluent_ui` is the *shell*: `FluentApp` owns `Theme`, `Material`, `Localizations` and
the `Navigator` theme beneath it. Its widget vocabulary is Fluent's own
(`NavigationView`, `ScaffoldPage`, `TextBox`, `InfoBar`, `ContentDialog`,
`ProgressRing`), so nothing Material 3 can be dropped in without first replacing the
app root. The measured surface to replace:

| Fluent symbol | Uses | Replacement |
|---|---|---|
| `Button` / `FilledButton` | 31 / 28 | `M3EButton` (`filled` / `filledTonal` / `outlined` / `text` + `M3EButtonSize`) |
| `FluentTheme` / `FluentThemeData` | 44 / 11 | `M3ETheme` / `M3EThemeData` + our `AppTheme` facade |
| `FluentApp` | 27 | `MaterialApp.router` (`material_ui`) under `M3ETheme` |
| `FluentIcons` | 24 refs, **21 distinct** | `LucideIcons` (already a declared dependency with **zero** imports — D8) |
| `NavigationView` / `NavigationPane` | 12 / 3 | `M3ENavigationRail` (`sections:` API) |
| `TextBox` | 11 | `M3ETextField` |
| `ProgressRing` / `ProgressBar` | 9 / 6 | `M3EProgressIndicator.circular` / `.linear` (`.circularWavy` for the downloader) |
| `ScaffoldPage` | 6 | `m3.Scaffold` (M3E ships **no** `M3EScaffold`) + `M3EAppBar` |
| `ContentDialog` | 6 | `M3EDialog.show` (labelled actions, returns a `Future`) |
| `ToggleSwitch` / `Slider` / `ComboBox` | 5 / 2 / 1 | `M3ESwitch` / `M3ESlider` / `M3EDropdownMenu` |
| `InfoBar` | 3 | **no M3E equivalent** — see §3.4 |
| `HoverButton`, `AccentColor` | 2 / 2 | `M3EIconButton`; `M3EColorScheme` roles |

### 0.2 The four reference repos, and what each is actually for

| Reference | Use | Why |
|---|---|---|
| `The-ring-io/flutter_staggered_animations` | **pattern only** — we already depend on the maintained fork `flutter_staggered_animations_plus ^1.0.4` | Upstream last pushed 2023-03; MIT, no archive, but the fork is what resolves |
| `felixblaschke/simple_animations` | **already a dependency** (`^5.3.0`, actively pushed 2026-05) | `MovieTween` for press/choreography, `LoopAnimationBuilder` for ambience |
| `material-components/material-components-flutter` | **component-pattern reference only** — it is the *catalog*, archived since 2022-09 | Its gallery shows layout/anatomy decisions; it is not a widget library and nothing is copied from it |
| `Meloong-Git/PCL` | **behaviour reference only** — `NOASSERTION` licence, VB.NET | Feature inventory and interaction flow. No code, strings, icons or XAML |

Standing constraint, restated because this milestone touches every pixel: **all art,
copy, icons and layout are original.** Lucide glyphs are ISC-licensed; the app's own
strings go through `AppLocalizations` or they do not ship.

---

## 1. Decisions, with the evidence that forced them

### 1.1 Pin `material_ui: 1.7.0` (not `^1.8.0`)

Verified by building against both. With 1.8.0 and `material_3_expressive 1.1.7` the
compile fails outright:

```
material_3_expressive-1.1.7/.../m3e_refresh_indicator.dart:12:1: Error:
'RoundedPolygon' is imported from both
'package:material_new_shapes/src/shapes/shapes.dart' and
'package:material_ui/src/shapes/rounded_polygon.dart'
```

1.8.0 moved `RoundedPolygon` into `material_ui` itself, colliding with
`material_new_shapes` (which M3E needs). Pin **exactly** `material_ui: 1.7.0` — a caret
range would float back to 1.8.0 on the next `pub upgrade` and break the build with an
unrelated-looking error. M3E itself declares `material_ui: ^1.7.0`, so 1.7.0 is inside
its supported window.

Consequence to record in `AGENTS.md`: **do not** "update dependencies" past this pin
without checking the `RoundedPolygon` collision first.

### 1.2 App root: `MaterialApp.router` + `M3ETheme`, not `M3EMaterialApp`

Probed and passing: `go_router` routes, dark theme, `M3ENavigationRail`, zero idle
tickers, no exception. `M3ETheme` is a plain `StatefulWidget` theme *scope*, not an app,
so it cannot own `routerConfig`; `MaterialApp.router` supplies the `Navigator`, the
localization tree and `MediaQuery`, and `M3ETheme` sits in its `builder` so every routed
page sees the expressive tokens.

```dart
MaterialApp.router(
  routerConfig: router,
  theme: AppTheme.material(Brightness.light),   // material_ui ThemeData
  darkTheme: AppTheme.material(Brightness.dark),
  themeMode: settings.themeMode,
  locale: settings.language == null ? null : Locale(settings.language!),
  supportedLocales: appSupportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  builder: (context, child) => M3ETheme(
    data: AppTheme.expressive(brightness),
    autoTheming: false,
    child: MotionScope(motion: motion, child: child!),
  ),
)
```

Note `M3EColorScheme.fromSeed` takes the seed **positionally**
(`fromSeed(Color seed, {Brightness brightness})`) — a named `seedColor:` argument is a
compile error.

### 1.3 Localization: `...GlobalMaterialLocalizations.delegates` (plural)

`MaterialApp` asserts that every delegate in `supportedLocales` has a localization for
the active locale. With `zh` selected and only the singular
`GlobalMaterialLocalizations.delegate` registered, the app throws *"locale zh is not
supported by all localization delegates"* (the Cupertino delegate is missing).
`GlobalMaterialLocalizations.delegates` is the three-element list
(`GlobalCupertinoLocalizations`, `GlobalMaterialLocalizations`,
`GlobalWidgetsLocalizations`) and is correct.

This is also how `lib/l10n/l10n.dart` stops importing `flutter_localizations` itself:
replace `GlobalWidgetsLocalizations.delegate` + `FluentLocalizations.delegate` with
`...m3.GlobalMaterialLocalizations.delegates`. That deletes the last entry in
`tool/check_imports.dart`'s `_restricted` map — a rule that exists only for Fluent's
sake goes with Fluent. The `flutter_localizations` **pubspec** dependency stays: the
generated `AppLocalizations` imports it for `GlobalMaterialLocalizations` in its own
`localizationsDelegates` list, which we never use.

### 1.4 Icons: Lucide, not the Fluent icon font

Dropping `fluent_ui` also drops `FluentIcons.ttf` and `SegoeIcons.ttf` from the bundle.
`lucide_icons ^0.257.0` is already declared and unused (D8) — this migration is its
consumer. The 21 distinct glyphs map as:

`list→list, download→download, settings→settings, text_document→fileText, play→play,
cube_shape→box, stop→square, add→plus, clock→clock, warning→alertTriangle,
error_badge→alertCircle, code→code, folder_open→folderOpen, search→search,
check_mark→check, completed→checkCircle, completed_solid→checkCircle2, delete→trash2,
edit→edit2, puzzle→puzzle, back→chevronLeft`

`ShellIcons` stays the single mapping point (§`lib/ui/shell/shell_icons.dart`), so this
is one file plus its type (`IconData` still, but from `material_ui`).

### 1.5 Motion stays *ours*: M3E is not reduced-motion aware

Measured: with `MediaQuery(disableAnimations: true)` wrapping
`M3EProgressIndicator.circular`, `transientCallbackCount` was still **3** — identical
to the count with motion enabled. M3E's *idle* components are clean (measured **0**
tickers for `M3EButton` + `M3ESwitch` + `M3ENavigationRail` at rest), so the problem is
narrower than with the animation packages, but the rule from `PLAN.md` §6.3 still holds:

> **`MotionScope` is the policy layer and it wraps, it never configures.** Where motion
> is off, we render the resting frame ourselves rather than asking a package to animate
> to it.

Two consequences specific to M3E:

1. **No looping M3E animation may run when motion is off.** Indeterminate progress is
   the only one we use — swap to a static determinate ring at the last known value.
2. M3E's internal press/ripple springs run at 50–200 ms and are not configurable from
   our side. Accept them (they are short, interruptible, and cannot loop), but do not
   *add* our own transition on top of the same property — double-animating a M3E
   control is the one way to make it feel worse than Fluent.

---

## 2. Migration order

Six waves, each one green before the next. The order is chosen so that the **app root
moves once, at the start**, and every later wave is a leaf change that cannot re-break
the theme/localization tree.

### W1 — Dependency swap (no UI change)

`pubspec.yaml`: remove `fluent_ui`, add `material_3_expressive: ^1.1.7`, pin
`material_ui: 1.7.0`. `dart run tool/check_imports.dart` will fail loudly on all 17
files — that failure *is* the wave's worklist, and it is why the pin and the gate
should land in the same commit.

Also in W1, from the `PLAN.md` §0.3 queue: **D7** (delete the four committed
`test/ui/failures/*.png`), and half of **D8** (resolve `lucide_icons` → kept, its
consumer is §1.4; `system_info2`/`dio` → remove).

### W2 — Root, theme, shell

| File | Change |
|---|---|
| `lib/app/app_root.dart` (129 L) | `FluentApp` → `MaterialApp.router` per §1.2; `themeMode` from settings |
| `lib/ui/theme/app_theme.dart` (61 L) | `FluentThemeData` → `M3EThemeData`; keep `AppTheme.material()` as the projection. Add `AppTheme.text` (§3.2) |
| `lib/l10n/l10n.dart` (37 L) | delegates per §1.3; drop `flutter_localizations` |
| `lib/ui/shell/app_shell.dart` (186 L) | `NavigationView` → `M3ENavigationRail` in a `Row`/`Expanded`; custom title bar keeps `DragToMoveArea` |
| `lib/ui/shell/shell_icons.dart` (34 L) | §1.4 |
| `lib/ui/shell/splash_overlay.dart` (75 L) | token-only; verify `AmbientLoop` still gated |
| `lib/main.dart` (165 L) | window bootstrap (W2 also carries **D6**, below) |

**Layout trap, measured:** `M3ENavigationRail` expands to fill its main axis. In a
`Column` it throws *"RenderFlex children have non-zero flex but incoming height
constraints are unbounded"*. It must be a `Row` child (`Expanded` body) — which is the
natural desktop shell anyway.

### W3 — Launch + instances (the screens users see first)

`launch_screen.dart` (380), `instances_screen.dart` (409), `instance_card.dart` (179).
This is where the motion catalogue (§4) is rebuilt on M3E components: hover lift on
cards, press feedback on play, stagger on the grid.

### W4 — Instance detail + args editor

`instance_detail_screen.dart` (783 — the largest file), `args_field.dart` (132).
`TextBox` → `M3ETextField`, `ContentDialog` → `M3EDialog.show`, `ToggleSwitch` →
`M3ESwitch`. **D4** (JVM/game args editor) is cheapest here, because `_MemoryRow` and
`_JavaRow` are already being rewritten and the args editor is the same shape.

### W5 — Download + setup + logs

`download_screen.dart` (558), `setup_screen.dart` (364), `java_panel.dart` (444),
`logs_screen.dart` (188). Download is also where the expressive progress indicator earns
its keep (`.circularWavy` for indeterminate, `.linear` for staged progress).

### W6 — Test migration + gate rewrite

All 11 test files. Details in §5.

---

## 3. Component-level decisions

### 3.1 Title bar and window chrome

Current state: `window_manager` is imported but **never initialised** (D6) — no
`ensureInitialized`, no `WindowOptions`, no minimum size. And the Linux plugin's
`startDragging` calls `gtk_window_begin_move_drag(window, 1, root_x, root_y, timestamp)`
using `gdk_device_get_position` for coordinates and `g_get_monotonic_time` for the
timestamp.

**Under Wayland that timestamp is not an input serial**, which is what
`xdg_toplevel.move` requires, and root coordinates are meaningless. The call is at best
ignored and at worst drags the window to a wrong place. So:

- **Linux: keep server-side decorations.** Do not set `TitleBarStyle.hidden`. The
  native title bar is correct on both X11 and Wayland, costs no code, and cannot fight
  the compositor. Our 40 px in-app bar stays *inside* the window as a header (drag
  handler kept for X11 where it works, `GestureDetector.onDoubleTap` →
  maximize/unmaximize kept everywhere).
- **Windows/macOS: hidden title bar + custom controls** — `startDragging` there uses
  `SendMessage(WM_NCLBUTTONDOWN)` and `performWindowDrag`, both reliable.
- `main.dart` gains, before `runApp`: `windowManager.ensureInitialized()`,
  `WindowOptions(size: Size(1200, 780), minimumSize: Size(940, 620), center: true,
  title: l10n.appTitle)`. The minimum size is not cosmetic — the rail plus a three-column
  instance grid genuinely does not fit below ~900 px.

This supersedes the `AGENTS.md` Mica claim: `flutter_acrylic` is Windows-only and stays
unused until there is a Windows runner to verify it on.

### 3.2 Typography: one facade, so screens never name a package

`theme.typography.title` / `.caption` (`FluentThemeData`) has no M3E twin. Rather than
rewrite 44 call sites twice over the life of the project, `AppTheme` exposes semantic
text roles (`AppTheme.text.title(context)`, `.caption(context)`, `.body(context)`), and
those are the only typography entry points outside `app_theme.dart`. A comment in that
file records that Fluent's `caption` (12 px) maps to M3E's `labelMedium`.

### 3.3 `.of(context)` accessors, and who may call them

`FluentTheme.of` asserts a non-null ancestor. `M3ETheme.of` / `M3ETheme.maybeOf` must be
reachable from every routed page — guaranteed by putting `M3ETheme` in
`MaterialApp.builder`, which is *above* the router's `Navigator`. Plan a widget test that
pumps a deep route directly and asserts `M3ETheme.maybeOf(context)` is non-null; that
test is the cheap insurance against re-introducing the theme-in-two-places bug that
`PLAN.md` §6.2 warns about.

### 3.4 `InfoBar` has no M3E equivalent

`M3E` ships snackbars and banners are absent. Three call sites (launch errors, download
warnings, setup validation). Build **one** small `AppBanner` widget on M3E tokens
(`colorScheme.emphasis` / `.danger` / `.success` roles), used by all three, rather than
three ad-hoc containers. It needs: icon, message, optional action, dismiss, and an
`AnimatedSize`-based entrance through `MotionScope` (zero-height/no-ticker when motion is
off).

### 3.5 Accessibility strings we do not control

M3E hardcodes some semantic labels as English constants
(`M3EDialogStrings.cancel/confirm/dismiss`, text-field `Clear`/`Show password`).
Where a parameter exists we pass ours:

| Component | Parameter | Ours |
|---|---|---|
| `M3EDialog.show` | `cancelLabel`, `confirmLabel`, `dismissLabel` | `l10n.commonCancel` etc. |
| `M3ETextField` | `clearButtonSemanticsLabel`, `showPasswordSemanticsLabel`, `hidePasswordSemanticsLabel`, `errorIconSemanticsLabel` | new ARB keys |
| `M3ENavigationRail` | `expandTooltip`, `collapseTooltip` | `l10n.navExpand` / `navCollapse` |
| dialogs/sheets | `M3EDialogStrings.dismiss` (no parameter) | cannot override — do not expose a dismissible barrier without also giving it a visible labelled action |

The rule for review: **no screen-reader string may be English-only.** New ARB keys go in
both `app_en.arb` and `app_zh.arb`; `test/l10n/l10n_test.dart` already fails on a missing
zh key and on a byte-identical one that is not listed in `identicalByDesign`.

---

## 4. Motion catalogue — closing the gaps

`PLAN.md` §6.4 is the target; §7 of `PLAN.md` (status table) records what is actually
there. Landed: splash `AmbientLoop`, shell content cross-fade, page transitions
(`SharedAxisTransition` via `appPage`), instance grid stagger, page-level `MotionEntrance`.

Still missing, in the order they should land:

| Gap | Where | Technique | Acceptance |
|---|---|---|---|
| Instance card → detail continuity | `instance_card.dart` → `instance_detail_screen.dart` | `Hero` on the card's icon tile; keep `SharedAxisTransition` for the page | Card icon and detail header icon are the same `Hero` tag; no double-fade |
| Press feedback on the play button | `launch_screen.dart` | `MovieTween` scale 1→0.97→1 + glow (already specified in `PLAN.md` §6.4, never built) | Motion-off renders scale 1 with no ticker |
| Launching state | `launch_screen.dart` | pulsing dot via `AmbientLoop` (not `MirrorAnimationBuilder` — see below) | One ticker while launching, **zero** after stop |
| Download rows appear per-file | `download_screen.dart` | `StaggerItem` with `StaggerConfig.stepFor` | A 200-file install stays inside the 320 ms budget |
| Progress never snaps | `download_screen.dart` | `PlayAnimationBuilder` trailing catch-up to reported progress | Bar reaches 100 % only when the file set is complete |
| Log lines append | `logs_screen.dart` | `AnimatedList` + warning-highlight fade | New line animates in; **no** animation on the initial backfill |
| Setup save success | `setup_screen.dart` | check-mark draw-on | Motion-off shows the check immediately |

Two rules that the migration makes newly relevant:

- **Prefer `AmbientLoop` over `MirrorAnimationBuilder`.** `AmbientLoop` has the
  motion-off short-circuit (`lib/ui/motion/primitives.dart`); `MirrorAnimationBuilder`
  always allocates a ticker. The pulsing launch dot must use the former.
- **`AnimatedSwitcher` with a zero duration still rebuilds**; the primitive wrappers are
  what skip work, not the duration token. Route every new animation through
  `lib/ui/motion/`.

---

## 5. Test migration

11 files import `fluent_ui`, and they import it for *widget types* they find in the tree,
so each needs the same substitution as its screen. The risk is not mechanical
substitution — it is that a test written against `FluentTheme` silently keeps passing
while asserting nothing about M3E.

| Test | Fluent symbols | Note |
|---|---|---|
| `test/app/app_root_test.dart` (218) | `FluentApp`, `FluentTheme`, `FluentThemeData` | assert `M3ETheme.maybeOf` **and** resolved brightness in both modes |
| `test/app/router_test.dart` (241) | `FluentApp`, `NavigationView` | rail selection must still follow the router |
| `test/ui/app_theme_test.dart` (124), `app_theme_golden_test.dart` (56) | `FluentThemeData` | swatch golden is font-free by design — keep that property |
| `test/ui/download_screen_test.dart` (376) | `Button`, `ProgressRing` | progress assertions move to `M3EProgressIndicator` |
| `test/ui/instance_detail_test.dart` (393) | `TextBox`, `ContentDialog` | `M3EDialog.show` is async — `pumpAndSettle` after the tap |
| `test/ui/java_panel_test.dart` (225) | `Button`, `InfoBar` | `AppBanner` |
| `test/ui/launch_and_instances_test.dart` (797) | most of the vocabulary | split if it grows; it is already the largest test |
| `test/ui/setup_screen_test.dart` (213) | `FluentTheme`, sliders | keep the 1400×2600 fixture (see `PLAN-M6-M9.md` §0.2) |
| `test/l10n/app_shell_l10n_test.dart` (90) | `FluentApp` | add the rail tooltip keys |
| `test/dbg_shots_test.dart` (157) | `FluentApp` in `find.byType` | see §6 |

New tests this milestone must add (they are the ones that would have caught the defects
this plan exists to prevent):

1. **Motion-off ⇒ no ticker, end to end.** Pump the whole shell with
   `disableAnimations: true`, assert `transientCallbackCount == 0` after settle, including
   while an indeterminate progress indicator is on screen (currently 3 — §1.5).
2. **Deep-route theme reachability** (§3.3).
3. **zh smoke at M3E level.** Route `/setup` with `locale: zh`, `MaterialApp`'s own
   `Localizations` assert is the test — if the delegate list regresses, this throws.
4. **Icon map completeness.** Every `ShellIcons` constant is a `LucideIcons` glyph and
   every route resolves to one (guards the §1.4 rename table).

---

## 6. Visual verification

The Wayland path is a dead end: `weston-screenshooter` aborts with
`assert 'width > 0'` on the headless composer, so there is no screenshot of the real
window. **Use the widget golden harness instead — it works, and it was verified this
session:**

```
flutter test test/dbg_shots_test.dart --run-skipped --update-goldens
```

writes 7 PNGs (launch, instances, instances-empty, detail, download, setup, logs) at
1440×900 to `test/shots/` in ~3 s — plus one `app root` case that writes no file and
only proves the root pumps. That directory is gitignored (line 58),
so these stay **review artifacts**, not CI gates — which is right: a golden of a
font-dependent screen fails on any other host for reasons unrelated to the change.

Required changes to that harness:

- `find.byType(FluentApp)` → `find.byType(MaterialApp)`.
- Add a second pass with `disableAnimations: true` so the motion-off resting frame is
  reviewable next to the animated one.
- Register the DejaVu fonts for the *Latin* text only; CJK still falls back to a
  notdef box unless a CJK font is loaded. Either add one to the harness or accept
  tofu in shots and never claim they prove the zh layout.

Keep the enforced golden set small and font-free (`test/ui/goldens/theme_*.png`); do not
commit `failures/` debris again (D7).

---

## 7. Milestones

Each ends with `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`,
`flutter test`, both `tool/check_*.dart` gates green, and a fresh `test/shots/` set.

### M10.1 — Dependency swap + gates
`pubspec` per §1.1; `check_imports.dart` updated: `package:fluent_ui/` moves to
`_globallyBanned` (it must not come back) and `package:material_3_expressive/` is added
to `_flutterPrefixes` so `lib/core/` stays engine-free. Colour owners stay in one place by
a source rule rather than an import rule — `M3EColorScheme(` / `M3EThemeData(` may only be
constructed in `lib/ui/theme/`, which is exactly the shape `check_tokens.dart` already
enforces for durations. Delete the `flutter_localizations` restriction once W2 lands.
D7 + D8 resolved, plus **D2** (`ManagedJavaRuntime.majorVersion` reports
`HostArch.x86_64` unconditionally — take the arch from the resolved runtime).
**Acceptance:** `flutter pub get` resolves with `material_ui 1.7.0`; the gate reports the
17 known violations and nothing else; no HTML/PNG debris in `test/ui/`.

### M10.2 — Root, theme, shell, window
W2 files + §3.1 window bootstrap + `AppTheme.text` + `AppBanner`.
**Acceptance:** app builds (`--no-tree-shake-icons` on arm64); every route reachable with
the rail selecting correctly; `M3ETheme.maybeOf` non-null on the deepest route; zh
renders; new-ticker test green.

### M10.3 — Launch + instances
W3 + Hero continuity + press feedback + grid stagger on M3E.
**Acceptance:** the launch and instances shots show M3E chrome; motion-off pass shows the
same layout with no motion; 0 tickers at rest.

### M10.4 — Detail, settings, args + D4
W4 + **D4** (jvm/game args editor) + **D3** (one heap clamp, 65536, exported once).
**Acceptance:** args round-trip into `Instance` and reach `launch_factory`; the clamp is
one constant with a unit test.

### M10.5 — Download, setup, logs
W5 + download motion gaps + **D1** (delete removes the instance directory) + **D5**
(create dialog picks a real version and loader).
**Acceptance:** delete reclaims disk and leaves no orphan `instanceDir`; create no longer
hardcodes `1.20.1`/vanilla.

### M10.6 — Test migration + motion catalogue closeout
W6, all §5 tests, §4 table complete.
**Acceptance:** `flutter test` green with the four new tests; grep proves `fluent_ui`
appears nowhere in `lib/` or `test/`.

### M10.7 — `AGENTS.md` + `PLAN.md` update
Record: the `material_ui` pin and its `RoundedPolygon` reason; that `M3E` is not
reduced-motion aware; the Linux server-side-decoration decision; the working screenshot
command. Retire `PLAN.md` §6.2's two-engine table where it names Fluent.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| `material_ui` floats to 1.8.0 and breaks the build with a `RoundedPolygon` error | Exact pin + a `pubspec` comment naming the collision + `AGENTS.md` note |
| `material_3_expressive 1.1.7` is early software; a component misbehaves | Every wave is leaf-local, so a component can be swapped for a `material_ui` `ThemeData` widget without touching the root. Keep `AppTheme.material()` alive for exactly this |
| Migration stalls mid-way with a half-M3E tree | The root moves first (W2); after that `fluent_ui` is gone from `lib/` and there is no half state to get stuck in. The 11 test files are the long tail and they are all in W6 |
| `M3ENavigationRail`'s expanded/collapsed modes break the shell's fixed-width assumption | Decide the rail's `type` in W2 and keep the shell body `Expanded`; the rail's own controller is optional and not needed |
| Motion regressions hide behind passing tests | The §5 ticker test is the only assertion that meaningfully covers motion; do not accept a "looks fine" review in place of it |
