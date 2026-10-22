# M3.5 implementation notes — installer glue

Scope: make the launcher able to install a version. Pure Dart, `lib/core/install/`,
no Flutter (import law bans the engine under `lib/core/`), no visual decisions.

## Why this is the milestone

`planInstall` and `FileDownloader` both work and are well tested, but nothing in
`lib/` calls them: 36 of the 281 tests describe machinery with no caller. The
missing glue *is* the feature. Natives are computed by `buildLibraryGraph` and
then never unpacked, so a 1.12.2 install today produces a version that cannot
launch.

## Pipeline

```
manifest -> version JSON (+ inheritsFrom chain) -> asset index -> plan
         -> download -> natives extraction -> asset materialization -> verify
```

Order matters and is not free to change:

* The **asset index must be fetched before planning**, because `planInstall`
  needs the parsed index to emit one task per distinct blob. `planInstall`
  re-lists the index file itself as a task; the downloader skips it as already
  valid, so that duplication is deliberate rather than an oversight.
* **Extraction runs after the whole download**, so a cancelled install never
  leaves a half-unpacked natives directory. Extraction is itself atomic: build
  in a temp dir, then swap.
* **`inheritsFrom` parents are needed before planning.** Fetching a parent
  writes it to `versions/<parent>/<parent>.json`, which is exactly where
  `directoryResolver` looks — so inheritance resolution and later
  `verifyInstall`/launch read the same file, and a parent is fetched once.

## Files

| File | Role |
|---|---|
| `lib/core/net/cancellation.dart` | `CancelToken` — one flag, checked at every chunk and directory entry |
| `lib/core/install/extract.dart` | zip extraction, traversal guard, atomic + idempotent |
| `lib/core/install/asset_layout.dart` | `virtual` / `map_to_resources` materialization |
| `lib/core/install/verify.dart` | `verifyInstall` |
| `lib/core/install/version_installer.dart` | the pipeline + stage progress |

## Defects found while planning, fixed here

1. **`FileDownloader.download(concurrency:)` is ignored.** The body awaits each
   task in a `for` loop. A launcher installs ~3000 assets for a modern version;
   serially that is minutes of wall time that should be seconds, and the
   documented parameter says otherwise. Fixed by a bounded worker pool.
2. **`planInstall` cannot report natives progress.** `stages[InstallStage.natives]`
   is `putIfAbsent(_, () => 0)`, so natives always show 0 bytes while the
   archives are counted under `libraries` (they are in `graph.jars`). Stage
   progress for natives is therefore derived at install time from the
   `NativeArchive` list rather than trusted from the plan.
3. **No cancellation anywhere.** `_transfer` writes chunks in a loop with no
   exit path, so closing the app mid-install depends on the process dying. The
   cancel token also has to cover extraction, which is the step that leaves a
   mess.

## Verification

* Synthetic server fixture: a version chain with natives **and** a `virtual`
  asset index. No real version has both (1.12.2 has natives, 1.6.4 has
  `virtual`), so the merge is synthetic by necessity.
* Assert the final tree: file set, hashes, natives contents, virtual copies.
* Cancel mid-extraction ⇒ no natives dir.
* Traversal: an entry named `../../evil` must not escape.
* `@Tags(['network'])` run installs real 1.20.1 and asserts `verifyInstall` empty.
