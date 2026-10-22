# PCL 2 parity: the structure users actually learn

This file is the contract for "the launcher behaves the way PCL does". It records
PCL 2's own structure, how a user actually sets Minecraft up with it, where this app
stands, and the order the gaps get closed. It is a working document: every item is
either done (with the file that proves it) or a named backlog entry.

PCL is closed-source; nothing here is copied from its code. The structure below is
the *behaviour* users describe in its own tutorials and help pages.

---

## 1. PCL 2's structure

| Area | What PCL puts there |
|---|---|
| Top navigation | **启动 / 下载 / 设置 / 更多** (联机, 皮肤, 工具) |
| 启动 (launch) | One **version card** per installed version - the card is the selector. Click the card to switch versions, its settings button opens 版本设置. Big 启动游戏 button, log tail, and a way to cancel a launch in progress. |
| 下载 (download) | 游戏版本 (release/snapshot/old + loaders), **Mod**, **整合包**, 资源包, 光影, 数据包, 世界, 服务器. Every install is a queued task with staged progress, pause/cancel. |
| 版本设置 (per version) | The hub for one version: 设置 → 游戏 (内存, Java, 窗口大小, 启动参数) / 高级; **Mod 管理**; 资源包; 光影; 存档; 数据包; 服务器; 打开文件夹; 删除. |
| 账户 | Offline name, Microsoft sign-in, skin. |

Two properties matter more than the list:

1. **The version is the unit.** There is no "project" or "instance" object to create
   first; a version that exists on disk is a card on the launch page.
2. **A finished download is immediately playable.** After 下载 finishes, the version
   appears on 启动. The user never "registers" it.

## 2. How a user sets Minecraft up (the flow to match)

1. **首次启动** → empty launch page → 下载.
2. **下载 → 游戏版本** → pick a version (optionally a loader) → 开始下载 → progress
   task → done.
3. **启动** → the new version is a card; it is already selected.
4. **版本设置** → Java (PCL auto-picks a matching JVM and offers to download one),
   memory slider, window size, launch arguments.
5. **启动游戏** → log tail; on failure the launcher explains the cause (missing
   Java, arch mismatch, crash report) rather than a bare exit code.
6. **Mods** → either 下载 → Mod (CurseForge/Modrinth search, dependencies) or
   版本设置 → Mod 管理 (enable/disable/delete, open the folder).
7. **整合包** → 下载 → 整合包 (from a platform or an existing `.zip`) → it installs a
   whole version with its mods and config.

Every step has one obvious next action, and steps 2-3 are the pair this app got
wrong: installing wrote files, and nothing pointed the launcher at them.

## 3. Where this app stands

| PCL capability | Status | Where |
|---|---|---|
| 启动: version card as selector | **done** | `_VersionPicker` in `lib/ui/launch/launch_screen.dart` |
| 启动: play/stop, log tail, busy state | **done** | same file |
| 下载: version list (release/snapshot/old) + install queue + progress | **done** | `lib/ui/download/`, `lib/data/install_providers.dart` |
| 下载完成即出现在启动页 | **done** | `InstallController.install` → `InstanceListController.ensureForVersion` |
| 版本设置: reachable from the card and from 版本设置 button | **done** | `/instances/:id`, `lib/ui/instances/instance_detail_screen.dart` |
| 版本设置: Java (path + detect + download), memory, JVM/game args, isolation | **done** | `instance_detail_screen.dart`, `lib/ui/setup/java_panel.dart` |
| 版本设置: open the game folder | **done** | Files section of the detail screen |
| Accounts: offline name | **done** | `AppSettings.playerName`, `launch_service.dart` |
| UI: language, theme, accent colour | **done** | `/setup` |
| **Loader install** (Fabric/Quilt/Forge/NeoForge) | **missing** | `LoaderKind` exists; no installer |
| **Mod management** (scan `fabric.mod.json`/`mods.toml`/`mcmod.info`, enable/disable/delete) | **missing** | - |
| **Mod search/install** (Modrinth/CurseForge, dependencies) | **missing** | - |
| **Modpack import/export** (`.zip`, `.mrpack`) | **missing** | - |
| **Instance import/export/clone** | **missing** (ARB strings only) | `instanceImport`, `instanceExport`, `instanceClone` |
| **Per-version window size** | **missing** | `Instance` has no width/height |
| **Crash analysis** | **missing** | - |
| **Microsoft sign-in, skin** | **missing** | offline identity only |
| 资源包 / 光影 / 存档 / 数据包 / 服务器 entries | **missing** | - |
| Download speed test / mirror health | **missing** (planned v1.1) | - |
| 联机 (LAN/port mapping) | **missing** | - |

## 4. Backlog, in the order it gets built

**P0 - nothing launches without these (landed)**
- `/instances/:id` rendered the launch screen because the route table compared the
  *pattern* to the concrete path. Fixed in `lib/main.dart` (`_screenFor` reads the
  route parameter), pinned by `test/ui/shell_material_test.dart`.
- 新建实例 hardcoded `versionId: '1.20.1'`, so an installed 26.3 could not be
  selected at all. The dialog now asks name + version from the *installed* set, and
  refuses to create an instance when nothing is installed (pointing at 下载).
- A finished install registers an instance for its version and selects it, so the
  Play button has a target the moment the files land.

**P1 - loaders.** Without Fabric/Forge most users cannot run their mods at all.
Fabric/Quilt: the meta API (`v2/versions/loader/<game>/<loader>/profile/json`) gives
a complete version JSON, so install = fetch + write + launch like vanilla. Forge/
NeoForge: run the official installer jar with `--installClient` against a temp
launcher dir, then copy the produced version. Either way `LoaderKind` stops being a
label and becomes a real install path.

**P2 - the rest of 版本设置.** Window size (width/height/fullscreen on `Instance`),
the per-version mods/resourcepacks/shaderpacks/saves entries (list + open folder +
delete), and "open folder" for each. This is cheap and closes the "where do I put
my mods" question.

**P3 - mods.** Local scan first (the three metadata formats → name/version/enabled
by file extension), enable/disable by renaming `.jar` ↔ `.jar.disabled`, delete.
Then Modrinth search/install with dependency resolution. CurseForge needs an API key
and is a separate decision.

**P4 - packs and instance portability.** `.mrpack`/`.zip` import (parse manifest →
resolve loader → install → download overrides), export, and instance clone/export
as a zip. Import/export strings already exist.

**P5 - accounts.** Microsoft device-code auth (the OAuth flow PCL uses), token
refresh, skin. Offline stays first-class.

**P6 - diagnostics.** Crash analyser over the log tail (Java stacktrace, OOM,
wrong-Java, mod mixin, arch mismatch) mapping to a human sentence and an action;
download speed test; LAN helpers.

## 5. Rules that keep us aligned with PCL

1. **The version card is the selector.** Any new screen that picks a version must
   route through the launch page's picker, not invent a second one.
2. **Download ⇒ playable.** Any install path (version, loader, modpack) ends by
   making the result launchable (`ensureForVersion` or its pack equivalent).
3. **Per-version settings live in 版本设置**, never in the global 设置 page. The
   global page holds what is true for the whole launcher: language, theme, accent,
   default memory, player name, Java search paths.
4. **One obvious next action per state.** Empty launch page → 下载; install done →
   Play; launch refused → the fix (Java/loader/mod) inline.
5. **An instance is a superset of a version**, which is the one place we deliberately
   differ: two instances may share one installed version (different mods, different
   memory). PCL's single-version model is the default path, not a constraint.
