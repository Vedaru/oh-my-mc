# Implementation plan — M6 → M9 (revision 2)

Supersedes `docs/PLAN-M4.2-M9.md` §2 from M6 onward. That document's M6 was a
sketch written before any instance-detail code existed; this one starts from what
is in the tree, measured, and only then schedules the remainder of PCL parity.

**Position:** M6 is ~80 % landed (uncommitted) · **M6.5 (instance CRUD parity) and
M7 (loaders) are next** · M8, M9 pending.

---

## 0. Where the code actually is

Measured at `4145071` + working tree, 2026-10-22:

| Gate | Result |
|---|---|
| `dart format --set-exit-if-changed lib test tool` | clean (109 files) |
| `dart run tool/check_tokens.dart` | `OK (59 files checked)` |
| `flutter analyze --fatal-infos` | **No issues found** |
| `flutter test` | **545 passing, 1 skipped** |

### 0.1 Landed since the last plan

| Area | Files | State |
|---|---|---|
| Instance detail | `lib/ui/instances/instance_detail_screen.dart` (601 L), `InstanceListNotifier.update` | name, version, isolation, memory override, Java override, playtime, open-folder, delete |
| Log console | `lib/ui/logs/logs_screen.dart` (188 L) | filter (all / errors), search, copy whole log — `/logs` no longer a placeholder |
| Setup screen | `lib/ui/setup/setup_screen.dart` (+347 L), `lib/ui/setup/java_panel.dart` | language, theme, motion, player name, global heap, managed-runtime list with delete |
| Routing | `lib/main.dart` | `/instances/:id` and `/logs` now render real screens; `_Pending` deleted |
| Tests | `test/ui/instance_detail_test.dart` (8), `setup_screen_test.dart` (16), `java_providers_test.dart` (+207 L) | — |

### 0.2 Defects repaired this session (both were failing tests, not product bugs)

1. **`languageEnglish` failed the zh-parity gate.** "English" is the correct
   Chinese string for that language (a language names itself in its own script),
   so it belongs in `identicalByDesign` next to `setupJava`; the test, not the
   ARB, was wrong.
2. **Three setup-screen tests could not see the Java section.** The page now
   exceeds the default 600 px test viewport and `ListView` does not build
   off-screen children, so `find.text('Java 17 (17.0.15)')` found nothing and the
   memory-slider `drag` landed outside the render tree. The fixture now pumps at
   1400×2600. Note the failure mode: it read as "the runtime list is broken"
   while the list was fine — a test that silently asserts about an unbuilt subtree
   is worse than no test.

Also removed: `test/dbg_test.dart` (throwaway debug harness), an unused import in
`launch_and_instances_test.dart`, and formatting drift in four files.

### 0.3 Defects found while planning — the queue (all real, none fixed yet)

| # | Defect | Why it matters |
|---|---|---|
| D1 | **Deleting an instance does not delete its directory.** `InstanceListNotifier.remove` only rewrites the JSON; the only `delete(recursive:)` calls in `lib/` are the Java ones. | PCL users expect delete to reclaim disk. An isolated instance keeps hundreds of MB, and `instanceDir(id)` is orphaned forever because ids are never reused. |
| D2 | **`ManagedJavaRuntime.majorVersion` hardcodes `arch: HostArch.x86_64`** (`java_providers.dart:303`). | On macOS arm64 — a ship target — a managed runtime reports the wrong arch. `selectRuntime` then compares arch against the host. No second arch can exist on one machine today, so it is latent, but it is a lie in the model. |
| D3 | **Two different heap clamps.** `settings.dart` validates 512–65536; `_MemoryRow` and `_GlobalMemoryRow` both cap at 16384. | The per-instance override cannot express a value the global setting accepts, and `PLAN.md` §6.4 claims one clamp. Pick 65536 and export the constant once. |
| D4 | **No `jvmArgs` / `gameArgs` editor.** `Instance` carries both and `launch_factory.dart:155-156` passes both to the plan. | The last two instance fields with no UI. PCL parity (§7) requires them, and `launch_service_test` proves the plumbing already works. |
| D5 | **Instance creation hardcodes `versionId: '1.20.1'`** (`instances_screen.dart:116`) and `LoaderKind.vanilla`. | A launcher cannot ship a create dialog that always makes 1.20.1 vanilla. Biggest single hole in M6. |
| D6 | **`window_manager` is never initialised** — no `ensureInitialized`, no `WindowOptions`, no min size; `flutter_acrylic` is unused (0 imports). | Window is unpositioned and unresizable-to-sane on first run; `AGENTS.md`'s Mica claim is aspirational. |
| D7 | **Golden diff artifacts are committed** (`test/ui/failures/theme_dark_*.png`, 4 files). | These are `flutter test --update-goldens` debris. Committed failure images make a real regression indistinguishable from old noise. |
| D8 | **Eight declared dependencies have zero imports** (`dio`, `oauth2`, `lucide_icons`, `file_picker`, `process_run`, `system_info2`, `url_launcher`, `flutter_acrylic`). | `flutter_acrylic` and `oauth2` are on the critical path for M9 (Mica, MS sign-in) — keep. `dio` is dead because `lib/core/net` uses `dart:io` `HttpClient`; `lucide_icons`, `system_info2` have no planned consumer. Remove or commit to them now, because each is a licensing and supply-chain surface. |

D1, D3, D4, D5 are M6 blockers. D2, D6, D7, D8 are a hygiene task.

---

## 1. Non-negotiable constraints (unchanged, restated once)

1. **PCL is a behaviour reference.** No code, XAML, string table, icon or asset.
   `Meloong-Git/PCL` carries a restrictive non-OSI licence; parity is functional.
2. **`lib/core/**` never imports Flutter.** Everything is testable with
   `dart test` semantics, which is why install/launch logic sits apart from screens.
3. **Every user-visible string goes through `AppLocalizations`** (en + zh_Hans,
   zh_Hant falls back). The ARB test enforces key parity, a `@description` on
   every en message, *and* that zh differs from en unless explicitly whitelisted.
4. **All durations/curves come from `lib/ui/motion/tokens.dart`**, enforced by
   `tool/check_tokens.dart` over `lib/ui/` (excluding `lib/ui/motion/`). Reduced
   motion is a wrapper, never a zero duration.
5. **Every failure is actionable** — names what failed and what the user can do.

---

## 2. M6 — Instance detail, completed

The page exists; these close it. Exit criterion is unchanged: **every `Instance`
field is reachable from the UI, and a widget test proves each edit round-trips to
the store.**

| Task | Deliverable |
|---|---|
| 6.7 | **Arguments tab.** Two `TextBox` lists, one arg per line, parsed with a shared `parseArgs` (quote-aware: `-Dfoo="a b"` must stay one argv entry). Empty means empty list, not `['']`. Test: write → read → store → `launch_factory` gets the same argv. |
| 6.8 | **Java tab "test" button.** Runs the selected executable with `-XshowSettings:properties -version` through the existing `JavaProbe` seam, shows the parsed major + vendor inline. The `-version` dump goes to stderr — read both (already in `AGENTS.md`); do not re-derive it. |
| 6.9 | **D1: delete removes the directory.** `remove(id, deleteFiles: true)` → `instanceDir(id).delete(recursive: true)` guarded by `p.isWithin`, *after* the JSON commit succeeds (a failed file delete must not leave an instance the store still lists). Confirmation text must say the files go too. Test: create dir with a file → remove → `existsSync() == false`. |
| 6.10 | **D3: one heap clamp.** `const kMinMemoryMb = 512; const kMaxMemoryMb = 65536;` in `core/instance/`, imported by both sliders and `AppSettings`. |
| 6.11 | **D4 follow-on:** honour `IsolationKind` change semantics. Switching to isolated must *not* pretend to move an existing mods folder — show it as "new empty game directory" with a warning, which is what the code already does; assert that message exists so it cannot regress into a silent data migration. |

**Not in M6:** mod lists on the detail page (that is M8, and a mod list with no
loader to install into is a dead page).

---

## 3. M6.5 — Instance CRUD parity (new; was hidden inside M7)

**Why this is its own milestone:** D5 means the product cannot currently create
anything but "1.20.1 vanilla", and `PLAN.md` §7 promises create / import / export
/ clone. This is also the first screen that needs to know about *installed*
versions and *available loaders* at the same time, so it is the bridge to M7.

| Task | Deliverable |
|---|---|
| 6.5.1 | **Create dialog → small form:** name, version (from `installedVersionsProvider`, plus a "download more" link to `/download`), loader picker (disabled with a reason when the loader is not installed for that version). Replaces the name-only dialog. |
| 6.5.2 | **Clone:** copy `Instance` with a new id and `name + " copy"`; copy the game directory only when isolated (a shared instance has nothing of its own to copy). Playtime reset, `lastPlayedAt` cleared. |
| 6.5.3 | **Export/import:** one `.json` per instance, carrying the `Instance` record and *not* the game files; import validates via the existing tolerant decoder and skips malformed entries with a count, exactly like `decodeInstances` already does. |
| 6.5.4 | **Empty state promise:** with no instances, `/instances` offers create *and* "install a version", because a fresh user has neither. |

**Exit:** from an empty data dir, install 1.20.1 on `/download`, create an
instance for it from `/instances`, open it, and have every action round-trip —
with no value hardcoded in the UI.

---

## 4. M7 — Mod loaders

Unchanged in intent from the previous plan; the endpoints are now probed, not
assumed (this host, 2026-10-22):

| Source | Probe | Result |
|---|---|---|
| Fabric loader list | `meta.fabricmc.net/v2/versions/loader/1.20.1` | **200, 599 KB, 255 builds**; entry shape `{loader:{version,stable,maven: 'net.fabricmc:fabric-loader:<v>'}, intermediary, launcherMeta}` |
| Fabric profile | `…/loader/1.20.1/0.16.5/profile/json` | **200, 2.8 KB** — already `inheritsFrom: "1.20.1"`, `mainClass: …KnotClient`, `arguments.jvm: ["-DFabricMcEmu= net.minecraft.client.main.Main "]` |
| Quilt loader list / profile | `meta.quiltmc.org/v3/versions/loader/1.20.1[/<v>/profile/json]` | **200** (892 KB / 200) — same shape, so one client covers both |
| Forge promotions | `files.minecraftforge.net/…/promotions_slim.json` | **200**, `1.20.1-recommended → 47.4.28` |
| NeoForge versions | `maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge` | **200** — note the version scheme is MC-minor-based (`20.2.x` ↔ 1.20.2), not `1.20.1`-keyed |
| Modrinth search | `api.modrinth.com/v2/search` | **200** |

Two consequences worth stating before code is written:

- **Fabric's profile is not the same shape as a vanilla version JSON.** It has no
  `downloads.client`, no `assetIndex`, no `javaVersion`; it relies entirely on
  `inheritsFrom`. `resolveVersion` already merges that chain and `version_json`
  already preserves `inheritsFrom`/`jar`, so this is a *data* path that exists —
  it needs a fixture, not new merge logic. The trap: the merged version must take
  `mainClass` and `arguments.jvm` from the **child**, and assets from the parent.
- **`-DFabricMcEmu= net.minecraft.client.main.Main ` has a trailing space and an
  internal one.** It is a single argv entry as served. Do not trim or split it;
  a test must pin the exact string.

| Task | Deliverable |
|---|---|
| 7.1 | `lib/core/loaders/loader_meta.dart` — pure parsing of Fabric/Quilt `…/loader/<mc>` lists; `LoaderBuild {version, stable, maven}`. |
| 7.2 | `lib/core/loaders/profile.dart` — fetch a loader profile JSON, validate `inheritsFrom` matches the requested MC, write it as `versions/<loader>-<v>-<mc>/<same>.json`. Refuse when the parent version is not installed, naming it. |
| 7.3 | **Fabric + Quilt install path** end-to-end (one client, both APIs). Download ~14 libraries from `maven.fabricmc.net` through the existing `FileDownloader`/`HashCache`/`MirrorChain` — no second download stack. |
| 7.4 | **NeoForge:** version list + `install_profile.json` handling. Newer NeoForge ships a processor-free path for the client; **assert which shape before implementing**, and refuse with a clear message for any version that needs a processor chain rather than half-installing it. |
| 7.5 | **Forge:** installer *processor chain* (`installertools`, `jarsplitter`, `binpatcher`). This is the hardest task in the project. Budget it alone; do not start it in the same change as anything else. |
| 7.6 | **UI:** loader picker in the create/edit flow (6.5.1 hooks it), install progress in the existing `/download` panel shape. |
| 7.7 | **Launch verification per loader** with `tool/verify_launch.dart` (real argv against a real JDK) — unit tests assert what we *believe* the JVM accepts, and that is not the same thing. |

**Exit:** Fabric, Quilt, NeoForge and Forge each install and reach the main menu
on at least one MC version, verified end-to-end (real installer jars, not a unit
test). Loader installs that cannot be supported refuse *before* writing files.

**Ordering that is not negotiable:** Fabric/Quilt (7.1–7.3) before Forge (7.5).
Fabric's metadata is simple and proves the inheritance path; Forge's processors
will expose every bug in it, and debugging both simultaneously is how a week
disappears.

---

## 5. M8 — Mods, resource packs, worlds

| Task | Deliverable |
|---|---|
| 8.1 | Mod scanner: `fabric.mod.json`, `mods.toml`/`neoforge.mods.toml`, `mcmod.info` → `{id, name, version, loader, deps}`. Fixtures for all three (the formats are the whole risk). |
| 8.2 | Per-instance mod list: enable/disable by `.jar` ↔ `.jar.disabled` rename (never delete), delete behind confirmation, dependency warning when a required mod id is absent. |
| 8.3 | Modrinth search + install (`api.modrinth.com/v2`), loader+MC-filtered; dependency resolve one level deep with an explicit list the user confirms. |
| 8.4 | Drag-and-drop `.jar` import with a compatibility check against the instance's loader and MC version; reject, do not silently place, when it cannot load. |
| 8.5 | Resource packs / shader packs (`resourcepacks/` vs `shaderpacks/`) and a world list with backup-before-delete. |

**Exit:** install a mod from search, see it in the list, launch, game loads it.

---

## 6. M9 — Accounts, crash analysis, shell polish

| Task | Deliverable |
|---|---|
| 9.1 | Why the log console matters: `/logs` currently answers "what did it print". M9 turns `hs_err_pid*.log` + the last 200 lines into **named causes** — wrong Java (reuse `BlockerCode.javaTooOld`), OOM (`OutOfMemoryError` + the `-Xmx` we passed), missing mod dependency (id from 8.1's scanner), GL driver, and the arm64 + LWJGL2 refusal `PLAN.md` §3.5.2 promises. Each diagnosis names a fix. |
| 9.2 | Microsoft device-code sign-in. `oauth2` is already a dependency and `LaunchRequest` already takes `uuid`/`accessToken`/`userType`, so this is a token source, not a rewrite. Refresh token in `flutter_secure_storage` (already a dep; the Linux build needs `libsecret-1-dev`, installed). Offline stays the fallback and `offlineUuid` stays byte-identical — `launch_factory_test` pins it. |
| 9.3 | Account chip in the shell (name + skin-less avatar initial), "sign out", and the offline/online distinction shown before launch — a server rejecting an offline token is the classic silent failure. |
| 9.4 | **D6:** `windowManager.ensureInitialized()`, `WindowOptions(size, minimumSize, center: true, titleBarStyle)`, and Mica/acrylic on Windows with a documented fallback (macOS is best-effort — `flutter_acrylic` ships no `macos/`). |
| 9.5 | `/setup` completions: **download source** (official / BMCLAPI / auto) — `MirrorChain` exists and *no* UI reaches it (`PLAN-M4.2-M9.md` 5.6), still true today; plus total disk used by managed runtimes. |
| 9.6 | **D2/D7/D8 hygiene:** runtime arch from the host, remove committed golden-diff artifacts, and delete the dependencies with no consumer (`dio`, `lucide_icons`, `system_info2`) or wire the ones still planned (`file_picker` for 8.4, `url_launcher` for links). |
| 9.7 | Packaging: `msix` on Windows, `.tar.gz` on Linux (scripts exist), `.dmg`/`.zip` on macOS; `flutter_launcher_icons`. |

**Exit:** a deliberately broken launch (Java 8 + 1.20.1) produces a diagnosis
naming Java and the fix — not a stack trace.

---

## 7. Motion & design — the part that is behind

The functional side is ahead of the visual side. `PLAN.md` §6.4 is still mostly a
wish list; what actually renders today:

| Catalogue item | State |
|---|---|
| Splash `AmbientLoop` wordmark + fade | ✅ |
| Shell content cross-fade (`AnimatedSwitcher`) | ✅ |
| Page transitions (`SharedAxisTransition` via `appPage`) | ✅ |
| Instance grid stagger (`StaggerItem` + bounded budget) | ✅ |
| Page-level entrance (`MotionEntrance`) | ✅ on launch, instances, setup, logs, detail |
| Download list stagger | ✅ |
| **Progress bar trailing catch-up** ("never snaps") | ❌ `ProgressBar(value:)` only — accepts the jump |
| **Instance card `Hero` → detail** | ❌ no `Hero` anywhere in `lib/` |
| **Nav-rail indicator easing** | ❌ Fluent default |
| **Log lines via `AnimatedList` + warning highlight** | ❌ plain list, rebuilt per frame of log |
| **Play button press feedback (`MovieTween`), hover lift** | ❌ |
| **Filter chips `AnimatedSize`** | ❌ |

Rules for closing these, so it stays reviewable:

- New primitives go in `lib/ui/motion/primitives.dart`, **wrapped** so motion-off
  returns the resting frame and allocates no ticker. Assert with
  `tester.binding.transientCallbackCount == 0`, never with a zero duration and
  never with `hasScheduledFrame` on a tree containing a `ListView`.
- The progress catch-up is a `TweenAnimationBuilder`-style follow toward the
  *reported* value with a `Durations.fast` tail — and its test is the monotonic
  invariant (the rendered value never decreases) plus "a stalled install does not
  creep to 100 %".
- `Hero` between card and detail needs the same tag on both ends; the detail page
  is reachable by deep link with no card on screen, so the tag must be optional.

---

## 8. Cross-cutting gates (every milestone)

- `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`,
  `dart run tool/check_tokens.dart`, `flutter test`. CI adds
  `tool/verify_binary_arch.dart` per target.
- New strings land with **en + zh + `@description`** in the same commit; a zh
  string that equals en must be added to `identicalByDesign` deliberately.
- A bug fix without a regression test is not done. Every defect in §0.3 gets one.
- No silent `catch`: log to the session log or return an actionable value.

---

## 9. Sequencing rationale

**M6 finish → M6.5 → M7 → M8 → M9.**

- M6 first because D1/D4 are the difference between "a settings page" and "every
  field is editable"; both are hours, not days.
- M6.5 before M7 because the loader picker (7.6) has nowhere to live until the
  create form exists, and a loader installed with no instance to install into is
  unobservable.
- M7 before M8 because most mods are loader-specific; a mod browser without
  loaders serves only vanilla players.
- M9 last because accounts and crash analysis multiply the quality of a launcher
  that must first install and launch. Exception: **D6 (window init) and D7/D8
  hygiene can ride along with any earlier change** — they are one-file fixes that
  make every later screenshot honest.
- Forge (7.5) after Fabric (7.1–7.3), always.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Forge processor chain is opaque and fails without diagnostics | Own milestone slot; verify by real launch, not by unit test; refuse unsupported versions explicitly |
| NeoForge version scheme (`20.2.x`) is not `1.20.1`-keyed | Derive from the Maven list, never from a `mcVersion` string; fixture the mapping |
| Loader profile drift (Fabric/Quilt APIs are versioned `v2`/`v3`) | Pin the parsed shape, validate `inheritsFrom`, refuse rather than guess; fixture captured JSON |
| Managed JREs are ~96 MB each (67 MB on the wire) | `/setup` shows per-runtime disk use and total (9.5); deletion already works |
| Widget tests silently assert on unbuilt `ListView` children | Tall test viewport (this session's fix); prefer `ensureVisible` only when the scroll itself is under test |
| arm64 dev sandbox cannot build Windows/macOS | Those paths are verified by CI (`windows-x64`, `macos-arm64`); no local claim pretended otherwise |
