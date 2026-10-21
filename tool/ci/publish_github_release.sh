#!/usr/bin/env bash
# Publish the single rolling release on GitHub.
#
#   publish_github_release.sh <repo-root> <target> <sha>     target: windows-x64 | macos-arm64
#
# The GitHub mirror builds windows-x64 and macos-arm64 into workflow artifacts,
# which expire after 14 days and require a login to fetch. Users could therefore
# not download two of the three shipped targets at all: the `rolling` release only
# existed on the Forgejo instance, and only Linux assets were ever attached.
# This attaches the two GitHub-built targets to a GitHub release, so each platform
# has a download next to the platform users are on. Linux stays on Forgejo (its
# builds are Linux jobs there); each release's body links the other.
#
# Same rules as the Forgejo publisher, for the same reasons:
#   * replace only assets for this target, so the two matrix jobs (which run in
#     parallel and cannot pass files to each other) never delete each other's work;
#   * put the commit in the asset name, so a stale asset is visibly stale;
#   * rebuild the body from the assets actually attached, and prove the upload
#     landed by reading it back - a 201 that attached nothing looks like success.
set -euo pipefail

root=${1:?repo root}
target=${2:?target (windows-x64|macos-arm64)}
sha=${3:?commit sha}

: "${GH_TOKEN:?GH_TOKEN is required}"

api="https://api.github.com/repos/${GITHUB_REPOSITORY:-Vedaru/oh-my-mc}"
# Asset uploads live on a different host: the REST path answers 404 there.
upload_api="https://uploads.github.com/repos/${GITHUB_REPOSITORY:-Vedaru/oh-my-mc}"
auth=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json")
tag="rolling"
dist="$root/dist"
short=$(printf '%s' "$sha" | cut -c1-12)

# The local artifact extension differs per target; everything else is shared.
case "$target" in
  windows-x64|macos-arm64) ext=zip ;;
  *) echo "unknown target: $target" >&2; exit 64 ;;
esac

api_get() { curl -sS "${auth[@]}" "$1"; }
id_of() {
  printf '%s' "$1" | python3 -c \
      'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")'
}

src="$dist/oh-my-mc-$target.$ext"
[ -f "$src" ] || { echo "no artifact at $src" >&2; exit 1; }
stamped="$dist/oh-my-mc-$target-$short.$ext"
cp "$src" "$stamped"
# macOS has no `sha256sum` (it is GNU coreutils), so hash through python3, which
# every runner has. Written as `<hash>  <name>` to match the Linux assets.
( cd "$dist" && python3 -c '
import hashlib, sys
name = sys.argv[1]
h = hashlib.sha256(open(name, "rb").read()).hexdigest()
open(name + ".sha256", "w").write("%s  %s\n" % (h, name))' "oh-my-mc-$target-$short.$ext" )

# Point the tag at this commit. A tag already at this commit answers 422, which is
# not a failure.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "${auth[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"sha\":\"$sha\",\"force\":true}" "$api/git/refs/tags/$tag")
if [ "$code" != 200 ]; then
  curl -sS -o /dev/null -X POST "${auth[@]}" -H "Content-Type: application/json" \
      -d "{\"ref\":\"refs/tags/$tag\",\"sha\":\"$sha\"}" "$api/git/refs" || true
fi

rid=$(id_of "$(api_get "$api/releases/tags/$tag" 2>/dev/null || true)")
if [ -z "${rid:-}" ]; then
  created=$(curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" \
      -d "{\"tag_name\":\"$tag\",\"target_commitish\":\"$sha\",\"name\":\"oh my mc - rolling\",\"body\":\"rolling build\",\"prerelease\":true,\"draft\":false}" \
      "$api/releases")
  rid=$(id_of "$created")
  if [ -z "${rid:-}" ]; then
    # The other matrix job can reach this line at the same moment; the loser
    # adopts the winner's release, which is the one we wanted anyway.
    rid=$(id_of "$(api_get "$api/releases/tags/$tag" 2>/dev/null || true)")
    [ -n "${rid:-}" ] || { echo "release creation failed: $created" >&2; exit 1; }
    echo "adopted existing release id=$rid"
  else
    echo "created release id=$rid"
  fi
else
  echo "reusing release id=$rid"
fi

api_get "$api/releases/$rid/assets" | python3 -c \
    'import json,sys
try: assets=json.load(sys.stdin) or []
except Exception: assets=[]
for a in assets: print(a.get("id",""), a.get("name",""))' |
while read -r aid aname; do
  [ -n "${aname:-}" ] || continue
  case "$aname" in
    *"$target"*) echo "removing previous $aname"
                 curl -sS -o /dev/null -X DELETE "${auth[@]}" "$api/releases/assets/$aid" ;;
  esac
done

for f in "$stamped" "$stamped.sha256"; do
  name=$(basename "$f")
  # `--upload-file` cannot set the asset name, so the name goes in the URL.
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${auth[@]}" \
      -H "Content-Type: application/octet-stream" --data-binary "@$f" \
      "$upload_api/releases/$rid/assets?name=$name")
  echo "uploaded $name -> HTTP $code"
  [ "$code" = 201 ] || { echo "asset upload for $name failed" >&2; exit 1; }
done

attached=$(api_get "$api/releases/$rid/assets" | python3 -c \
    'import json,sys
try: assets=json.load(sys.stdin) or []
except Exception: assets=[]
for a in assets: print(a.get("name",""))')
echo "assets attached:"; printf '%s\n' "$attached" | sed 's/^/  /'
case "$attached" in
  *"oh-my-mc-$target-$short.$ext"*) ;;
  *) echo "the artifact is not attached; refusing to call this a release" >&2; exit 1 ;;
esac

body=$(printf '%s\n' "$attached" | python3 -c '
import re, sys
stamped = re.compile(r"^oh-my-mc-(windows-x64|macos-arm64|linux-x64)-([0-9a-f]{7,40})\.(zip|tar\.gz)$")
rows = []
for name in sys.stdin.read().splitlines():
    if not name or name.endswith(".sha256"):
        continue
    m = stamped.match(name)
    rows.append((name,
                 m.group(1) if m else "unknown",
                 m.group(2) if m else "unversioned"))
out = ["Rolling build. Each asset names the commit it was built from.", "",
       "| asset | target | commit |", "| -- | -- | -- |"]
for name, target, commit in sorted(rows, key=lambda r: r[1]):
    out.append("| `%s` | %s | `%s` |" % (name, target, commit))
out += ["", "Linux builds (linux-x64) are attached to the release on the main "
        "repository: https://git.vedaru.cn/Vedaru/oh-my-mc/releases/tag/rolling"]
print("\n".join(out))')

payload=$(python3 -c '
import json, sys
print(json.dumps({"body": sys.argv[1], "prerelease": True, "name": "oh my mc - rolling"}))' "$body")
curl -sS -o /dev/null -X PATCH "${auth[@]}" -H "Content-Type: application/json" \
    -d "$payload" "$api/releases/$rid" \
  || echo "warning: could not update the release body" >&2

echo "published rolling for $target at $short"
