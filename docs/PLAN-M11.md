# M11 — Material Design styling, informative motion

Supersedes `PLAN-M10.md` §3 (component decisions) and replaces its §1.5 rationale.
Feature scope is unchanged: **functional parity with PCL 2, pre-2.99**.

Two directives drive this milestone:

1. **Keep the animations, change the styles to Material Design.** The motion
   layer (`lib/ui/motion/`, `lib/app/router.dart`) is not rewritten — only the
   `material_3_expressive` (`m3e`) *style/widget* layer is replaced with
   `material_ui` (`m3`), which is already the app's Material implementation.
2. **The motion we have is not informative.** It decorates (fades, staggers) but
   rarely *tells the user something*. This milestone adds state-communicating
   motion — skeleton loading, progress that never snaps, list insert/remove,
   press feedback — using animation packages chosen for that job.

**Explicitly out of scope: an animations on/off switch.** Motion is on by
default. No new gate, toggle, or settings row is introduced. The existing
`AppSettings.uiAnimations` preference (already defaulting to `true`) is left
exactly as it is; see §5.3.

**Position:** M0–M10 landed. Every number below was measured in this tree,
2026-10-21, on the working tree (uncommitted M10 tail included).

---

## 0. Where the code is

| Gate | Result |
|---|---|
| `flutter analyze` | clean |
| `flutter test` | 575 declarations across 37 files (last full run: 571 passing) |
| `dart run tool/check_imports.dart` | `import law OK (65 files checked)` |
| `dart run tool/check_tokens.dart` | `motion tokens OK (65 files checked)` |

### 0.1 The measured style surface

`package:material_3_expressive` appears in **14 files in `lib/`** and **6 in
`test/`**, at **97 `m3e.` call sites**:

| File | Sites | LOC | Dominant symbols |
|---|---:|---:|---|
| `lib/ui/setup/java_panel.dart` | 20 | 457 | `M3EButtonStyle` ×9, `M3EButtonSize` ×6, `M3ETheme` ×4, `M3EDialog` ×1 |
| `lib/ui/instances/instance_detail_screen.dart` | 19 | 832 | `M3EButtonStyle` ×8, `M3EDialog` ×3, `M3ESwitch` ×2, `M3ESlider`, `M3EColorScheme` |
| `lib/ui/download/download_screen.dart` | 15 | 578 | `M3EButtonStyle` ×6, `M3EButtonSize` ×5, `M3ETheme` ×2, `M3ETextField`, `M3ESwitch` |
| `lib/ui/instances/instances_screen.dart` | 9 | 436 | `M3EButtonStyle` ×6, `M3EDialog` ×2, `M3ETextField` |
| `lib/ui/components/app_button.dart` | 5 | 55 | the wrapper itself |
| `lib/ui/setup/setup_screen.dart` | 5 | 389 | `M3ERadioGroup`/`M3ERadio`, `M3ETextField`, `M3ESwitch`, `M3ESlider` |
| `lib/ui/shell/app_shell.dart` | 5 | 205 | `M3ENavigationRail*` |
| `lib/ui/launch/launch_screen.dart` | 4 | 366 | `M3EButtonStyle` ×2, `M3EButtonSize`, `M3ETheme` |
| `lib/ui/logs/logs_screen.dart` | 4 | 201 | `M3EButtonStyle`, `M3EButtonSize`, `M3ETextField`, `M3ESwitch` |
| `lib/ui/components/app_banner.dart` | 3 | 118 | `M3ETheme`, button style/size |
| `lib/ui/instances/instance_card.dart` | 3 | 200 | `M3ETheme`, button style/size |
| `lib/ui/theme/app_theme.dart` | 3 | 81 | `M3EThemeData` ×2, `M3EColorScheme` |
| `lib/ui/instances/args_field.dart` | 1 | 136 | `M3ETextField` |
| `lib/app/app_root.dart` | 1 | 138 | `M3ETheme` (the whole app's style root) |

Sixteen distinct symbols. Variant split of the button enum: **14 `filled`, 7
`outlined`, 14 `text`** styles; **17 `sm`, 1 `lg`** sizes.

### 0.2 The motion surface that must not move

| Piece | Files | LOC | Status |
|---|---|---:|---|
| Motion vocabulary + policy | `lib/ui/motion/tokens.dart`, `motion_scope.dart`, `primitives.dart`, `motion.dart` | 471 | **unchanged** |
| Page transitions | `lib/app/router.dart` (`appPage` → `SharedAxisTransition`) | 118 | **unchanged** |
| Consumers | `StaggerItem`/`StaggerList` (4), `MotionEntrance` (6), `AmbientLoop` (4), `Hero` (3) | — | **unchanged** |

The motion layer imports only `flutter_staggered_animations_plus`,
`simple_animations` and `animations`. It names no style package, so replacing
`m3e` cannot break it — this is why the directive "same animations, MD styles"
is cheap: **the two layers were already independent.**

---

## 1. The four reference repos, and what each is actually for

| Repo | What we take | What we do **not** take |
|---|---|---|
| `The-ring-io/flutter_staggered_animations` | The cascade concept, already re-implemented as `StaggerItem`/`StaggerList` with our own 320 ms budget (`StaggerConfig`) | Its `AnimationLimiter` — it builds a controller and sets `value = 1.0` when suppressed, so "disabled" still costs a frame |
| `felixblaschke/simple_animations` | `LoopAnimationBuilder`-class timelines, wrapped by `AmbientLoop` | Direct use in content code: it always allocates a ticker |
| `material-components/material-components-flutter` | The **styling** reference: which MD3 component plays which role, and the states each owns (elevation, indicator, tonal surface) | Its widget wrappers — `material_ui 1.7.0` already ships the same components, and mixing copies creates the second theme tree the import law exists to prevent |
| `Meloong-Git/PCL` | **Behavioural** parity: which actions exist, in what order, and what feedback each gives (this is the "informative" spec) | Any code, XAML, string or icon — PCL is closed-source; parity is functional only |

Ranking rule for anything new: **behaviour from PCL, styling from
material-components-flutter, motion from the two animation packages, all of it
funnelled through `lib/ui/motion/`.**

---

## 2. Decisions, with the evidence that forced them

### 2.1 `material_ui` is the style layer; delete `material_3_expressive`

Every `m3e` symbol the app uses has a first-party MD3 equivalent in the pinned
`material_ui 1.7.0`, and the replacement compiles today. Verified by building a
throwaway package against `material_ui: 1.7.0` and running `flutter analyze` on a
file exercising all of them jointly (`RadioGroup` + `RadioListTile`,
`FilledButton`/`OutlinedButton`/`TextButton`, `NavigationRail(extended: true)`,
`AlertDialog`, `Slider(…, onChangeEnd:)`, `Switch`, `TextField` +
`InputDecoration`, `SegmentedButton`): **No issues found.**

| `m3e` symbol | Sites | Replacement | Note |
|---|---:|---|---|
| `M3EButtonStyle.filled/outlined/text` (36) | 36 | `m3.FilledButton` / `OutlinedButton` / `TextButton` | collapse into one `AppButton` switch (§2.2) |
| `M3EButtonSize.sm/lg` (19) | 19 | `AppButtonSize` enum → `ButtonStyle.minimumSize`/`padding` | `sm` 40 px (unchanged); `lg` 40 px→MD3 large, §2.2.1 |
| `M3EButton` | 1 | internal to `AppButton` | the wrapper becomes the only place a button is built |
| `M3ETextField` (6) | 6 | `AppTextField` → `m3.TextField` + `m3.InputDecoration` | `placeholder` → `hintText` |
| `M3ESwitch` (5) | 5 | `AppSwitch` → `m3.Switch` + `Semantics` | `m3.Switch` has no `semanticLabel`, §2.7 |
| `M3ESlider` (2) | 2 | `AppSlider` → `m3.Slider` + `Semantics` | **removes a workaround**, §2.4 |
| `M3EDialog` (6) | 6 | `AppDialog` → `m3.AlertDialog` | title doubles as `semanticLabel` |
| `M3ERadioGroup` + `M3ERadio` (2) | 2 | `AppRadioGroup` → `m3.RadioGroup` + `m3.Radio` rows | **not** `RadioListTile`, §2.7 |
| `M3ETheme` (11) | 11 | delete; read `m3.Theme.of(context).colorScheme` | |
| `M3EThemeData` (2) + `M3EColorScheme` (2) | 4 | `m3.ThemeData` + `m3.ColorScheme` | `AppTheme.expressive` disappears; `AppTheme.material` is the only theme |
| `M3ENavigationRail*` (5) | 5 | `m3.NavigationRail(extended: true, …)` + `NavigationRailDestination` | §2.3 |

Consequence: **one colour system instead of two.** Today `AppTheme.material` and
`AppTheme.expressive` are both seeded from `AppTheme.accentSeed`, and
`test/ui/app_theme_test.dart` asserts they agree. After this milestone there is
nothing to agree with — the assertion is deleted, not weakened.

`pubspec.yaml` drops `material_3_expressive`, and the `material_ui` pin
comment (which exists *because* of a `material_new_shapes` /
`RoundedPolygon` collision caused by `material_3_expressive`) is rewritten:
the pin can be relaxed to `^1.8.0` only after that comment is re-verified.

### 2.2 One `AppButton`, so 36 call sites survive a second style change

`AppButton` currently forwards to `m3e.M3EButton`, including a documented
workaround: `M3EButton` only builds `label` when an `icon` is present, so a
text-only button renders empty and the content has to be passed as `child`. That
bug disappears with `m3`. The wrapper keeps its public shape — `label`,
`onPressed`, `icon`, `style`, `size`, `semanticLabel`, `tooltip` — and its
`style`/`size` enums move from `m3e.*` to `AppButtonStyle`/`AppButtonSize`
declared beside it, so the 36 `style:` and 19 `size:` call sites change one
token each and no screen ever names a button class again.

Height must be explicit rather than inherited, because the default and the
measurement differ: MD3's default body is 40 px but Material pads the tap target
to 48, so an unstated height is ambiguous. Declared values are from
`m3e_button_theme.dart:_measurementsTable`; rendered values are measured:

| `m3e` size | Declared | **Rendered** | hPadding | Sites | MD3 mapping |
|---|---:|---:|---:|---:|---|
| `sm` | 40 | **48** | 16 | 17 | `minimumSize: (64, 40)` → also renders 48 (tap target) — unchanged |
| `lg` | 96 | **96** | 48 | 1 | MD3 large, 56 px (§2.2.1) |

The declared/rendered split matters: `sm` declares a 40 px body but Material pads
the *tap target* to 48, and that is what a widget test measures. Both old and new
code render **48**, so the dense rows do not move — verified by measuring the
expressive button directly (`height=48.0 width=82.0`) before writing the
replacement, and pinned by `test/ui/app_button_test.dart`.

**2.2.1 The Play button is the one deliberate visual change.** It is the only
`lg` site (`launch_screen.dart:187`) and today it is a 96 px-tall pill. MD3 has no
96 px button role — its largest is a 56 px "extra-large" shape, and buttons are
40 px by default. Options were: reproduce 96 px with `minimumSize`, or adopt the
MD3 role. **Take the MD3 role (56 px, `Durations`/`MotionCurves` untouched)** and
let the *motion* carry the emphasis instead (§3.4 press feedback + glow), because
the directive is explicitly "switch the styles to MD design". A 96 px button in
an otherwise MD-styled app would be the one element that visibly is not MD. This
is recorded as an intentional deviation from pixel parity, not an oversight.

### 2.3 The rail stays permanently extended, as a *declared* constraint

`AppShell` pins `M3ENavigationRailType.alwaysExpand` for a documented layout
reason: a collapsing rail animates its own width, which would make the body's
constraints depend on a control inside the rail. `m3.NavigationRail` expresses
the same thing with `extended: true`, which asserts
`labelType == null || labelType == NavigationRailLabelType.none` and gives a
fixed `minExtendedWidth`. The rail keeps `expandedWidth: 216` via that property.

Two l10n keys become unused (`navExpand`, `navCollapse` — they fed
`expandTooltip`/`collapseTooltip`). They are **kept in the ARB files** in this
milestone: removing keys renumbers the generated files for no user-visible gain,
and `test/l10n/l10n_test.dart` does not assert on unused keys.

### 2.4 `m3.Slider` deletes a workaround, and one test

`lib/ui/setup/setup_screen.dart` currently works around an upstream `m3e` bug:
`M3ESlider.onChangeEnd` reports the *pre-drag prop*, not the released value
(`m3e_slider_interaction.dart:58,111`), so the screen reads the value from its
own `_dragging` field. `material_ui`'s slider calls
`widget.onChangeEnd?.call(_lerp(value))` (`slider.dart:768`) — the real value.
The workaround and its comment are removed, and `_dragging` goes back to being a
pure display flag. This is a **behaviour fix hidden inside a styling change** and
gets its own test.

### 2.5 New animation packages: three accepted, four rejected — all measured

Requirement for any new package: it must not pull
`package:flutter/material.dart` (the banned second tree), and it must not be the
only thing standing between us and "motion off costs nothing".

Resolved against `material_ui: 1.7.0` in a scratch package with
`flutter pub get` (all succeeded):

| Package | Version | Banned `package:flutter/material.dart` files | Honours reduced motion? | Verdict |
|---|---|---|---|---|
| `skeletonizer` | 3.0.0 | **0** | yes — `enabled: false` never creates the controller (`_startAnimationIfNeeded` runs only when enabled) | **accept** |
| `flutter_animate` | 4.5.2 | **0** | **no** — zero references to `disableAnimations` | **accept, wrapped** (§2.6) |
| `shimmer` | 4.0.0 | 0 (imports `material_ui` directly) | no | skip — `skeletonizer` already renders a shimmer effect |
| `confetti` | 0.8.0 | 3 | no | reject — banned import; celebration is not a parity feature |
| `flutter_spinkit` | 5.2.2 | 3 | no | reject — spinner variety is styling, and `material_ui` has the indicators |
| `number_slide_animation` | 0.2.1 | 2 | no | reject — see §3.4, we animate the digit ourselves |
| `circular_reveal_animation`, `animated_toggle_switch`, `auto_animated` | — | 2 / 1 / 3 | no | reject — each duplicates a component `material_ui` already ships |

Note on the "banned import" column: `tool/check_imports.dart` only scans `lib/`,
so a dependency's own `material.dart` import is invisible to the gate. It still
matters at runtime — it is the exact second-tree hazard the gate documents — so
the column is measured by hand and treated as a hard requirement.
(`confetti` and `flutter_spinkit` *do* mount under a `material_ui` app — verified
in a widget test — precisely because neither calls `Theme.of`. That is luck, not
a property; both stay out.)

### 2.6 `flutter_animate` goes behind a wrapper, like every other engine

`flutter_animate` creates its controller unconditionally
(`animate.dart:331: controller = AnimationController(vsync: this)`) and never
reads `MediaQuery.disableAnimations`. Using it directly in a screen would break
the standing rule that motion-off creates no ticker — the same defect `AmbientLoop`
exists to avoid for `simple_animations`.

So content code never imports it. `lib/ui/motion/primitives.dart` gains one
primitive, `Emphasis`, which:

* reads `MotionScope.of(context)`;
* when motion is off, returns `child` with no adapter and no controller;
* when motion is on, applies the effect chain the caller supplies.

This keeps `tool/check_tokens.dart` meaningful (durations still come from
`Durations`) and keeps "which package animates what" a one-file question.

### 2.7 Three `m3e` conveniences `material_ui` does not have

Discovery during W4/W5, not predictable from the docs. Each is a small wrapper
rather than a spread of ad-hoc fixes at the six call sites:

| `m3e` had | `material_ui` 1.7.0 | Consequence |
|---|---|---|
| `M3ESwitch(semanticLabel:)` | no `semanticLabel`; announces only "on"/"off" | `AppSwitch` wraps a `MergeSemantics` + `Semantics(label:, toggled:)` |
| `M3ESlider(semanticLabel:)` | no `semanticLabel`; announces only the number | `AppSlider` wraps a `Semantics(label:)` around the slider |
| `M3ERadioGroup` + `M3ERadio(label:)` | `RadioGroup` exists in `flutter/widgets.dart`; `RadioListTile` asserts under a `DecoratedBox` with a background | `AppRadioGroup` builds `m3.Radio` inside `m3.InkWell` rows; the setup panel is such a `DecoratedBox`, so the tile is unusable there |

`Radio.groupValue`/`Radio.onChanged` are **deprecated** after 3.32; group state
belongs on the `RadioGroup` ancestor. `AppRadioGroup` therefore takes
`value`/`onChanged` and forwards them, which is also the shape the setup screen
already had.

### 2.8 Status colours are fixed, not seeded

`ColorScheme` has `error` but no success/warning/info. Those three carry
meaning - a version row is green because it is installed, not because green
suits the accent - so `AppTheme.status(context)` returns fixed hues that resist
the seed, with `danger` mapped to `scheme.error` so it still tracks the theme.
This replaces the four roles `M3EColorScheme` used to supply.


---

## 3. Making motion informative

The complaint "the animation is not that informative" is precise, and
`PLAN-M10.md` §4 already enumerated the gaps without closing them. This
milestone closes them. Every row is a *state the user must be able to read*, not
a flourish.

### 3.1 Skeleton loading, instead of a spinner where content will appear

| Where | Today | After |
|---|---|---|
| `download_screen.dart:93` | bare `CircularProgressIndicator` | `Skeletonizer` rows shaped like the file rows they will become |
| `instances_screen.dart:43` | bare `CircularProgressIndicator` | skeleton grid, same `mainAxisExtent: 148` as the real cards |
| `launch_screen.dart:192` | spinner inside the requirement check | unchanged — it is a 1-line check, not a content region |

The rule: **skeleton where the shape is known, spinner where it is not.** A
skeleton states "cards are coming, this many, this size"; a spinner states
nothing.

### 3.2 Progress that never snaps

`download_screen.dart:386` binds `LinearProgressIndicator` straight to
`state.fraction`. Bytes arrive in bursts, so the bar jumps. Wrap it in a
`PlayAnimationBuilder` that trails the reported value over `Durations.fast`, and
only allow 1.0 when the file set is complete. This is the single most
*informative* change in the milestone: it converts a jumpy number into a
smoothly-advancing answer to "how much longer".

### 3.3 Lists that show their own changes

* `logs_screen.dart`: `AnimatedList` + a warning-highlight fade for appended
  lines. **No animation on the initial backfill** — that is a wall of text, and
  animating it delays the user's first useful frame.
* `download_screen.dart` rows: already `StaggerList`; add removal on cancel so a
  cancelled file *leaves* rather than vanishing.

### 3.4 Numbers and press feedback

* Launch memory / download percentage: animate the digits via
  `TweenAnimationBuilder<int>` + `IntTween` inside `Emphasis`, not a package —
  `number_slide_animation` would add a banned import for ~15 lines of code.
* Play button press: `MovieTween` scale `1 → 0.97 → 1` plus a glow, specified in
  `PLAN.md` §6.4 and never built. Motion-off renders scale 1, zero tickers.
* Launching state: pulsing dot via `AmbientLoop` (**not**
  `MirrorAnimationBuilder`, which always allocates a ticker).

### 3.5 Card → detail continuity

`Hero` is already used on the card and detail icon (3 sites). Verify the tag
matches on both sides and that `SharedAxisTransition` does not double-fade the
hero; fix the tag if it does.

---

## 4. Work order

Each wave ends green: `flutter analyze`, both `tool/` gates, full `flutter test`.
The order is chosen so the tree compiles after every wave — the theme root
changes before any widget does, and the dependency is removed last.

| Wave | Content | Files | Gate at end |
|---|---|---|---|
| **W1** | Theme: delete `AppTheme.expressive`, keep `AppTheme.material` as the only theme; drop the `m3e.M3ETheme` builder from `AppRoot` | `app_theme.dart`, `app_root.dart`, `app_theme_test.dart` | analyze + test |
| **W2** | `AppButton`: `AppButtonStyle`/`AppButtonSize` enums, `m3.Filled/Outlined/TextButton`, explicit 40 px / MD3-large (see §2.2.1) | `app_button.dart`, `app_banner.dart`, `instance_card.dart`, `launch_screen.dart` | analyze + test |
| **W3** | Shell: `m3.NavigationRail(extended: true)` | `app_shell.dart` + `app_shell_l10n_test.dart` | analyze + test |
| **W4** | Inputs: `AppTextField`, `AppSwitch`, `AppSlider` (drops the `onChangeEnd` workaround), `AppRadioGroup` | `app_text_field.dart`, `app_switch.dart`, `app_slider.dart`, `app_radio_group.dart` + 5 screens | analyze + test |
| **W5** | Dialogs: `AppDialog` over `m3.AlertDialog`; `AppTheme.status` replaces the four `m3e`-only semantic colours | `app_dialog.dart`, `instances_screen.dart`, `instance_detail_screen.dart`, `java_panel.dart`, `app_theme.dart` | analyze + test |
| **W6** | Motion: `Emphasis` primitive, skeletons, trailing progress, `AnimatedList` logs, press feedback | `primitives.dart`, 3 screens | analyze + test + tokens |
| **W7** | Remove the dependency, update the pin comment, `AGENTS.md` + this doc | `pubspec.yaml`, docs | all four gates |

**Status (2026-10-22):** W1–W7 are done and green — `flutter analyze` clean, both `tool/` gates
pass, full `flutter test` green. `grep -rn material_3_expressive lib/ test/ pubspec.yaml` returns only
this document's own history.

W6 was landed as written, with three decisions worth recording:

- **`Emphasis` listens, it does not gesture.** A `GestureDetector` around a button competes for the tap;
  `Listener` sees the pointer without claiming it, so the press feedback cannot break the press.
- **The progress clamp lives in one helper** (`_displayFraction` in `download_screen.dart`) and both the
  bar and the percentage go through it. A bar that is honest and a number that says 100% would be worse
  than either alone.
- **The log console animates appends only.** A structured diff (`identical` element-wise) decides between
  "insert these at the end" and "the visible set was replaced, rebuild without animation"; the initial
  backfill and every filter/search change take the second path.
- `flutter_animate` earns its place with exactly one effect (`AppendHighlight`'s tint); `skeletonizer`
  with the skeletons. Both imports are fenced into `lib/ui/motion/primitives.dart` by
  `tool/check_imports.dart`.

---

## 5. Tests

### 5.1 The harness loses a layer

`test/support/harness.dart` currently installs **both** `m3.Theme` and
`m3e.M3ETheme`, with a comment explaining that a harness installing only the
first would pass while `M3E*` widgets fell back to a default scheme. After W1
there is one theme, so the `builder:` disappears and that comment goes with it.
`test/ui/app_theme_test.dart`'s "the expressive scheme reports the requested
brightness" and "one seed reaches both colour systems" groups are deleted —
they assert a duality that no longer exists. The brightness and type-role tests
stay.

### 5.2 Type-driven finds must be replaced, not just renamed

Four finders looked up `m3e` types and would have passed vacuously otherwise:

| Test | Finds | Replace with |
|---|---|---|
| `download_screen_test.dart` | `find.byType(m3e.M3ESwitch)` | `find.byType(m3.Switch)` |
| `setup_screen_test.dart` | `M3ETextField` directly | `m3.TextField` via `find.descendant` (the key is on `AppTextField`, the finder must reach the `m3` widget) |
| `setup_screen_test.dart` | `M3ESwitch`, default-value state | `m3.Switch`; plus the slider release test in §2.4 |
| `launch_and_instances_test.dart` | `M3E*` buttons | `AppButton` by key, not by class |

New tests this milestone needs:

* **slider release value** — drag, release, assert the *released* value persists
  (the exact class of bug the old workaround existed for);
* **motion-off renders skeletons statically** — `Motion.none` + the new skeleton
  path, assert `transientCallbackCount == 0`;
* **`Emphasis` allocates no ticker when motion is off** — same assertion, mirroring
  `test/ui/motion_primitives_test.dart:83`;
* **progress never reports 1.0 early** — feed incomplete state, assert the
  displayed value stays below 1.0.

Landed in W4/W5 as `test/ui/app_controls_test.dart` (10 tests): a labelled
`AppSwitch` announces its label *and* stays label-free when none is given; a
`m3.Switch` with a null `onChanged` stays disabled; `AppSlider` exposes the
control name the SDK slider drops, and forwards `divisions`/`label`; an
`AppRadioGroup` reports the tapped option; it builds **no** `RadioListTile`, so
it can live under the setup panel's `DecoratedBox` (§2.7); `AppDialog`'s visible
title is its semantic label; and `AppTheme.status` keeps success green under a
yellow seed while `danger` tracks `scheme.error`.

### 5.3 No animation switch

The settings screen keeps exactly its current rows. `AppSettings.uiAnimations`
stays, defaults to `true`, and `AppRoot` keeps resolving it into `MotionScope`
(which ORs in the OS accessibility setting and can therefore only ever turn
motion *off*). `test/ui/setup_screen_test.dart`'s "the animation switch flips and
persists" test stays as-is.

Nothing in this milestone adds a control for motion, and nothing reads the new
packages' own enable flags from the UI — the only switch is the policy layer.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| A test finds an `m3e` type and silently stops testing anything | §5.2 — replace with `m3`, never delete the find |
| `m3.AlertDialog` buttons inherit MD3 typography and drift from `AppTheme.label` | `AppButton` always passes an explicit `textStyle`; visual diff via `test/dbg_shots_test.dart` |
| Rail width change reflows every screen | `minExtendedWidth: 216` is pinned to today's `expandedWidth`, asserted in a widget test |
| `Skeletonizer` wraps content in a paint layer that hides semantics | Wrap the *placeholder*, not the real content; assert the real tree returns when loading ends |
| `flutter_animate` used directly in a screen, bypassing the policy | Import-law style check: `flutter_animate` may appear only in `lib/ui/motion/` (extend `tool/check_imports.dart`'s restricted table) |
| Removing `material_3_expressive` re-resolves `material_ui` past the pin | **Resolved:** the pin existed only to dodge `material_new_shapes`, which `m3e` pulled in. With both gone the constraint is `^1.7.0` and `pub get` still resolves 1.7.0 — checked in `pubspec.lock` |
| The 2 px overflow fixed at `mainAxisExtent: 148` is re-broken by new button heights | `sm` stays pinned at 40 px (identical to today) and the card grid test stays |

---

## 7. Definition of done

* `grep -r material_3_expressive lib/ test/ pubspec.yaml` → no matches.
* One colour system: `AppTheme.material` only.
* Motion layer diff is additive (`Emphasis` + the new call sites); `tokens.dart`,
  `motion_scope.dart` and `router.dart` are untouched.
* Motion-off creates no ticker on every new animated surface.
* All four gates green, test count ≥ today's 575 declarations (now **587**:
  577 + the 10 in `app_controls_test.dart`).
* `AGENTS.md` records: `material_ui` is the only style package; `flutter_animate`
  is confined to the motion layer; skeletons are the loading idiom.

---

## 8. Shell and page frame (post-W7, reported from a screenshot)

The milestone's waves all passed their gates while the app *looked* broken, because no test asserted
what the page sat inside. Two defects, one cause:

- `AppShell` returned a bare `Column` with no `Scaffold`, so the page had **no `Material` ancestor**.
  Every `InkWell` in a settings row asserted "No Material widget found", and the radio labels - the
  only `Text` in the app without an explicit style - inherited `MaterialApp`'s error style: 48 px,
  red, yellow double underline.
- Each screen carried its own outer padding and title, so the content was pinned to the rail on one
  page and indented 16 px on another, and the launch screen showed a disabled Play button above an
  empty console that stretched to the window.

Fixed by giving the shell the `Scaffold` it always needed (`Material`, themed background, a divider
between rail and content) and by introducing `PageBody`/`PageTitle` so the six pages share one frame.
The rail is now fixed-width with each label under its icon (`NavigationRailLabelType.all`), which also
gives 128 px back to every page. The launch screen's no-instance case is an empty state with a way
forward instead of a dead button, and an idle console is as tall as its own message.

**Verification**: `test/ui/shell_material_test.dart` mounts every route and fails if any `Text`
resolves the 48 px error style; `test/dbg_shots_test.dart` renders all six pages (and two zh shots) so
the layout can be looked at, not just asserted. Screens 1440x900.

---

## 9. Visual language pass (from the follow-up screenshots)

Four decisions that came out of reviewing the rendered pages, in the order they matter:

**Elevation is tone, not shadow.** MD3 renders a raised surface as a lighter or tinted container from
the same neutral ramp; stacking surfaces never produces a drop shadow. `AppTheme.material` therefore
zeroes the dialog and popup-menu elevations and gives both an explicit container colour, and the one
custom shadow in the tree (the pressed Play button's glow, in `Emphasis`) is gone - the press scale is
the signal. A `BoxShadow` anywhere in `lib/ui/` is now a review defect.

**The accent is a setting.** `AppSettings.accent` (a closed enum: blue/teal/green/orange/red/purple)
seeds `ColorScheme.fromSeed` for both brightnesses, and the settings page shows the palette as a
swatch row (`AppAccentPicker`). Status colours stay fixed so "installed" does not become a warning
because someone chose an orange accent.

**Motion has no switch.** Animation is part of the design, so the `/setup` toggle, the
`AppSettings.uiAnimations` field and its four ARB strings are gone. `MotionScope` is always
`Motion.full`; only the OS accessibility flag can remove motion, and `MotionScope.of` still ORs it in.

**The launch page follows PCL, and the rail loses the Instances tab.** A launcher's first question is
*which version*, so the launch page's top control is a version picker listing every instance, with
version settings beside Play and the instance-management screen at the bottom of the picker's menu.
Keeping a separate Instances tab meant two tabs choosing the same thing. `/instances` remains a route
for management, and version settings is still `/instances/<id>`.

**Verification**: 598 tests green (`test/ui/shell_material_test.dart` for the Material ancestor,
`test/ui/motion_informative_test.dart` for the motion guarantees, `test/data/settings_test.dart` for
the accent round-trip), plus `test/shots/setup-zh.png` and `launch.png` re-rendered and read by eye.
