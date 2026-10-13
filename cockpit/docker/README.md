# Reproducible Cockpit build environment (Docker)

The Cockpit desktop app builds against a host-installed **Zig 0.16.0** (the
`libghostty` native build hook pins it at comptime — 0.15.x and 0.17.x both
fail), plus **Flutter 3.47.5** and **Rust stable**. When the host Zig drifts
(e.g. Homebrew bumps to 0.17) `flutter test` stops working with a confusing
native-build error, and a checkout that built last month no longer builds.

This image pins all three so `flutter analyze`, `flutter test` and a Linux
desktop build run the same on any machine and in CI. Versions mirror
[`.github/workflows/cockpit-release.yml`](../../.github/workflows/cockpit-release.yml).

> Linux only. macOS and Windows desktop builds need their native host
> toolchains and cannot run in this container; use it for the analyzer, the
> test suite, and Linux artifacts.

## Use

From the repo root (needs Docker):

```bash
cockpit/docker/run.sh                 # flutter pub get && flutter test
cockpit/docker/run.sh flutter analyze # any command, run in cockpit/
cockpit/docker/run.sh bash            # interactive shell
```

or via make:

```bash
make -C cockpit/docker check          # pub get + analyze + test
make -C cockpit/docker test
make -C cockpit/docker shell
```

`run.sh` builds the image on first use (several minutes — it clones Flutter and
installs the toolchain), then bind-mounts the repo at `/work`.

`flutter analyze` is clean here and the logic/widget suite runs green, with one
caveat below.

## Platform-conditional tests

This is a Linux container; a few widget tests assert host-specific behaviour and
so differ from a macOS run (verified against unmodified `main`):

- `test/ui/window_menu_bar_test.dart` expects the macOS native menu bar (the
  widget is a `SizedBox` there by design) and fails on Linux, where the menu is
  drawn.
- `test/core/terminal/xterm/src/terminal_view_test.dart` `textScaler` cases are
  font-metric sensitive and depend on the host's text rendering.
- Conversely the xterm golden tests (`htop`/`color`) pass here but can show a
  sub-pixel diff on macOS.

None are toolchain problems. For gating changes, prefer `flutter analyze` plus
the directories relevant to your change (e.g. `flutter test test/core/terminal`)
over asserting the entire widget suite is green on every host.

## How the caching works

- The repo is bind-mounted read-write at `/work`; commands run in
  `/work/cockpit`.
- `/work/cockpit/.dart_tool` and the pub cache are **named volumes**, not the
  bind mount. That keeps the container's Linux build artifacts — above all the
  Zig-compiled `libghostty` dylib under `.dart_tool/hooks_runner` — separate
  from a host macOS checkout, and persists them across runs. The first `test`
  compiles ghostty with Zig (minutes); later runs reuse it.

Reset the caches with:

```bash
docker volume rm remote-pi-cockpit-dart-tool remote-pi-cockpit-pub-cache
```

## Pinned versions

| Tool | Version | Why |
|------|---------|-----|
| Flutter | 3.47.5 | `FLUTTER_VERSION` in the release workflow |
| Zig | 0.16.0 | `libghostty` build hook enforces `minimum_zig_version` 0.16.0 |
| Rust | stable (≥1.74) | `cockpit/cli` `rust-version` |
| Base | ubuntu:24.04 | matches the CI runner |

Bump them with Docker build args, e.g.
`docker build --build-arg FLUTTER_VERSION=3.48.0 cockpit/docker`. The Zig
sha256 sums in the `Dockerfile` are per-version and must be updated alongside
`ZIG_VERSION`.
