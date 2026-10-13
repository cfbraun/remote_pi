#!/usr/bin/env bash
# Build the pinned Cockpit build image (if needed) and run a command inside it
# against the repo working tree.
#
#   ./run.sh                      # flutter pub get && flutter test
#   ./run.sh flutter analyze      # run any command in cockpit/
#   ./run.sh bash                 # interactive shell
#
# The repo is bind-mounted at /work. .dart_tool and the pub cache live in named
# volumes so the container keeps its own Linux build artifacts (the native
# libghostty dylib especially) separate from a host macOS checkout and across
# runs — the first run compiles ghostty with Zig, later runs reuse it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)" # .../remote_pi
image="${COCKPIT_BUILD_IMAGE:-remote-pi-cockpit-build:flutter3.47.5-zig0.16.0}"

docker build -t "$image" "$here"

tty_flags=(-i)
[ -t 0 ] && tty_flags=(-i -t)

if [ "$#" -eq 0 ]; then
    cmd="flutter pub get && flutter test"
else
    cmd="$*"
fi

exec docker run --rm "${tty_flags[@]}" \
    -v "$repo_root":/work \
    -v remote-pi-cockpit-dart-tool:/work/cockpit/.dart_tool \
    -v remote-pi-cockpit-pub-cache:/opt/pub-cache \
    -w /work/cockpit \
    "$image" \
    bash -lc "$cmd"
