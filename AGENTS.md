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

No `DISPLAY` → no windowed runs here. Visual verification is the user's job, or CI screenshots.

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

## Architecture rules

- `lib/core/**` must not import `package:flutter` (it must stay pure-Dart testable).
- All durations/curves come from `lib/ui/motion/motion.dart`; no inline `Duration(` / `Curves.` elsewhere.
- Respect reduced motion via `MotionScope` (collapses durations to 0).
- Every user-visible string goes through `AppLocalizations` (en + zh_Hans). No hardcoded UI text.

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

## Test-environment facts

- **This sandbox has no Java at all** (`java: command not found`, no `/usr/lib/jvm`). Java
  probing tests therefore inject a `runProcess` double; nothing here can launch a real game.
- **The sandbox has live network access.** An "offline" test that relies on a real URL failing
  will silently pass the download and fail the assertion. Tests that need failure point at
  `http://127.0.0.1:1/…` instead (`deadUri()` in `version_manifest_test.dart`).
- Fixture-based tests are the default; `tool/smoke_download.dart` is the only thing that
  touches the network, and it is run by hand (`dart run tool/smoke_download.dart 1.20.1
  [--mirror]`).

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

* **Forgejo** (`.forgejo/workflows/ci.yml`) builds `linux-x64` + `linux-arm64` and runs the gate.
  Both runners are Linux: `glibc` = aarch64, `glibc-amd64` = x86_64. No macOS/Windows runner exists.
* **GitHub** (`.github/workflows/ci.yml`) builds `windows-x64` + `macos-arm64`. Those jobs clone
  `https://git.vedaru.cn/Vedaru/oh-my-mc.git` (public, anonymous clone works) so both systems build
  the same commit. Push to both remotes: `git push forgejo master && git push github master`.
* Heavy logic lives in `tool/ci/*.sh`, not YAML, so it can be run and tested locally:
  * `fetch_flutter_sdk.sh <dest> [ver]` — 1.5 GB tarball, retries + resumes + mirrors (CN mirror is
    ~8-22 MB/s and reachable; a bare curl died at 7 min with "Recv failure: Connection reset by peer").
  * `assemble_arm64_toolchain.sh <dest> [ver]` — the hybrid SDK recipe above, automated. Verified
    from scratch on aarch64: rebuilds the tool natively, then `flutter build linux --release` gives
    an ELF with `e_machine=0xb7`.
  * `package_linux.sh <root> <target>` / `publish_release.sh <root> <target> <sha>` — rolling releases
    tagged `rolling-linux-x64` / `rolling-linux-arm64`.

### Traps that cost real time
* `tar -tzf ... | grep -q NAME` under `set -o pipefail` **fails on a good archive**: grep exits at the
  first match, tar takes SIGPIPE, pipeline status is non-zero. Capture the listing first.
* The Forgejo release API returns `{"message":"repo is empty"}` until the first push lands.
* Job logs are not in the REST API. Fetch them from the web UI:
  `https://git.vedaru.cn/<owner>/<repo>/actions/runs/<n>/jobs/<i>/logs`.
* `assert s.count(x)` against YAML written by hand is fragile — rewrite the file instead of patching it.
