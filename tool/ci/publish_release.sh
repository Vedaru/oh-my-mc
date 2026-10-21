#!/usr/bin/env bash
# Publish the single rolling release on this Forgejo instance.
#
#   publish_release.sh <repo-root> <target> <sha>     target: linux-x64 | linux-arm64
#
# There is ONE release, and it holds one asset per target. Two releases (one per
# architecture) meant two independent "latest" pointers, and they drifted: the
# x64 release sat on an older commit than arm64, so "the rolling build" named two
# different commits depending on which one a user opened.
#
# This instance cannot pass files between jobs (`actions/upload-artifact` is
# unavailable, since the default action source is github.com and unreachable
# here), so each job uploads into the shared release itself:
#
#   1. the tag is repointed at the commit that just built;
#   2. the release is created if missing - or reset if it belongs to an older
#      commit - and only ever holds assets produced by that commit;
#   3. this target's assets are deleted and re-uploaded;
#   4. assets for the *other* target from the same commit are left alone.
#
# So both jobs converge on one release, and a job can never wipe the other
# architecture's asset. Losing that isolation was the whole reason the two
# releases existed; it is preserved here by filtering on the commit marker
# instead of on the release identity.
set -euo pipefail

root=${1:?repo root}
target=${2:?target}
sha=${3:?commit sha}

: "${FORGEJO_TOKEN:?FORGEJO_TOKEN is required}"
: "${FORGEJO_URL:?FORGEJO_URL is required}"

api="$FORGEJO_URL/api/v1/repos/${FORGEJO_REPOSITORY:-Vedaru/oh-my-mc}"
auth=(-H "Authorization: token $FORGEJO_TOKEN")
tag="rolling"
dist="$root/dist"
short=$(printf '%s' "$sha" | cut -c1-12)

api_get() { curl -sS "${auth[@]}" "$1"; }

# Repoint the tag. PATCH moves an existing tag; POST creates a missing one.
# Neither is fatal on its own: a tag that is already correct answers 422, and a
# release cannot be created against a tag that does not exist, so the state is
# re-read afterwards rather than trusted from these responses.
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "${auth[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"sha\":\"$sha\",\"force\":true}" "$api/tags/$tag")
if [ "$code" != 200 ]; then
  curl -sS -o /dev/null -X POST "${auth[@]}" -H "Content-Type: application/json" \
      -d "{\"tag_name\":\"$tag\",\"target\":\"$sha\"}" "$api/tags" || true
fi

rel=$(api_get "$api/releases/tags/$tag" 2>/dev/null || true)
rid=$(printf '%s' "$rel" | python3 -c \
    'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")')
belongs=$(printf '%s' "$rel" | python3 -c \
    'import json,sys
try: print(json.load(sys.stdin).get("target_commitish",""))
except Exception: print("")')

if [ -n "${rid:-}" ] && [ "$belongs" != "$sha" ]; then
  echo "release $rid belongs to ${belongs:0:12}, not ${short}; resetting it"
  curl -sS -X DELETE "${auth[@]}" "$api/releases/$rid" >/dev/null
  rid=""
fi

hostarch=$(uname -m)
flutter_version=$(cd "$root" && flutter --version 2>/dev/null | head -1 || echo unknown)

if [ -z "${rid:-}" ]; then
  body=$(python3 - "$sha" "$hostarch" "$flutter_version" "$dist" <<'PY'
import hashlib, json, os, sys

sha, hostarch, flutter_version, dist = sys.argv[1:5]
rows = []
if os.path.isdir(dist):
    for name in sorted(os.listdir(dist)):
        if name.endswith('.sha256') or not os.path.isfile(os.path.join(dist, name)):
            continue
        with open(os.path.join(dist, name), 'rb') as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        rows.append('| `%s` | `%s` |' % (name, digest))

body = [
    'Rolling build of `%s` - the last commit that built and passed the gate.' % sha[:12],
    '',
    '- commit: `%s`' % sha,
    '- flutter: %s' % flutter_version,
    '- built natively on `%s` (not cross-compiled)' % hostarch,
    '',
    'One asset per Linux architecture. Both are built from the commit above;',
    'the two CI jobs each upload their own target into this release.',
    '',
    '| asset | sha256 |',
    '| -- | -- |',
] + rows
print(json.dumps({'tag_name': 'rolling',
                  'target_commitish': sha,
                  'name': 'oh my mc - rolling',
                  'body': '\n'.join(body),
                  'prerelease': True,
                  'draft': False}))
PY
)
  created=$(curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" -d "$body" "$api/releases")
  rid=$(printf '%s' "$created" | python3 -c \
      'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")')
  if [ -z "${rid:-}" ]; then
    # Both jobs reach this point concurrently, and the loser of that race gets
    # an error rather than a release. Re-read instead of failing: the winner's
    # release is the one we wanted anyway, since both are building this commit.
    echo "create answered: $created"
    echo "another job may have created it first; re-reading $tag"
    rel=$(api_get "$api/releases/tags/$tag" 2>/dev/null || true)
    rid=$(printf '%s' "$rel" | python3 -c \
        'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")')
    [ -n "${rid:-}" ] || { echo "release creation failed: $created" >&2; exit 1; }
    echo "adopted release id=$rid"
  else
    echo "created release id=$rid for $short"
  fi
else
  echo "reusing release id=$rid for $short"
fi

# Drop only this target's previous assets. The other architecture's assets stay,
# which is what makes two independent jobs able to share one release.
existing=$(api_get "$api/releases/$rid/assets")
printf '%s' "$existing" | python3 -c \
    'import json,sys
try: assets=json.load(sys.stdin) or []
except Exception: assets=[]
for a in assets: print(a.get("id",""), a.get("name",""))' |
while read -r aid aname; do
  [ -n "${aname:-}" ] || continue
  case "$aname" in
    *"$target"*) echo "removing stale $aname"; curl -sS -X DELETE "${auth[@]}" "$api/releases/$rid/assets/$aid" >/dev/null ;;
  esac
done

shopt -s nullglob
files=("$dist"/oh-my-mc-"$target".tar.gz "$dist"/oh-my-mc-"$target".tar.gz.sha256)
shopt -u nullglob
[ ${#files[@]} -gt 0 ] || { echo "nothing to upload in $dist" >&2; exit 1; }

for f in "${files[@]}"; do
  name=$(basename "$f")
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${auth[@]}" \
      -F "attachment=@$f" "$api/releases/$rid/assets?name=$name")
  echo "uploaded $name -> HTTP $code"
  [ "$code" = 201 ] || { echo "asset upload for $name failed" >&2; exit 1; }
done

# A 201 that attached nothing looks exactly like success, so read it back.
final=$(api_get "$api/releases/$rid")
attached=$(printf '%s' "$final" | python3 -c \
    'import json,sys
try: print(" ".join(a.get("name","") for a in (json.load(sys.stdin).get("assets") or [])))
except Exception: print("")')
echo "assets attached: $attached"
case " $attached " in
  *" oh-my-mc-$target.tar.gz "*) echo "published $tag with $target" ;;
  *) echo "the tarball is not attached; refusing to call this a release" >&2; exit 1 ;;
esac
