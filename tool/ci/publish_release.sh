#!/usr/bin/env bash
# Publish a rolling release for one target on this Forgejo instance.
#
#   publish_release.sh <repo-root> <target> <sha>
#
# The tag is a pointer, not a version: every green build replaces the previous
# release for that target, and it is marked prerelease because the tag moves.
# One release per target, so a linux-arm64 build can never overwrite the
# linux-x64 asset.
set -euo pipefail

root=${1:?repo root}
target=${2:?target}
sha=${3:?commit sha}

: "${FORGEJO_TOKEN:?FORGEJO_TOKEN is required}"
: "${FORGEJO_URL:?FORGEJO_URL is required}"

api="$FORGEJO_URL/api/v1/repos/${FORGEJO_REPOSITORY:-Vedaru/oh-my-mc}"
auth=(-H "Authorization: token $FORGEJO_TOKEN")
tag="rolling-$target"
dist="$root/dist"
short=$(printf '%s' "$sha" | cut -c1-12)

id_of() { python3 -c 'import json,sys;print(json.load(sys.stdin).get("id",""))'; }
api_get() { curl -sS "${auth[@]}" "$1"; }

# Delete-then-create keeps the tag pointing at the commit that just built.
rel=$(api_get "$api/releases/tags/$tag" || true)
rid=$(printf '%s' "$rel" | id_of)
if [ -n "${rid:-}" ]; then
  echo "replacing previous release id=$rid for $tag"
  curl -sS -X DELETE "${auth[@]}" "$api/releases/$rid" >/dev/null
fi
curl -sS -X DELETE "${auth[@]}" "$api/tags/$tag" >/dev/null || true

hostarch=$(uname -m)
flutter_version=$(cd "$root" && flutter --version 2>/dev/null | head -1 || echo unknown)

body=$(python3 - "$tag" "$sha" "$hostarch" "$flutter_version" "$dist" <<'PY'
import hashlib, json, os, sys

tag, sha, hostarch, flutter_version, dist = sys.argv[1:6]
rows = []
for name in sorted(os.listdir(dist)):
    if name.endswith('.sha256') or not os.path.isfile(os.path.join(dist, name)):
        continue
    path = os.path.join(dist, name)
    with open(path, 'rb') as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()
    rows.append('| `%s` | `%s` |' % (name, digest))

body = [
    'Rolling build of `%s` - the last commit on the branch that built and passed the gate.' % sha[:12],
    '',
    '- commit: `%s`' % sha,
    '- artifact: `%s`' % tag,
    '- built on: `%s` (native, not cross-compiled)' % hostarch,
    '- flutter: %s' % flutter_version,
    '',
    '| asset | sha256 |',
    '| -- | -- |',
] + rows
print(json.dumps({'tag_name': tag,
                  'target_commitish': sha,
                  'name': 'oh my mc - %s (rolling)' % tag.replace('rolling-', ''),
                  'body': '\n'.join(body),
                  'prerelease': True,
                  'draft': False}))
PY
)

created=$(curl -sS -X POST "${auth[@]}" -H "Content-Type: application/json" -d "$body" "$api/releases")
rid=$(printf '%s' "$created" | id_of)
[ -n "${rid:-}" ] || { echo "release creation failed: $created" >&2; exit 1; }
echo "created release id=$rid tag=$tag"

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
    'import json,sys;print(" ".join(a.get("name","") for a in (json.load(sys.stdin).get("assets") or [])))')
echo "assets attached: $attached"
case " $attached " in
  *" oh-my-mc-$target.tar.gz "*) echo "published $tag" ;;
  *) echo "the tarball is not attached; refusing to call this a release" >&2; exit 1 ;;
esac
