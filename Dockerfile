FROM oven/bun:1-slim@sha256:1846adf22496bd711036aae8be147e57bdebbaea2e5264e3e0b5af1db187d9a4 AS bun
FROM denoland/deno:bin@sha256:b507583d3c68ba69f3ed2ce5969ae5b8b70f43421c781279c7aea06435263543 AS deno
FROM golang:latest@sha256:ec47ea3725fea0cc88f6de94919aef19f40f12fc1ec0e2d1b3426dbf15ecca04 AS golang
# Pin a release tag: ko's `latest` tag is rebuilt from every commit on its main branch.
FROM ghcr.io/ko-build/ko:v0.19.1@sha256:504badc509e58f193a6b9f5527ae8885f8d61b38187b2d9580e15c34d027a082 AS ko
FROM ghcr.io/dskiff/tko:bin@sha256:22d093ac97100fc318e74724ecdd1757ebdc46f5d50b406302cb49ceb354f848 AS tko
FROM ghcr.io/astral-sh/uv:latest@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv

FROM ghcr.io/actions/actions-runner:latest@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300 AS base

FROM ubuntu:noble@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5 AS builder
# Collect standalone binaries in one directory so they land in the final image as a single layer

ENV WORKDIR=/work
ENV BIN_OUT=/work/bin
ENV GO_DIR=/work/go

RUN mkdir -p ${WORKDIR} && \
    mkdir -p ${BIN_OUT}
WORKDIR ${WORKDIR}

COPY --from=bun     --chown=root:0 /usr/local/bin/bun /usr/local/bin/bunx ${BIN_OUT}/
COPY --from=deno    --chown=root:0 /deno ${BIN_OUT}/
COPY --from=ko      --chown=root:0 /ko-app/ko ${BIN_OUT}/
COPY --from=tko     --chown=root:0 /usr/local/bin/tko ${BIN_OUT}/
COPY --from=uv      --chown=root:0 /uv /uvx ${BIN_OUT}/

# Zig has no official container image, so fetch its release tarball the way
# https://ziglang.org/download/community-mirrors/ asks automated downloads to: try the
# community mirrors in random order (ziglang.org is a single host with no uptime guarantee,
# so it is only the last resort) and verify the minisign signature of whatever is served
# against the ZSF key, including the file name in its trusted comment (prevents downgrades).
FROM ubuntu:noble@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5 AS zig
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl minisign xz-utils && \
    rm -rf /var/lib/apt/lists/*
# renovate: datasource=forgejo-tags depName=ziglang/zig registryUrl=https://codeberg.org
ARG ZIG_VERSION=0.17.1
# ZSF release signing key, published at https://ziglang.org/download/
ARG ZIG_PUBKEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
RUN <<'EOF'
set -eu
tarball="zig-$(uname -m)-linux-${ZIG_VERSION}.tar.xz"
fetch() {
    curl -fsSL --retry 2 --connect-timeout 10 --speed-limit 102400 --speed-time 30 "$@"
}
cd /tmp
# An unreachable mirror list leaves only the ziglang.org fallback.
mirrors=$(fetch https://ziglang.org/download/community-mirrors.txt | shuf)
verified=
for base in ${mirrors} "https://ziglang.org/download/${ZIG_VERSION}"; do
    if fetch -o "${tarball}" "${base}/${tarball}?source=dockerfile" &&
        fetch -o "${tarball}.minisig" "${base}/${tarball}.minisig?source=dockerfile" &&
        comment=$(minisign -V -Q -P "${ZIG_PUBKEY}" -m "${tarball}") &&
        printf '%s\n' "${comment}" | tr '\t' '\n' | grep -qxF "file:${tarball}"; then
        echo "Verified ${tarball} from ${base}"
        verified=1
        break
    fi
    echo "No verified ${tarball} from ${base}, trying the next source" >&2
done
[ -n "${verified}" ] || { echo "No source served a verified ${tarball}" >&2; exit 1; }
mkdir -p /opt/zig
tar -xJf "${tarball}" -C /opt/zig --strip-components=1 --no-same-owner
rm -f "${tarball}" "${tarball}.minisig"
chmod -R g+r /opt/zig
find /opt/zig -type d -exec chmod g+x {} +
EOF

FROM ubuntu:noble@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5
# see: https://github.com/actions/runner/blob/main/images/Dockerfile

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

ENV BIN_DIR=/usr/bin
ENV UID=1001
ENV GID=0
ENV USERNAME="runner"
ENV BASE_DIR=/home/${USERNAME}_base
ENV RUNTIME_HOME_DIR=/home/${USERNAME}

# Add deps from images
COPY --from=golang  --chown=root:0 /usr/local/go /usr/local/
COPY --from=builder --chown=root:0 /work/bin/* ${BIN_DIR}/
# Zig locates its lib/ dir next to the executable, so it stays in one tree. Like Python, it
# lives outside ${BASE_DIR} and is read-only at runtime: Zig's caches go to ~/.cache/zig.
COPY --from=zig     --chown=root:0 /opt/zig /opt/zig

# Setup runner first to get access to installdependencies.sh
COPY --from=base --chown=root:0 /home/runner ${BASE_DIR}

# Install deps
RUN useradd -m $USERNAME -u $UID && \
    usermod -aG $GID $USERNAME && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    g++ \
    libfreetype6-dev \
    libssl-dev \
    musl-tools \
    zlib1g-dev \
    ca-certificates \
    curl \
    fontconfig \
    fonts-liberation \
    fonts-urw-base35 \
    git \
    git-lfs \
    jq \
    lsb-release \
    libicu-dev \
    pkg-config \
    unzip \
    wget \
    xz-utils \
    zstd \
    openjdk-21-jre-headless \
    libclang-dev \
    libasound2t64 \
    libatk-bridge2.0-0t64 \
    libatk1.0-0t64 \
    libatspi2.0-0t64 \
    libcairo2 \
    libcups2t64 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libglib2.0-0t64 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libx11-6 \
    libxcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 && \
    ${BASE_DIR}/bin/installdependencies.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install rustup and stable Rust toolchain as root into BASE_DIR
# NOTE: At runtime, /home/runner is mounted as a volume. Any content that needs to be
# available in /home/runner at runtime must be installed in ${BASE_DIR} (/home/runner_base)
# at build time. The entrypoint script copies everything from ${BASE_DIR} to /home/runner.
# Install as root with root:0 ownership and group read permissions so the runner user
# (member of group 0) can read from ${BASE_DIR} at runtime.
RUN export CARGO_HOME=${BASE_DIR}/.cargo && \
    export RUSTUP_HOME=${BASE_DIR}/.rustup && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path && \
    chmod -R g+r ${BASE_DIR}/.cargo ${BASE_DIR}/.rustup && \
    find ${BASE_DIR}/.cargo ${BASE_DIR}/.rustup -type d -exec chmod g+x {} +

# Install the latest stable Python via uv into a system location. Unlike rustup, this
# lives outside ${BASE_DIR} so it isn't copied into /home/runner on every start; it is
# read-only at runtime, so the stdlib is bytecode-compiled up front.
# uv links python3.x into /usr/local/bin; python/python3 are linked by hand rather than via
# `--default`, which is still a preview feature. UV_PYTHON_INSTALL_DIR is only set for this
# step: at runtime uv finds this interpreter on PATH, and `uv python install <version>`
# still writes to its default (writable) dir under /home/runner.
ARG PYTHON_INSTALL_DIR=/opt/python
RUN export UV_PYTHON_INSTALL_DIR=${PYTHON_INSTALL_DIR} UV_PYTHON_BIN_DIR=/usr/local/bin && \
    uv python install --compile-bytecode --no-cache && \
    python_bin=$(uv python find --managed-python) && \
    ln -s "${python_bin}" /usr/local/bin/python3 && \
    ln -s "${python_bin}" /usr/local/bin/python && \
    chmod -R g+r ${PYTHON_INSTALL_DIR} && \
    find ${PYTHON_INSTALL_DIR} -type d -exec chmod g+x {} +

# Inject a copy of ffmpeg
ENV FFMPEG_PREFIX=/opt/ffmpeg
ENV FFMPEG_VERSION=8.1
ENV PATH="${FFMPEG_PREFIX}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${FFMPEG_PREFIX}/lib"
ENV PKG_CONFIG_PATH="${FFMPEG_PREFIX}/lib/pkgconfig"

RUN mkdir -p "$FFMPEG_PREFIX" && \
    curl -sL "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-shared-${FFMPEG_VERSION}.tar.xz" \
    | tar -xJC "$FFMPEG_PREFIX" --strip-components=1 --no-same-owner && \
    sed -i "s|^prefix=.*|prefix=$FFMPEG_PREFIX|" "$FFMPEG_PREFIX"/lib/pkgconfig/*.pc && \
    chmod -R g+r "$FFMPEG_PREFIX" && \
    find "$FFMPEG_PREFIX" -type d -exec chmod g+x {} +

# Add runtime paths for golang + zig + builtin node + cargo + user-local bin (uv tools/pythons) to PATH
ENV PATH=/usr/local/go:/opt/zig:${RUNTIME_HOME_DIR}/externals/node20/bin:${RUNTIME_HOME_DIR}/.cargo/bin:${RUNTIME_HOME_DIR}/.local/bin:${PATH}

# Generate versions.yaml file (run as root to have write permissions to BASE_DIR)
RUN ["/bin/bash", "-c", "set -eo pipefail && \
    { \
    echo '# Build Tool Versions'; \
    echo \"bun: $(bun --version)\"; \
    echo \"deno: $(deno --version | head -n1 | awk '{print $2}')\"; \
    echo \"go: $(go version | awk '{print $3}' | sed 's/go//')\"; \
    echo \"java: $(java -version 2>&1 | head -n1 | awk -F'\"' '{print $2}' || echo 'unknown')\"; \
    echo \"ko: $(ko version 2>&1 | head -n1 | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+' || echo 'unknown')\"; \
    echo \"node: $(${BASE_DIR}/externals/node20/bin/node --version | sed 's/v//')\"; \
    echo \"rustc: $(CARGO_HOME=${BASE_DIR}/.cargo RUSTUP_HOME=${BASE_DIR}/.rustup ${BASE_DIR}/.cargo/bin/rustc --version | awk '{print $2}')\"; \
    echo \"cargo: $(CARGO_HOME=${BASE_DIR}/.cargo RUSTUP_HOME=${BASE_DIR}/.rustup ${BASE_DIR}/.cargo/bin/cargo --version | awk '{print $2}')\"; \
    echo \"tko: $(tko version)\"; \
    echo \"uv: $(uv --version | awk '{print $2}')\"; \
    echo \"python: $(python3 --version | awk '{print $2}')\"; \
    echo \"ffmpeg: $(pkg-config --modversion --static libavformat)\"; \
    echo \"zig: $(zig version)\"; \
    } | tee ${BASE_DIR}/versions.yaml && \
    chmod g+r ${BASE_DIR}/versions.yaml"]

USER $USERNAME

# Inject entrypoint
COPY --chown=root:0 ./entrypoint.sh ${BASE_DIR}/

WORKDIR ${RUNTIME_HOME_DIR}

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/home/runner_base/entrypoint.sh"]

