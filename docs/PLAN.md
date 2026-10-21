# oh my mc — Flutter Minecraft Launcher: Implementation Plan

**Status:** M0 + M0.5 complete (toolchain, scaffold, CI matrix, arch verifier)
**Repo state:** `master`, M0 baseline committed
**Targets:** Windows x64 · Linux x64 · macOS arm64 (§3.5)
**Date:** 2026-10-21

---

## 1. What we're building

A desktop Minecraft launcher written in Dart/Flutter with a fluent, motion-first UI:

- **Fluent Animations** — staggered list/grid entrances, choreographed multi-property transitions, looping ambient motion, shared-element navigation — no dead frames, respects reduced-motion.
- **Material 3 design language** — plus Windows-native chrome (Mica-like translucency, custom title bar) via `fluent_ui`.
- **PCL-class functionality** — the launcher feature set of Plain Craft Launcher: version install (vanilla + Forge/NeoForge/Fabric/Quilt/OptiFine), instance management, mod management, Java detection, download mirroring, offline + Microsoft login, crash analysis, log console.

### Non-goals (v1)

- Multiplayer/social features, skin editing, modpack publishing.
- The EasyTier "Link" tunnel (LAN discovery only in v1 — see §11).
- Copying PCL code or assets — see licensing note in §3.4.

---

## 2. Reference audit (what each link actually gives us)

I checked each repository at the API/metadata level, not just reading the README, because two of the four links do **not** mean what they appear to mean.

### 2.1 `The-ring-io/flutter_staggered_animations` — ❌ cannot be used as-is

| Fact | Value |
|---|---|
| Latest version | 1.1.1 (published 2022-08-23) |
| SDK constraint | `>=2.17.0 <3.0.0` |
| Repo state | 1.7k ★, last push 2023-03-22 |
| Verdict | **Does not resolve under Dart 3.** `<3.0.0` upper bound is a hard pub failure. |

**Decision:** use the maintained Dart-3 fork **`flutter_staggered_animations_plus` 1.0.4** (`sdk >=3.0.0 <4.0.0`, `flutter >=3.10.0`, published 2026-10-16). Public API verified against the installed source: `AnimationLimiter`, `AnimationConfiguration.synchronized/staggeredList/staggeredGrid/toStaggeredList`, `SlideAnimation`, `FadeInAnimation`, `ScaleAnimation`, `FlipAnimation`.

> **Correction (probed 2026-10-21):** there is **no `SlideAnimationConfiguration`** and **no `staggeredColumn`** — an earlier draft of this section listed both. Use `AnimationConfiguration.toStaggeredList` for columns. Also note the fork has **no total stagger cap**: `delay` defaults to `duration ~/ 6` per item, so long lists crawl unless we pass an explicit delay. See `docs/PLAN-M1-M4.md` §0.2–0.3.

If the fork ever regresses, the fallback is a ~200-line in-repo vendored copy (library is MIT, single-file `AnimationLimiter` + 4 animation widgets) — we keep the import behind `lib/ui/motion/stagger.dart` so a swap is a one-file change.

### 2.2 `felixblaschke/simple_animations` — ✅ use it

| Fact | Value |
|---|---|
| Latest version | 5.3.0 (2026-05-23) |
| Constraints | `sdk ^3.12.0`, `flutter >=3.44.0` |
| Modules | `animation_builder` (`CustomAnimationBuilder`, `PlayAnimationBuilder`, `LoopAnimationBuilder`, `MirrorAnimationBuilder`), `movie_tween`, `animation_mixin`, `animation_controller_extension`, `animation_developer_tools` |

This is our **non-staggered** motion engine: `MovieTween` for multi-property choreography, `LoopAnimationBuilder` for ambient/background motion, `PlayAnimationBuilder` for progress/reveal, `MirrorAnimationBuilder` for pulse states, and `animation_developer_tools` behind a debug flag. Flutter ≥3.44 requirement is fine (we pin 3.47.7).

### 2.3 `material-components/material-components-flutter` — ⚠️ docs only, not a package

The repo contains **no Dart source** — only `docs/components/*.md` (backdrop, banners, bottom sheets, cards, chips, data tables, dialogs, FAB, nav drawer/rail, progress indicators, sliders, snackbars, tabs, text fields, tooltips, …), a docsite, and a README redirecting to `package:flutter/material.dart`. It is a **design/spec reference**, not a dependency.

**Decision:** treat it as the **component inventory + usage-guideline reference** for the Material 3 layer. Concretely: `ThemeData(useMaterial3: true)` with an explicit `ColorScheme.fromSeed` + typography scale, and each component we build is checked against the matching `docs/components/*.md` guidance (e.g. cards → elevation/state-layer rules, progress → linear vs circular usage, tabs → fixed vs scrollable). Do **not** add it as a pub dependency (nothing to resolve).

### 2.4 `Meloong-Git/PCL` — ⚠️ behavior reference only (license restricts reuse)

| Fact | Value |
|---|---|
| Stars / language | 8.4k ★ / VB.NET (WPF + a custom animation module `ModAnimation.vb`) |
| Layout | `Plain Craft Launcher 2/{Modules,Pages,Controls,Forms}`, `Modules/{Base,Minecraft,Resource,ThirdParty}` |
| License | 《PCL 分发有限许可》 + "reasonable use guidelines" — **not** an OSI license; distribution and code reuse are restricted |

**Decision:** mine it for **feature semantics and module boundaries only** (public API names + behavior), then reimplement in Dart. We do **not** copy code, XAML, string tables, or art. The module surface I extracted that defines our service boundaries:

- `ModLaunch.vb` → `McLaunchStart`, `McLoginInput`, `McLoginMojangUuid`, `McLoginName`, `McLoginLegacyUuid`, `McLoginAble`, `McLaunchLog`
- `ModMinecraft.vb` → `Load`, `Check`, `RefreshInfo`, `McLibListGetWithJson`, `McLibNetFilesFromTokens`, `McAssetsGetIndex`, `McJsonRuleCheck`, `McFolderLauncherProfilesJsonCreate`
- `ModDownload.vb` → `DlClientListGet`, `DlClientJarGet`, `DlClientAssetIndexGet`, `DlSourceOrder`, `DlSourceAssetsGet`, `DlSourceLibraryGet`, `DlModRequest`, `DlVersionListOrder`, `DlForgeVersion*`, `DlNeoForgeListBmclapiMain`
- `ModJava.vb` → `JavaInit`, `UpdateJavaLists`, `ManuallySearchJava`, `SelectOrDownloadJava`, `GetJavaRequirement`
- `ModModpack.vb` → `ModpackInstall`; `ModCrash.vb` → `Analyze`/`Collect`/`Import`/`Prepare`; `ModWatcher.vb` → `Kill`
- `Pages/*` → screen inventory: `PageLaunch`, `PageDownload{Install,Modify,Resource}`, `PageInstance{Overall,Setup,Mod,Export}`, `PageSetup{Launch,Link,System,UI}`, `PageSpeed*`, `PageOther`

`ModAnimation.vb` (aa* helpers: `AaOpacity`, `AaScale`, `AaTranslateX/Y`, `AaScaleTransform`, `AaRotateTransform`, `AaTextAppear`, `AniStart/AniStop`, timer-driven) is worth reading as a **technique** reference: it is exactly the imperative-animation style that `simple_animations` replaces declaratively for us.

### 2.5 External APIs verified reachable from this sandbox

| Endpoint | Result |
|---|---|
| `piston-meta.mojang.com/mc/game/version_manifest_v2.json` | 200 — latest release **26.3**, latest snapshot 26.4-snapshot-5, 920 versions |
| `launchermeta.mojang.com/mc/game/version_manifest_v2.json` | 200 |
| `bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json` | 302 (redirect; usable as mirror base) |
| `meta.fabricmc.net/v2/versions/loader` | 200 |
| `api.modrinth.com/v2/search` | 200 |
| `api.minecraftservices.com/minecraft/profile` | 401 without token (expected) |

Version-JSON shapes confirmed (this drives §5.4):
- Modern (26.3, 1.20.1): `arguments.jvm`/`arguments.game` with `{rules, value}` objects, `javaVersion.majorVersion` 25 / 17, **no** `natives` classifiers (LWJGL3 natives are ordinary artifacts).
- Legacy (1.12.2, 1.8.9): `minecraftArguments` string, `javaVersion` 8, 5 libraries with `natives` + `downloads.classifiers` (`natives-windows`/`-linux`/`-osx`), asset index ids `1.12`/`1.8` → legacy virtual assets.

---

## 3. Technical decisions

### 3.1 Runtime & SDK

| Item | Choice | Reason |
|---|---|---|
| Flutter | **3.47.7 stable** (Dart 3.13.5) | latest stable; satisfies `simple_animations` (≥3.44) |
| Null safety / lints | `flutter_lints ^6.0.0`, `analysis_options.yaml` with `strict-casts`, `strict-raw-types` | catches launcher-critical type bugs early |
| Platforms | 3 release targets: `windows` x64, `linux` x64, `macos` arm64 | launcher needs filesystem + process spawning; arm64 limited to macOS — see §3.5 |

### 3.2 Package set (versions verified on pub.dev today)

```yaml
dependencies:
  flutter: {sdk: flutter}
  flutter_localizations: {sdk: flutter}     # zh_Hans + en_US at minimum (PCL is Chinese-first)
  flutter_staggered_animations_plus: ^1.0.4 # 2.1 — stagger/motion building blocks
  simple_animations: ^5.3.0                 # 2.2 — MovieTween, loop/mirror/play builders
  animations: ^3.0.0                        # Material motion (shared axis, container transform)
  fluent_ui: ^4.17.0                        # Windows-native chrome + Fluent controls
  window_manager: ^0.5.2                    # window size/min-size/title-bar
  flutter_acrylic: ^1.1.4                   # Mica/acrylic backdrop (win10/11), no-op elsewhere
  go_router: ^18.1.1                        # declarative routing + deep links
  flutter_riverpod: ^3.4.3                  # state + DI (no BuildContext coupling in services)
  freezed_annotation: ^3.1.0 / json_annotation: ^4.12.0
  dio: ^5.11.1                              # HTTP with progress, cancel tokens, retry
  crypto: ^3.0.7                            # sha1/sha256 verification
  archive: ^4.5.2                           # zip for modpack import/export
  path: ^1.9.0 / path_provider: ^2.1.6
  file_picker: ^13.1.0
  shared_preferences: ^2.5.6                # light settings; instances live on disk as JSON
  flutter_secure_storage: ^11.2.0           # MS refresh/access tokens
  url_launcher: ^6.3.3
  system_info2: ^4.1.0                      # RAM/CPU for JVM arg defaults
  process_run: ^1.4.1                       # process spawn + stdout/stderr streams
  oauth2: ^2.0.5                            # PKCE for MS device-code/authorization flow
  lucide_icons: ^0.257.0                    # crisp UI icon set
dev_dependencies:
  flutter_test, build_runner: ^2.16.2, freezed: ^4.0.3,
  json_serializable, riverpod_generator: ^4.0.7, flutter_lints: ^6.0.0,
  flutter_launcher_icons: ^0.14.4, msix: ^3.18.0
```

**Resolved and verified** — `flutter pub get` succeeded with 149 packages on Flutter 3.47.7 / Dart 3.13.5.

> **Critical (probed 2026-10-21): Flutter 3.47 split Material out of the SDK.** `fluent_ui 4.17.0`,
> `animations 3.0.0` and `go_router 18.1.1` all depend on the standalone **`material_ui`** package,
> while `package:flutter/material.dart` still ships as a parallel copy. The two are **different type
> universes** — `ThemeData`, `Theme`, `MaterialLocalizations` are distinct classes with the same names,
> and mixing them silently gives two independent theme/localization trees. **Import law: content code
> imports `package:material_ui/material_ui.dart`; nothing imports `package:flutter/material.dart`.**
> Add `material_ui` as a direct dependency. Details: `docs/PLAN-M1-M4.md` §0.1.

Notes / rejected candidates:
- `flutter_staggered_animations` **rejected** (Dart 2 only, §2.1).
- `flutter_animate` (4.5.2, stale 2024) not needed — `simple_animations` + staggered fork cover it; fewer animation engines = fewer races on one `AnimationController`.
- No pub package exists for Minecraft launching (`minecraft_launcher_lib`, `mcauth`, `minecraft_ping` → not found; `craft_launcher_core`/`dart_minecraft` are immature). **We implement the launch pipeline ourselves** — that's the core of the project anyway.
- **`build_runner` is pinned to `^2.16.2`, not `^2.17.x`.** Real solver conflict, found by running it: `build_runner >=2.17.1` needs `build >=5.0.0 <5.1.0`, while `riverpod_generator >=3.0.0` (incl. 4.0.7) needs `build <5.0.0`. Pub's own suggestion is the 2.16.2 pin, which resolves cleanly with `freezed 4.0.3`.
- `google_fonts` dropped: it fetches fonts at runtime by default, which is wrong for an offline-capable launcher. We bundle fonts as assets instead (also avoids a network dependency on first paint).

### 3.3 Architecture: layered, testable core

```
lib/
  main.dart                     # bootstrap: window_manager + acrylic, ProviderScope, router
  app/                          # shell, theme, router, localization, motion scope
    theme/{tokens.dart, app_theme.dart, fluent_bridge.dart}
    motion/{motion.dart, stagger.dart, reduced_motion.dart, movie_presets.dart}
    router.dart
  core/                         # PURE DART. no Flutter imports -> 100% unit-testable
    mc/
      version_manifest.dart     # manifest fetch + cache + mirror fallback
      version_json.dart         # version JSON model incl. arguments/rules/assetIndex
      version_resolver.dart     # inheritance chain, modloader merge
      rules.dart                # os/arch/features rule evaluation
      library_graph.dart        # deps, natives extraction, classpath build
      asset_index.dart          # objects download + legacy virtual assets
      jvm_args.dart             # arg template expansion, memory defaults
      java_requirement.dart     # per-version java major -> java manager query
      launcher_profiles.dart    # launcher_profiles.json interop
    auth/
      offline_auth.dart         # deterministic offline UUID (name -> uuid v3 style)
      msa_device_code.dart      # XBL/XSTS/Minecraft token chain
    net/{downloader.dart, mirror.dart, hash_cache.dart}
    instance/{instance.dart, instance_store.dart}
    mods/{mod_scanner.dart, modrinth_client.dart, toml_parser?}
    crash/{crash_report.dart, crash_analyzer.dart}
  data/                         # providers / repositories wired to core
  ui/
    shell/{app_shell.dart, nav_rail.dart, title_bar.dart, log_drawer.dart}
    launch/ instance/ download/ setup/ speed/ shared/
```

Rule: `core/` never imports `package:flutter`. Every launcher decision (what to download, what command line to build) is a pure function over JSON → unit-testable without a widget tree, which is exactly where launchers break.

### 3.4 Licensing

`flutter_staggered_animations_plus` and `simple_animations` are MIT (safe). Material Components repo is docs (safe). **PCL is not open source** — its license restricts distribution and the repo README frames the code as a synchronized snapshot for reference. So: no code, XAML, strings, or icon assets copied; feature parity is a functional goal, and our strings/art/UX are original. This also means the plan's §7 screens are "same capabilities", not "same pixels".

### 3.5 Release targets — Windows x64, Linux x64, macOS arm64

Verified against the Flutter 3.47.7 tool and live infra, not assumed. Two CI
systems, because neither can do the whole matrix: the Forgejo instance has only
Linux runners, and Flutter cannot cross-compile a desktop app from Linux to
Windows or macOS at all.

| Target | Artifact | Built on | Notes |
|---|---|---|---|
| `windows-x64` | `oh-my-mc-windows-x64.zip` | GitHub `windows-latest` (x64) | |
| `linux-x64` | `oh-my-mc-linux-x64.tar.gz` | Forgejo `glibc-amd64` (x86_64) | native |
| `macos-arm64` | `oh-my-mc-macos-arm64.zip` | GitHub `macos-14` (arm64) | arm-only via `flutter config --enable-macos-arm64-only` |

Each target is published to a release tagged `rolling` **on the system that builds it**: Linux on the
Forgejo instance, Windows and macOS on the GitHub mirror, so a user downloads next to the platform
they are on. Both releases are rebuilt from the assets actually attached and carry the commit in the
filename, and each body links the other. Workflow artifacts alone are not a release: they expire and
need a login.

Scope decision (explicit): **no Windows arm64 and no Linux arm64 build.**
Neither has a downloadable Flutter SDK (consequence 2). Linux arm64 was briefly
carried in the matrix because it is *achievable* — an aarch64 runner existed and
the SDK could be hand-assembled — but "achievable" is not "shipped": it needs a
hand-built toolchain plus a runner that has been dead since 2026-10-21, to serve
an audience with no evidence of demand. An arm64 Linux build is therefore
**not** maintained, and `.forgejo/workflows/arm64.yml` has been deleted. The
sandbox recipe below is retained only as developer-environment setup.

Consequence 1 — **we cannot cross-compile from here.** `flutter build linux --target-platform linux-x64` on this arm64 box fails with *"cross-building only supported on Linux x64 hosts"*. So x64 artifacts come from x64 runners; this sandbox proves macOS-adjacent arm64 logic only. CI is a build dependency, not release polish.

Consequence 2 — **Flutter ships no arm64 Windows or Linux SDK.** Audited all three release manifests: `releases_linux.json` and `releases_windows.json` contain **zero** arm64 archives; only `releases_macos.json` has them. So there is nothing to download that runs on an aarch64 Linux host.

For Linux that is a packaging gap rather than an impossibility. The working recipe, verified on an aarch64 host and automated in `tool/ci/assemble_arm64_toolchain.sh`:

1. extract the **x64** tarball (the only tarball there is);
2. replace `bin/cache/dart-sdk` with a native arm64 Dart SDK of the **exact matching patch version** (3.13.5 for Flutter 3.47.7; 3.13.6 aborts with *"Invalid SDK hash"*), keeping the x64 copy as `dart-sdk-x64`;
3. place `artifacts/engine/linux-arm64/` by hand from the engine hash in `bin/internal/engine.version`, copying `const_finder.dart.snapshot` from the x64 artifacts (arch-independent kernel code) and accepting that **`font-subset` has no arm64 build** — hence `--no-tree-shake-icons`;
4. delete the prebuilt `flutter_tools.snapshot` so the tool recompiles natively on first run; the x64 snapshot dies with *"Snapshot not compatible with the current VM configuration"*.

For Windows the same trick is not available when the SDK itself is absent and there is no arm64 Windows runner, so `windows-arm64` stays out of scope.

Consequence 3 — **the macOS app is arm-only, but the *game* it launches may not be arm-capable.** Launcher architecture and Minecraft runtime architecture are independent problems:

| Game-side component | arm64 macOS |
|---|---|
| Mojang Java runtime (`mac-os-arm64`) | ✅ |
| LWJGL **3** natives (MC ≥1.13) — `natives-macos-arm64` present in manifest | ✅ |
| LWJGL **2** natives (MC ≤1.12.2) — no arm64 build exists anywhere | ❌ |

So **MC ≤1.12.2 cannot run on macOS arm64.** Verified: 1.12.2's manifest lists only `natives-linux|osx|windows`; LWJGL 2 was never built for arm64 on any OS. PCL is Windows-x64-only and never faced this. Our launcher treats it as a diagnosable, explained refusal (`LaunchBlocker`) surfaced *before* the Play button, not an opaque JVM stacktrace. Intel Macs are out of scope, so no Rosetta fallback path is built.

With `linux-arm64` out of the matrix, `arch_compat` stays minimal and is limited to exactly one rule: the macOS-arm64 LWJGL2 refusal. Linux arm64 needs no case at all — the launcher is not shipped there. (For the record, LWJGL3 `natives-linux-arm64` *is* present in the manifest for MC ≥1.13, so if the target were ever reinstated the game would resolve natives itself and no launcher-side patch would be needed.)

#### 3.5.1 CI matrix

Two workflows, one per system, each building the targets the other structurally
cannot.

**Forgejo — `.forgejo/workflows/ci.yml`** (Linux only; both runners are Linux)

| Job | Runner | Command | Verification |
|---|---|---|---|
| `gate` | `glibc-amd64` | `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test` | gates both builds |
| `build-linux-x64` | `glibc-amd64` | `flutter build linux --release` | `tool/verify_binary_arch.dart` → ELF64/x64 |

There is no arm64 job. It was removed along with the target: every job on the
`glibc` label has failed in 1s since 2026-10-21 (including `echo hello`), so it
only ever turned pushes red for a reason unrelated to the commit. The label being
dead is also why an arm64 Linux build could not be reinstated without
infrastructure work, even if the target were wanted back.

The gate deliberately runs on the amd64 runner with a stock SDK: a gate that
depends on the hand-assembled arm64 toolchain is a gate you learn to ignore.

Instance constraints that shape that file (all measured, see §4): no
`actions/checkout` and no marketplace actions (github.com unreachable, and no node
in the runner image) — checkout is a `git clone` over `127.0.0.1:3000`; a per-job
`container:` block is ignored, so the toolchain is installed in-job; the SDK
download needs retry + resume because a bare `curl` of the 1.5 GB tarball dies
with *"curl: (56) Recv failure: Connection reset by peer"*.

**GitHub — `.github/workflows/ci.yml`** (Windows + macOS, which Forgejo cannot build)

| Job | Runner | Command | Verification |
|---|---|---|---|
| `build windows-x64` | `windows-latest` | `flutter build windows --release` | `tool/verify_binary_arch.dart` → PE/AMD64 |
| `build macos-arm64` | `macos-14` | `flutter config --enable-macos-arm64-only` + `flutter build macos --release` | `lipo -archs` must contain `arm64` and must **not** contain `x86_64` |

Those jobs clone the **Forgejo** repository rather than trusting GitHub's copy, so
a green run on either system describes the same commit. Artifacts are attached as
workflow artifacts there; Forgejo publishes a **single** rolling release tagged
`rolling`, holding one asset per Linux architecture (both built from the same
commit), via `tool/ci/publish_release.sh`. That script reads the release back and
refuses to report success unless the asset is actually attached, and only ever
replaces assets for its own target, so the two build jobs cannot clobber each
other. They are split into one release because two per-arch releases had two
independent "latest" pointers that drifted apart.

`tool/verify_binary_arch.dart` exists so a silently mis-targeted binary can never be published under an arch-specific name — it parses the ELF/PE/Mach-O headers itself (14 unit tests, including the arm64-rejected-as-x64 case) instead of trusting the build log.

#### 3.5.2 Game-runtime compatibility layer

`core/mc/arch_compat.dart`, run after version resolution and before the library graph is finalised:

```dart
bool needsLwjgl2(VersionJson v) =>
    v.libraries.any((l) => l.name.startsWith('org.lwjgl.lwjgl:lwjgl-platform'));

/// macOS arm64 has no LWJGL2 natives, so these versions are unlaunchable.
LaunchBlocker? checkHostCompat(VersionJson v, HostOs os, HostArch arch);
```

Rules (unit-testable from fixtures already captured: 1.12.2 = LWJGL2, 1.20.1/26.3 = LWJGL3):
1. `macos && arm64 && lwjgl2` → block before launch, explain that the version predates arm64 support, and suggest a 1.13+ version. Never attempt the launch.
2. `macos && arm64 && lwjgl3` → no patching needed; `natives-macos-arm64` is already in the manifest.
3. `linux`/`windows` x64 → no patching needed at all (this is why dropping the arm64 targets removed a whole class of code).

---

## 4. Environment constraints (measured, not assumed)

Status after M0 bootstrap — every item below was executed, not guessed:

- **Host is `aarch64`** (`uname -m`), Debian 13 trixie. This mattered more than expected: **Flutter publishes no arm64 Linux SDK** (the release manifest contains zero `arm` archives; both plausible arm64 URLs 404).
- **Workaround that works:** the `flutter` tool is a Dart kernel snapshot, so it is architecture-independent — only its bundled Dart SDK is not. So: extract the x64 `flutter_linux_3.47.7-stable.tar.xz`, replace `bin/cache/dart-sdk` with the **native arm64 Dart 3.13.5** SDK, delete the stale x64 `flutter_tools.snapshot` (it fails with *"Snapshot not compatible with the current VM configuration"*), and let `bin/internal/shared.sh` rebuild it natively. Result: `Flutter 3.47.7 • Dart 3.13.5` running natively on arm64. Hack, but self-contained and documented in `AGENTS.md`.
- **Dart patch version must match the engine exactly.** Dart 3.13.6 → `flutter_tester` dies with *"Invalid SDK hash"*. Pin 3.13.5, which is what the SDK's `bin/internal` expects.
- **arm64 engine artifacts are under-populated.** `linux-arm64/artifacts.zip` lacks `const_finder.dart.snapshot` and `font-subset`. `const_finder` is arch-independent kernel code, so copying it from `linux-x64` is safe; `font-subset` is a native ELF with no arm64 build, so **arm64 builds need `--no-tree-shake-icons`** until upstream fills the gap. Consequences are cosmetic-only (larger icon font). This constrains the local build loop only; no CI job builds Linux arm64.
- **Linux desktop toolchain: now fully installed and proven.** `libgtk-3-dev 3.24.49`, `pkg-config`, `cmake 3.31.6`, `ninja 1.12.1`, `clang 19.1.7`, `libsecret-1-dev 0.21.7`, `unzip`. Two real blockers hit and fixed: (a) `libpng-dev` wanted `libpng16-16t64=…u5` while `…u6` was installed → `--allow-downgrades`; (b) `flutter_secure_storage_linux` requires `libsecret-1>=0.18.4`.
- **`flutter build linux --release` succeeds**: `build/linux/arm64/release/bundle/oh_my_mc`, ELF64 **aarch64**, 24 MB. This proves the *local toolchain* works on an aarch64 host; it is not a ship target (§3.5).
- **`flutter test` passes** (`flutter_tester` is native arm64). This is the primary local verification loop — no `DISPLAY` needed.
- **No `DISPLAY`**, so windowed runs still happen in CI or on the user's machine. Consequence unchanged: local loop is `flutter analyze` + `flutter test` + `flutter build linux`; visual sign-off is the user's (or CI screenshots).
- **Cross-compilation is impossible here**: `--target-platform linux-x64` from arm64 → *"cross-building only supported on Linux x64 hosts"*. Hence the runner-per-arch matrix in §3.5.1.
- **Disk/RAM**: 127 GB free, 23 GB RAM — enough for the SDK, pub cache, and parallel builds.

---

## 5. Core engine design (the part that must be right)

### 5.1 Version manifest + mirrors

```dart
abstract class VersionSource {
  Future<VersionManifest> fetchManifest({bool force = false});
  Future<VersionJson> fetchVersion(String id);
  Uri rewrite(Uri officialUrl);        // mirror substitution
}
```
- Cache in `<data>/meta/manifest.json` (TTL 30 min, ETag-aware).
- `MirrorChain` = `[Official, BMCLAPI]` with `rewrite()` mapping `piston-meta`/`libraries.minecraft.net`/`resources.download.minecraft.net` → mirror hosts, ordered by user setting (`DlSourceOrder` equivalent). Health-check switch on 3 consecutive failures.

### 5.2 Version resolution (vanilla + modloader inheritance)

```dart
VersionResolution resolve(String versionId, {InstanceMeta? meta});
// returns: resolvedLibraries, resolvedGameArgs, resolvedJvmArgs,
//          mainClass, assetIndex, javaMajor, mergesApplied
```
- Walk `inheritsFrom` chain (Forge/Fabric/OptiFine install into a child version dir); parent-first merge with the standard rules: `libraries` dedupe by `group:artifact` keeping the **last/highest** entry, `arguments.*` append, `mainClass` overrides, `assetIndex` inherits unless overridden.
- Modloader installers: Fabric/Quilt via `meta.fabricmc.net/v2/versions/loader/{game}/{loader}/profile/json`; Forge/NeoForge via installer jar `--installClient` into a scratch dir then import the produced version JSON (no GUI); OptiFine by reusing the downloaded jar's installer with the same trick.

### 5.3 Rules & library graph

```dart
bool ruleAllows(List<Rule>? rules, RuleContext ctx); // os.name/os.arch/os.version, features
```
`RuleContext` is injectable (`{os: windows, arch: x86_64, features: {has_custom_resolution: true}}`) so tests cover every OS without a VM. Natives: legacy `natives` + `classifiers[<os>-<arch>]` → extract `.dll/.so/.dylib` into `natives/` and append `-Djava.library.path`; modern versions need no extraction. Deduplicate by `group:artifact[:classifier]`, prefer `downloads.artifact`, fall back to maven URL synthesis, verify SHA-1 with `HashCache` (skip re-hash if mtime+size match).

### 5.4 Assets

Modern: `objects/<first2>/<hash>` from `resources.download.minecraft.net`. Legacy (`assetIndex.id` = `1.8`, `1.12`, `pre-1.7`): download `virtual/legacy` tree and, for `map_to_resources` indexes, mirror into `<instance>/resources`. Total ~480 MB for latest — must be resumable and concurrency-limited (see 5.6).

### 5.5 Java management

```dart
class JavaManager {
  Future<List<JavaRuntime>> scan();       // registry/PATH/common dirs; `java -XshowSettings:properties -version`
  Future<JavaRuntime?> findFor(int major); // per-version javaVersion.majorVersion
  Future<JavaRuntime> download(int major); // Mojang java-runtime manifest or Adoptium
}
```
Cache each runtime's `{path, version, arch}` keyed by file identity, not path. UI shows the requirement (`Java 25 required`) and blocks launch with a one-click "Download Java 25".

### 5.6 Downloader

`Downloader` = priority queue (`meta > libraries > assets > mods`), N workers (default 32 metadata / 8 large files), per-host rate limits, exponential backoff, `CancelToken` per task group, aggregate progress (`bytesDone / bytesTotal`, `filesDone/filesTotal`, `speed`, `eta`) exposed as a `Stream<DownloadProgress>`. Every file: temp `.part` → hash check → atomic rename. This stream feeds the animated progress UI (§6.4) directly.

### 5.7 Auth

- **Offline**: `name` → stable v3-style UUID; no network.
- **Microsoft**: device-code flow (`oauth2` PKCE → `login.microsoftonline.com/consumers/oauth2/v2.0/devicecode`) → XBL (`user.auth.xboxlive.com`) → XSTS (`xsts.auth.xboxlive.com`) → `api.minecraftservices.com/authentication/login_with_xbox` → `/minecraft/profile` for name/UUID. Tokens in `flutter_secure_storage`, silent refresh before expiry. Device code is chosen because a Game Bar/OAuth-window flow can't be tested headlessly here.

### 5.8 Launch

```dart
Future<LaunchHandle> launch(Instance inst) // builds argv, spawns, streams logs
```
- Expand `${auth_player_name} ${version_name} ${game_directory} ${assets_root} ${assets_index_name} ${auth_uuid} ${auth_access_token} ${user_type} ${version_type} ${resolution_width/height} ${natives_directory} ${launcher_name} ${launcher_version} ${classpath} ${classpath_separator}` (+ legacy `minecraftArguments` path).
- Defaults: `-Xmx` from instance/settings vs `system_info2` RAM, G1 flags per version, `-Dfile.encoding=UTF-8`, `-Djava.library.path`, `-cp` join with platform separator.
- Spawn with cwd = game dir, capture stdout/stderr → `Stream<String>` → log console + `crash_analyzer`; report exit code; `kill()` tree on "stop".

### 5.9 Instances, mods, modpacks

Instance = directory + `instance.json` (freezed): id, name, icon, gameVersion, loader{type,version}, javaPath override, memory, jvmArgs, resolution, playTime, lastPlayed, modsEnabled, isolation flag. Scanner reads `mods/*.jar` → `fabric.mod.json` / `META-INF/mods.toml` / `mcmod.info` (jar read via `archive`), enabled/disabled via `.disabled` suffix. Modrinth client: search, version filtering by `game_versions` + `loaders`, dependency resolution, install with hash verify. Modpack import: `.zip`/`.mrpack` → `modrinth.index.json` → plan + download.

---

## 6. Motion & design system (the "fluent animations" part)

### 6.1 Motion tokens (`ui/motion/motion.dart`)

```dart
class Durations { static const xfast=120ms, fast=200ms, base=280ms, slow=420ms, ambient=2400ms; }
class Curves_ { static const enter=Curves.easeOutCubic, exit=Curves.easeInCubic,
                            emphasise=Curves.easeOutQuint, spring=Curves.easeOutBack; }
class Stagger { static const step=40ms, maxTotal=320ms, maxAnimatedIndex=24; }
```

`maxTotal` / `maxAnimatedIndex` are **ours, not the package's** — `flutter_staggered_animations_plus`
has no cap and defaults to `duration ~/ 6` per item (`docs/PLAN-M1-M4.md` §0.3). The wrapper
computes `step = min(step, maxTotal ~/ itemCount)` and renders items past `maxAnimatedIndex` at rest.

Single source of truth; no ad-hoc `Duration(milliseconds: ...)` anywhere else (enforced by a grep-based CI check, since a lint can't express it).

### 6.2 The two engines, used for different jobs

| Job | Engine | Technique |
|---|---|---|
| List/grid/column entrances | `flutter_staggered_animations_plus` | `AnimationLimiter(child: ListView.builder(... AnimationConfiguration.staggeredList(position: i, duration: 375ms, child: SlideAnimation(verticalOffset: 50, curve: easeOutCubic, child: FadeInAnimation(child: card)))))` |
| Ambient/background (parallax layers, aurora gradient, floating title particles) | `simple_animations` | `LoopAnimationBuilder<double>(tween: Tween(0,1), duration: 8s, builder: ...)` |
| Reveal/hold (progress, victory state) | `simple_animations` | `PlayAnimationBuilder`, `MirrorAnimationBuilder` (pulsing launch dot) |
| Multi-property choreography (press feedback: scale+lift+glow+tint together) | `simple_animations` | `MovieTween()..scene(0s).tween('scale', Tween(1,0.97))..scene(0s).tween('glow', Tween(0,1))..scene(200ms).tween('scale', Tween(0.97,1))` |
| Page ↔ detail continuity | `animations` package | `SharedAxisTransition` / `OpenContainer`, plus a `Hero` on instance icon |
| Window/element chrome | Flutter implicit | `AnimatedContainer/AnimatedOpacity/AnimatedSwitcher` for cheap state changes |

### 6.3 Reduced motion & performance rules

- **Neither animation package reads `disableAnimations`** (verified by grep + runtime probe,
  `docs/PLAN-M1-M4.md` §0.4). So `MotionScope` must **wrap** the engines rather than configure
  them: when motion is off, `StaggerItem` renders its child with no `AnimationConfiguration` at
  all, and `AmbientLoop` renders one steady frame without creating a ticker.
- `MotionScope` reads (a) `MediaQuery.disableAnimations`, (b) a "UI animations" setting; the two
  are OR'd, and the setting can only ever reduce motion. Surfaced in `PageSetupUI`-equivalent.
- Every animated list item wrapped in `RepaintBoundary`; stagger index passed from the builder, never re-derived in a `setState`.
- Long lists: animate on first paint only (`_hasAnimated` flag per screen), not on scroll.
- Debug: `AnimationDeveloperTools` (simple_animations) toggled by `--dart-define=MOTION_DEBUG=true`.

### 6.4 Concrete animation catalogue (per screen, so review is concrete)

| Screen | Animation |
|---|---|
| Splash/boot | Logo `MovieTween` (scale 0.85→1, blur 8→0, opacity 0→1) + mirrored glow ring; then `SharedAxisTransition.vertical` into shell |
| Shell | Nav rail indicator slides with `Curves.easeOutQuint`; content cross-fades via `AnimatedSwitcher` (no jarring rebuild) |
| Launch (home) | Big version card: staggered hero cloud background (`LoopAnimationBuilder` 12 s drift), play button `MovieTween` press feedback, hover lift `AnimatedScale`, "launching" state → pulsing dot (`MirrorAnimationBuilder`) + log console slide-up |
| Instance list | `AnimationConfiguration.staggeredGrid` 3-column cards, fade+slide (50 px, 375 ms, 40 ms step); icon `Hero` into detail |
| Instance detail | Tab content `AnimationConfiguration.toStaggeredList`; mod toggles `AnimatedSwitcher` + `ScaleTransition`; danger-zone delete uses `OpenContainer`→dialog |
| Download/install | Staged progress: `PlayAnimationBuilder` fills the bar to *reported* progress with a 200 ms trailing catch-up so it never snaps; per-file rows stagger in as they start; speed graph drawn with a `LoopAnimationBuilder`-driven shimmer while throttled |
| Version picker | `staggeredList`, filter chips animate width (`AnimatedSize`); snapshot/release tags `FadeInAnimation` |
| Setup | Section cards `AnimationConfiguration.toStaggeredList`; sliders/toggles Fluent or M3 by theme; save button `MovieTween` success morph (check draw-on) |
| Log drawer | Bottom sheet `SharedAxisTransition`; new lines `AnimatedList` + subtle highlight fade for warnings |

---

## 7. Screen inventory (PCL capability parity → our routes)

| Route | Capability | v1 |
|---|---|---|
| `/launch` | Version select, account chip, play/stop, quick settings, news/announce | ✅ |
| `/instances` | Grid/list of instances, create/import/export/delete/clone, loader + version | ✅ |
| `/instances/:id` | Overview, mods (enable/disable/delete/add), settings (memory, JVM args, resolution, java, isolation) | ✅ |
| `/download` | Version list (release/snapshot/old), loader install, optifine, resource/mod search (Modrinth) | ✅ |
| `/download/install` | Task queue with staged progress, pause/cancel/retry | ✅ |
| `/setup` | Launch (memory, args, window), Java management, download source/mirror, UI (theme, motion toggle, language) | ✅ |
| `/speed` | Download speed test / mirror health | ⏳ v1.1 |
| `/logs` | Live log console + crash analysis result | ✅ |

---

## 8. Milestones

Each milestone ends with a green `dart analyze` + `flutter test` and a demoable artifact. No milestone depends on unfinished work in a later one.

### M0 — Bootstrap & verification harness — **DONE**
Flutter 3.47.7 installed natively on this arm64 host (§4), project scaffolded as `oh_my_mc`/`io.ohmy` for `windows,linux,macos`, `pubspec.yaml` pinned and resolving (149 packages), Linux desktop toolchain installed, `flutter analyze` clean, `flutter test` green, `flutter build linux --release` producing an aarch64 bundle.
**Acceptance met:** all four commands run successfully; the arm64/x64 matrix and its constraints are documented (§3.5) before any feature code was written.

### M0.5 — CI matrix & arch verification — **DONE**
The target set makes CI a build dependency, not release polish: x64 Windows/Linux artifacts can only be produced on x64 runners (§3.5). Landed `.github/workflows/ci.yml`: an `analyze` job (`dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test`) gating a `build` matrix over `windows-latest`, `ubuntu-24.04`, `macos-14`, each verifying its own binary's architecture and uploading a packaged artifact.

**Acceptance met locally:** `dart format --set-exit-if-changed` clean, `flutter analyze --fatal-infos` clean, 15/15 tests green, workflow YAML parses with the expected 3-target matrix. Remaining: first green run on GitHub (needs a pushed branch).

`tool/verify_binary_arch.dart` is the part worth knowing about — it reads ELF/PE/Mach-O headers and exits non-zero on an arch mismatch, so "the build succeeded" can never be confused with "the build is the right architecture". Its own tests caught a real bug during development (I compared the Mach-O magic read little-endian against the big-endian constant, so every Mach-O binary was reported as `unknown`).

### M1 — Core MC engine (pure Dart, no UI)
`version_manifest`, `version_json`, `rules`, `version_resolver`, `library_graph`, `asset_index`, `jvm_args`, `java_requirement`, **`arch_compat`** (§3.5.2).
**Acceptance:** golden-JSON unit tests using **trimmed real fixtures** captured from 26.3 (modern, Java 25, no natives), 1.20.1 (Java 17), 1.12.2 + 1.8.9 (legacy args, natives classifiers, virtual assets) plus synthetic Forge/Fabric `inheritsFrom` chains. Assertions: exact argv for a fixed account/instance, exact classpath ordering + dedupe, correct natives set per `(os, arch)` pair, correct `javaMajor` per version, correct asset policy per index type, and `arch_compat` blocks LWJGL2 on macOS arm64 while leaving LWJGL3 untouched.

### M2 — Downloader + Java manager + install pipeline
Priority queue, sha1 verify, `.part`→rename, mirror chain with failover, cancel/retry, `Stream<DownloadProgress>`; Java scan/download.
**Acceptance:** unit tests with a local `HttpServer` fixture (404 → mirror retry, hash mismatch → re-download once then fail, cancel mid-flight leaves no `.part`); integration test installs a real vanilla version into a temp dir and asserts file count/hashes, marked `@Tags(['network'])`.

### M3 — Design system + motion foundation + shell
Tokens, theme (M3 seed + Fluent bridge), `MotionScope`, `stagger.dart`, `movie_presets.dart`, title bar, nav rail, splash, log drawer.
**Acceptance:** widget tests for reduced-motion collapse (pump with `disableAnimations: true` → no transient frames), stagger order (item N's controller starts before N+1), and golden tests at 3 keyframes per screen shell.

### M4 — UI vertical slice: launch screen + instance list
Instance model/store (`instance.json`), staggered grid, hero to detail, play button states, log console wired to a fake `LaunchHandle`.
**Acceptance:** widget test taps play → state transitions idle→preparing→running→exited with fake process; golden tests; list of 200 items scrolls at 60 fps (verified via `--profile` trace on Windows CI, screenshot diff only).

### M5 — Real launch end-to-end
MS device-code auth, offline auth, `launch()` with real argv, process spawn + streaming, stop/kill, playtime tracking, **`LaunchBlocker` surfacing for arch-compat refusals (§3.5.2)**.
**Acceptance:** on Windows x64 CI, install + launch `1.20.1` offline with a stub main class replaced by a tiny Java "echo args" harness (no game assets needed) → assert argv contains every expected token and process exits 0; then one manual real launch documented in `AGENTS.md`. macOS arm64 coverage asserts the LWJGL2 case is *blocked* rather than launched (§3.5.2).

### M6 — Download UI + version/loader installers
Version picker (staggered), install queue with staged animated progress, Fabric/Quilt profile API, Forge/NeoForge installer import, OptiFine.
**Acceptance:** installer unit tests against captured profile JSON; UI test asserts progress bar never regresses (monotonic invariant on the catch-up animator); cancel leaves instance dir clean.

### M7 — Instance management, mods, modpacks, crash analysis, polish
Mod scanner (fabric.mod.json / mods.toml / mcmod.info), enable/disable, Modrinth search/install/deps, modpack import/export, crash analyzer rules, setup screens, i18n (en + zh_Hans), **per-platform packaging** (`msix` on Windows, `.tar.gz` on Linux, `.dmg`/`.zip` on macOS), launcher icons, README.
**Acceptance:** mod-scan fixtures for all three metadata formats; modpack round-trip test (export → import → identical plan); crash fixtures (Java stacktrace, OOM, mod-mixin, wrong-Java, **arm64+LWGJ2 unsupported**) map to expected diagnoses; the full 5-artifact release set produced by the matrix with arch verified on each.

### M8 (v1.1 backlog)
Speed test page, multi-account switcher UI, per-instance screenshots/gallery, skin preview, update checker, Linux/macOS packaging hardening.

---

## 9. Testing strategy

| Layer | Tool | Notes |
|---|---|---|
| Pure core | `flutter_test` (no widgets) | golden JSON fixtures trimmed from real manifests; the highest-value tests |
| Widgets/motion | `flutter_test` + `matchesGoldenFile` | keyframe goldens; reduced-motion variants |
| Network | local `HttpServer` fixtures | no mocking of our own classes — real Dio against a real socket |
| Integration | `integration_test` on Windows CI | install + stub-launch 1.20.1 |
| Static | `dart analyze` (strict), `dart format --set-exit-if-changed`, custom `tool/check_tokens.dart` | forbids raw `Duration(`/`Curves.` outside motion tokens |

Mocks are limited to: process spawning (until M5) and the OS clock. Everything else runs real code paths.

---

## 10. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `flutter_staggered_animations_plus` is a single-maintainer fork | package disappears | mitigation: `stagger.dart` indirection + MIT vendoring escape hatch (≈200 LOC) |
| `simple_animations` needs Flutter ≥3.44 | blocks older SDKs | we pin 3.47.7; documented in README |
| **No arm64 Linux Flutter SDK upstream** (§4) | the aarch64 dev sandbox needs a hand-built toolchain | `tool/ci/assemble_arm64_toolchain.sh` automates it, verified from scratch on aarch64. **Developer setup only:** no CI job uses it, since `linux-arm64` is not shipped, and the gate runs on amd64 with a stock SDK so a red gate never means "the hand-built SDK broke" |
| **No arm64 `font-subset`** | icon tree-shaking unavailable on the arm64 dev box | `--no-tree-shake-icons` locally only; CI x64 runners tree-shake normally. Cosmetic (larger icon font) |
| **MC ≤1.12.2 has no arm64 LWJGL2 natives** (§3.5.2) | those versions cannot run on macOS arm64 | product-level honesty: `LaunchBlocker` + crash-analyzer diagnosis; never ship a silent crash. Intel Macs out of scope, so no Rosetta fallback |
| **macOS arm-only drops Intel Macs entirely** | some users cannot run the launcher | accepted product decision; PCL's own install base is overwhelmingly Windows. Reversible with one config flag if it ever matters |
| 3-target matrix triples CI time and failure surface | slow feedback, flaky release | `fail-fast: false` so one platform can't mask the others; arch-verification step makes a mis-targeted artifact impossible to publish |
| Version 26.x schema drift (Java 25, new arg forms) | launch failures | rules/args resolvers driven by fixtures for 26.3 **and** legacy; unknown fields preserved, unknown arg placeholders warn-not-crash |
| PCL license restricts reuse | legal | behavior-only reimplementation, original assets/strings (§3.4) |
| MS auth can't be fully tested headlessly | login regressions | device-code flow testable to the token-exchange boundary with a fake token endpoint; offline path always available |
| 480 MB asset downloads in tests | slow CI | network-tagged tests excluded by default; opt-in job nightly |

---

## 11. Decisions locked

All previously open questions are now answered (you chose "agent defaults"):

1. **Name / id** — `oh_my_mc` / `io.ohmy`, display name **"oh my mc"**.
2. **Window chrome** — Fluent shell (`fluent_ui` nav rail + Mica via `flutter_acrylic`), Material 3 for content components. Matches "fluent animations + Material design guidance".
3. **Languages** — English + Chinese (`zh_Hans`) from the start, via `flutter_localizations` + ARB; every user-visible string goes through `AppLocalizations` from the first widget, not retrofitted in M7.
4. **Auth scope** — offline + Microsoft device code in v1 (both), because an offline-only launcher can't join most servers.
5. **Modloaders** — all five in v1: Fabric, Quilt, Forge, NeoForge, OptiFine.
6. **Feature scope** — full PCL pre-2.99 surface (§7 inventory).
7. **Platforms** — the 6-target matrix in §3.5, with arm64 runtime caveats surfaced in-product rather than hidden.

Remaining judgement call I'll make myself unless you object: **LAN/"Link" tunnel** (PCL's EasyTier-based multiplayer). PCL ships a bundled `easytier` binary and talks to `uptime.easytier.cn`. Reproducing that means vendoring a third-party VPN binary per architecture, which cuts directly against the 6-target matrix and adds a security surface. Plan: **v1 ships LAN discovery/join on the local network only**; the EasyTier tunnel is deferred to the M8 backlog with a note. Say the word if you want it in v1 and I'll scope it separately.

---

## 12. Definition of done (v1)

A user on **any of the three targets** can: launch the app → see an animated shell → log in (offline or MS) → install `1.20.1` (+Fabric) through the animated installer → create an instance with memory/Java settings → add a mod from Modrinth or drop in a jar → press Play and watch the log stream → stop the game → get a readable crash diagnosis if it fails — with all motion respecting the reduced-motion toggle, English or Chinese UI, and all 3 release artifacts produced and arch-verified by CI.

Where a target genuinely cannot run a given game version (macOS arm64 + MC ≤1.12.2, §3.5.2), the app says so clearly *before* launch and explains why, instead of failing with an opaque JVM error.
