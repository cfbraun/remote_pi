# Reproducible Linux build/test environment for the Cockpit Flutter desktop app.
#
# Pins the exact toolchain the app needs so `flutter analyze` / `flutter test`
# (and a Linux desktop build) run the same way on any machine and in CI — the
# cockpit build otherwise depends on a host-installed Zig 0.16.0, which silently
# breaks when the host Zig drifts (e.g. Homebrew bumping to 0.17).
#
# Versions mirror .github/workflows/cockpit-release.yml (Flutter 3.47.5, Zig
# 0.16.0, Rust stable) and the Linux apt deps of its desktop build job.
#
# Build (from this directory):
#   docker build -t remote-pi-cockpit-build .
# or use ./run.sh / the Makefile in this directory, which wire up the repo mount
# and caches for you.
FROM ubuntu:24.04

ARG FLUTTER_VERSION=3.47.5
ARG ZIG_VERSION=0.16.0
# Provided automatically by BuildKit: "amd64" or "arm64".
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    PUB_CACHE=/opt/pub-cache \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/zig:/root/.cargo/bin:/usr/local/bin:/usr/bin:/bin

# System dependencies: Flutter Linux desktop (gtk/mpv/secret), the libghostty
# native build (clang/cmake/ninja/pkg-config), and packaging (rpm). Mirrors the
# `apt-get install` in the release workflow's Linux job.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        clang \
        cmake \
        curl \
        git \
        libgtk-3-dev \
        libmpv-dev \
        libsecret-1-dev \
        ninja-build \
        pkg-config \
        rpm \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Zig — the libghostty build hook (hooks.user_defines.libghostty.source:
# compile) enforces minimum_zig_version 0.16.0 at comptime; 0.15.x and 0.17.x
# both fail. Pinned by sha256 per arch.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) zarch=x86_64;  zsha=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00 ;; \
        arm64) zarch=aarch64; zsha=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://ziglang.org/download/${ZIG_VERSION}/zig-${zarch}-linux-${ZIG_VERSION}.tar.xz"; \
    curl -fsSL -o /tmp/zig.tar.xz "$url"; \
    echo "${zsha}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/zig; \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    rm /tmp/zig.tar.xz; \
    zig version

# Rust via rustup (stable; cockpit/cli declares rust-version = "1.74").
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain stable \
    && cargo --version

# Flutter at the pinned tag, with the Linux desktop toolchain precached.
# safe.directory '*' lets Flutter run git inside both /opt/flutter and the
# bind-mounted repo (owned by the host user, not root).
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git /opt/flutter \
    && git config --global --add safe.directory '*' \
    && flutter --version \
    && flutter config --enable-linux-desktop \
    && flutter precache --linux --universal

WORKDIR /work/cockpit
