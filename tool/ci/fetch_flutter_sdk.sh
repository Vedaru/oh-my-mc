#!/usr/bin/env bash
# Download and extract the Flutter SDK, survivably.
#
#   fetch_flutter_sdk.sh <dest-root> [version]
#
# The tarball is 1.5 GB. A single `curl` of it from the runner failed at ~7
# minutes with "curl: (56) Recv failure: Connection reset by peer", which kills
# the whole job after the 4-minute apt install. So: try several mirrors, resume
# with `-C -` on every attempt (all of them support byte ranges), and verify the
# archive before extracting so a truncated download is an error here instead of
# a confusing CMake failure later.
set -euo pipefail

dest=${1:?destination root (the dir that should contain ./flutter)}
version=${2:-3.47.7}
archive=flutter_linux_${version}-stable.tar.xz

mirrors=(
  "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/$archive"
  "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$archive"
)

mkdir -p "$dest"
out="$dest/$archive"


fetch() {
  local url=$1 attempt rc size
  for attempt in 1 2 3 4 5; do
    echo "fetch attempt $attempt: $url"
    set +e
    # -C - resumes, which matters for a 1.5 GB file that already died once at
    # 7 minutes. curl refuses with exit 33 when a server answers 200 to a range
    # request; that is recoverable by starting over, so it is handled below
    # rather than treated as a dead mirror.
    curl -fSL --retry 5 --retry-delay 3 --retry-all-errors \
         --connect-timeout 30 --max-time 1800 \
         -C - -o "$out" "$url"
    rc=$?
    set -e
    [ "$rc" -eq 0 ] && return 0
    size=$(stat -c%s "$out" 2>/dev/null || echo 0)
    echo "attempt $attempt failed (curl exit $rc, $size bytes on disk)"
    if [ "$rc" -eq 33 ]; then
      echo "  server refused the range request; discarding partial file"
      rm -f "$out"
    fi
    sleep 5
  done
  return 1
}

fetch_all() {
  local ok=0 m
  for m in "${mirrors[@]}"; do
    if fetch "$m"; then ok=1; break; fi
    echo "mirror exhausted: $m"
  done
  [ "$ok" = 1 ] || { echo "could not download $archive from any mirror" >&2; exit 1; }
}

# Re-running must not re-download 1.5 GB: a file that already passes the archive
# integrity check is reused, anything else is fetched again.
if [ -f "$out" ] && xz -t "$out" 2>/dev/null; then
  echo "reusing verified $out ($(du -h "$out" | cut -f1))"
else
  fetch_all
fi

# A truncated xz decompresses partway and then errors; checking integrity now
# keeps the failure next to its cause.
xz -t "$out"
rm -rf "$dest/flutter"
tar -C "$dest" -xf "$out"
[ -x "$dest/flutter/bin/flutter" ] || { echo "extracted tree has no bin/flutter" >&2; exit 1; }
echo "flutter $version at $dest/flutter ($(du -sh "$out" | cut -f1) archive)"
