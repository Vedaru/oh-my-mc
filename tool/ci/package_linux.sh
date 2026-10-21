#!/usr/bin/env bash
# Stage a Linux release bundle as a relocatable tarball.
#
#   package_linux.sh <repo-root> <target>     target: linux-x64
#
# The Flutter bundle must be unpacked as a directory named `oh-my-mc`, not
# `bundle`, because that is the name a user sees after extracting.
set -euo pipefail

root=${1:?repo root}
target=${2:?target (linux-x64)}

case "$target" in
  linux-x64) arch=x64 ;;
  *) echo "unknown target: $target (only linux-x64 is shipped)" >&2; exit 64 ;;
esac

bundle="$root/build/linux/$arch/release/bundle"
[ -x "$bundle/oh_my_mc" ] || { echo "no executable at $bundle/oh_my_mc" >&2; exit 1; }

stage="$root/stage/oh-my-mc"
rm -rf "$root/stage"
mkdir -p "$stage" "$root/dist"
cp -a "$bundle/." "$stage/"

tar -czf "$root/dist/oh-my-mc-$target.tar.gz" -C "$root/stage" oh-my-mc
( cd "$root/dist" && sha256sum "oh-my-mc-$target.tar.gz" > "oh-my-mc-$target.tar.gz.sha256" )

# Prove the archive is usable rather than merely written: a tarball that omits
# the executable extracts "successfully" and then cannot be run.
# The listing is captured first because `tar | grep -q` under `pipefail` fails a
# good archive: grep exits on the first match, tar takes SIGPIPE, and the
# pipeline's status becomes non-zero despite the file being present.
listing=$(tar -tzf "$root/dist/oh-my-mc-$target.tar.gz")
printf '%s\n' "$listing" | grep -qx 'oh-my-mc/oh_my_mc' || {
  echo "archive does not contain oh-my-mc/oh_my_mc" >&2; exit 1; }
ls -l "$root/dist"
