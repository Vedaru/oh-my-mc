#!/usr/bin/env bash
# Publish the single rolling release on this Forgejo instance.
#
#   publish_release.sh <repo-root> <target> <sha>     target: linux-x64 | linux-arm64
#
# There is ONE release, tagged `rolling`, holding one asset per target. Two
# releases (one per architecture) meant two independent "latest" pointers, and
# they had drifted: the x64 one named an older commit than arm64, so "the rolling
# build" named two different commits depending on which release a user opened.
#
# This instance cannot pass files between jobs (`actions/upload-artifact` is
# unavailable - the default action source is github.com and unreachable here), so
# each job uploads into the shared release itself. The two jobs therefore have to
# cooperate through the API alone:
#
#   1. never delete the release, and never delete another target's asset. A job
#      that fails after the other succeeded must not remove the good artifact,
#      or the release ends up serving one architecture for a commit built for
#      two. This is not hypothetical: the first version of this script reset a
#      release whose commit did not match, and an arm64 job dying in one second
#      took the x64 asset with it.
#   2. replace only assets whose name contains this target.
#   3. put the commit in every asset's name, so an asset left behind by an older
#      commit is visible in the filename rather than silently passed off as
#      current. A rolling release's download links are allowed to move; a
#      mislabelled binary is not.
#   4. rebuild the body from the assets actually attached, so it cannot claim a
#      set that is not there.
set -euo pipefail

root=${1:?repo root}
target=${2:?target (linux-x64|linux-arm64)}
sha=${3:?commit sha}

: "${FORGEJO_TOKEN:?FORGEJO_TOKEN is required}"
: "${FORGEJO_URL:?FORGEJO_URL is required}"

api="$FORGEJO_URL/api/v1/repos/${FORGEJO_REPOSITORY:-Vedaru/oh-my-mc}"
auth=(-H "Authorization: token $FORGEJO_TOKEN")
tag="rolling"
dist="$root/dist"
short=$(printf '%s' "$sha" | cut -c1-12)

api_get() { curl -sS "${auth[@]}" "$1"; }
rid_of() {
  printf '%s' "$1" | python3 -c \
      'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")'
}

# The checksum file names its payload, so it is regenerated for the stamped name
# rather than copied from the unstamped one.
src="$dist/oh-my-mc-$target.tar.gz"
[ -f "$src" ] || { echo "no tarball at $src" >&2; exit 1; }
stamped="$dist/oh-my-mc-$target-$short.tar.gz"
cp "$src" "$stamped"
( cd "$dist" && sha256sum "oh-my-mc-$target-$short.tar.gz" > "oh-my-mc-$target-$short.tar.gz.sha256" )

# Point the tag at this commit. PATCH moves an existing tag, POST creates one; a
# tag already at this commit answers 422, which is not a failure.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "${auth[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"sha\":\"$sha\",\"force\":true}" "$api/tags/$tag")
if [ "$code" != 200 ]; then
  curl -sS -o /dev/null -X POST "${auth[@]}" -H "Content-Type: application/json" \
      -d "{\"tag_name\":\"$tag\",\"target\":\"$sha\"}" "$api/tags" || true
fi

rid=$(rid_of "$(api_get "$api/releases/tags/$tag" 2>/dev/null || true)")
if [ -z "${rid:-}" ]; then
  created=$(curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" \
      -d "{\"tag_name\":\"$tag\",\"target_commitish\":\"$sha\",\"name\":\"oh my mc - rolling\",\"body\":\"rolling build\",\"prerelease\":true,\"draft\":false}" \
      "$api/releases")
  rid=$(rid_of "$created")
  if [ -z "${rid:-}" ]; then
    # The other job can reach this line at the same moment; the loser of that
    # race adopts the winner's release, which is the one we wanted anyway.
    echo "create answered: $created"
    rid=$(rid_of "$(api_get "$api/releases/tags/$tag" 2>/dev/null || true)")
    [ -n "${rid:-}" ] || { echo "release creation failed: $created" >&2; exit 1; }
    echo "adopted existing release id=$rid"
  else
    echo "created release id=$rid"
  fi
else
  echo "reusing release id=$rid"
fi

# Remove this target's assets only; every other asset is left exactly as found.
api_get "$api/releases/$rid/assets" | python3 -c \
    'import json,sys
try: assets=json.load(sys.stdin) or []
except Exception: assets=[]
for a in assets: print(a.get("id",""), a.get("name",""))' |
while read -r aid aname; do
  [ -n "${aname:-}" ] || continue
  case "$aname" in
    *"$target"*) echo "removing previous $aname"
                 curl -sS -X DELETE "${auth[@]}" "$api/releases/$rid/assets/$aid" >/dev/null ;;
  esac
done

for f in "$stamped" "$stamped.sha256"; do
  name=$(basename "$f")
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${auth[@]}" \
      -F "attachment=@$f" "$api/releases/$rid/assets?name=$name")
  echo "uploaded $name -> HTTP $code"
  [ "$code" = 201 ] || { echo "asset upload for $name failed" >&2; exit 1; }
done

# A 201 that attached nothing looks exactly like success, so the attachment is
# read back and looked for by name.
attached=$(api_get "$api/releases/$rid/assets" | python3 -c \
    'import json,sys
try: assets=json.load(sys.stdin) or []
except Exception: assets=[]
for a in assets: print(a.get("name",""))')
echo "assets attached:"; printf '%s\n' "$attached" | sed 's/^/  /'
case "$attached" in
  *"oh-my-mc-$target-$short.tar.gz"*) ;;
  *) echo "the tarball is not attached; refusing to call this a release" >&2; exit 1 ;;
esac

body=$(printf '%s\n' "$attached" | python3 -c '
import re, sys
# A name that does not carry a commit is reported as such. Guessing a commit out
# of an arbitrary name is worse than admitting it is unknown: splitting on "-"
# turns "oh-my-mc-linux-x64.tar.gz" into a commit called "x64".
stamped = re.compile(r"^oh-my-mc-(linux-x64|linux-arm64)-([0-9a-f]{7,40})\.tar\.gz$")
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
print("\n".join(out))')

payload=$(python3 -c '
import json, sys
body = sys.argv[1]
print(json.dumps({"body": body, "prerelease": True, "name": "oh my mc - rolling"}))' "$body")
curl -sS -o /dev/null -X PATCH "${auth[@]}" -H "Content-Type: application/json" \
    -d "$payload" "$api/releases/$rid" \
  || echo "warning: could not update the release body" >&2

echo "published $tag for $target at ${short}"
