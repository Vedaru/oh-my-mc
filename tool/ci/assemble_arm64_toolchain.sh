#!/usr/bin/env bash
# Turn a stock x64 Flutter tarball into a working aarch64 Flutter toolchain.
#
#   assemble_arm64_toolchain.sh <dest-root> [version]
#
# Upstream publishes NO arm64 Linux SDK - releases_linux.json contains zero
# arm64 archives - so there is nothing to download that runs on this host. The
# working arrangement, recorded in AGENTS.md and reproduced here, is:
#
#   1. extract the x64 tarball (it is the only tarball there is);
#   2. swap its x64 Dart SDK for a native arm64 one, keeping the x64 copy aside;
#   3. put the linux-arm64 engine artifacts in place by hand, filling the two
#      gaps upstream leaves (`const_finder.dart.snapshot` is arch-independent
#      kernel code, so the x64 copy is valid; `font-subset` has no arm64 build at
#      all, which is why the build must pass --no-tree-shake-icons);
#   4. delete the prebuilt flutter_tools snapshot so the tool recompiles it
#      natively on first run - an x64 snapshot dies with "Snapshot not
#      compatible with the current VM configuration".
#
# The Dart patch version must match the engine exactly: 3.13.6 aborts with
# "Invalid SDK hash", 3.13.5 is correct for Flutter 3.47.7. So the version is
# read from the tarball rather than hardcoded.
set -euo pipefail

dest=${1:?destination root}
version=${2:-3.47.7}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root="$dest/flutter"

bash "$script_dir/fetch_flutter_sdk.sh" "$dest" "$version"

dartver=$(cat "$root/bin/cache/dart-sdk/version")
engine=$(cat "$root/bin/internal/engine.version")
echo "dart=$dartver engine=$engine"

# Keep the x64 SDK: the tool consults it for host-side lookups, and AGENTS.md
# records that the reverse arrangement is what breaks.
x64dir="$root/bin/cache/dart-sdk-x64"
if [ ! -d "$x64dir" ] && [ ! -L "$root/bin/cache/dart-sdk" ]; then
  mv "$root/bin/cache/dart-sdk" "$x64dir"
fi
rm -f "$root/bin/cache/dart-sdk"
rm -rf "$dest/nativedart"
mkdir -p "$dest/nativedart"
curl -fSL --retry 5 --retry-all-errors --connect-timeout 30 -o "$dest/dartsdk.zip" \
  "https://storage.googleapis.com/dart-archive/channels/stable/release/$dartver/sdk/dartsdk-linux-arm64-release.zip"
unzip -q -o "$dest/dartsdk.zip" -d "$dest/nativedart"
ln -sfn "$dest/nativedart/dart-sdk" "$root/bin/cache/dart-sdk"
"$root/bin/cache/dart-sdk/bin/dart" --version

arts="$root/bin/cache/artifacts/engine"
mkdir -p "$arts/linux-arm64" "$arts/linux-x64"
base="https://storage.googleapis.com/flutter_infra_release/flutter/$engine"
curl -fSL --retry 5 --retry-all-errors --connect-timeout 30 -o "$dest/a-arm64.zip" "$base/linux-arm64/artifacts.zip"
curl -fSL --retry 5 --retry-all-errors --connect-timeout 30 -o "$dest/a-x64.zip"   "$base/linux-x64/artifacts.zip"
unzip -q -o "$dest/a-arm64.zip" -d "$arts/linux-arm64"
unzip -q -o "$dest/a-x64.zip"   -d "$arts/linux-x64"

# Arch-independent kernel blob; the arm64 zip omits it.
if [ ! -f "$arts/linux-arm64/const_finder.dart.snapshot" ]; then
  cp "$arts/linux-x64/const_finder.dart.snapshot" "$arts/linux-arm64/"
fi
printf '%s' "$engine" > "$arts/engine.stamp"

# Force a native rebuild of the tool snapshot.
rm -f "$root/bin/cache/flutter_tools.snapshot" \
      "$root/bin/cache/flutter_tools.stamp" \
      "$root/bin/cache/flutter_tools.snapshot.json" \
      "$root/bin/cache/lockfile"

git config --global --add safe.directory "$root" 2>/dev/null || true
"$root/bin/flutter" --version
echo "arm64 flutter ready at $root"
