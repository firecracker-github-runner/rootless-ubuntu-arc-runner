FROM oven/bun:1-slim@sha256:478281fdd196871c7e51ba6a820b7803a8ae97042ec86cdbc2e1c6b6626442d9 AS bun
FROM denoland/deno:bin@sha256:65d09bbcd1afeecae9651b1ec40d4f921fb68069a5549a1712bb82fcdc6efc57 AS deno
FROM golang:latest@sha256:c42e4d75186af6a44eb4159dcfac758ef1c05a7011a0052fe8a8df016d8e8fb9 AS golang
FROM ghcr.io/dskiff/tko:bin@sha256:f3b1fb296f6793e9e69c43c68a7a99a118f32493e1ae747fda23122d0c1e46ea AS tko

FROM ghcr.io/actions/actions-runner:latest@sha256:1ad983536759ceec39ed75a2c8f007ca8c37b66eee35ed86f13623b29a4db97d AS base

FROM ubuntu:noble@sha256:0d39fcc8335d6d74d5502f6df2d30119ff4790ebbb60b364818d5112d9e3e932 AS builder
# Grab anything we can't get via other means

# apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/*
RUN apt-get update && apt-get install -y curl jq

ENV WORKDIR=/work
ENV BIN_OUT=/work/bin
ENV GO_DIR=/work/go

RUN mkdir -p ${WORKDIR} && \
    mkdir -p ${BIN_OUT}
WORKDIR ${WORKDIR}

COPY --from=bun     --chown=root:0 /usr/local/bin/bun /usr/local/bin/bunx ${BIN_OUT}/
COPY --from=deno    --chown=root:0 /deno ${BIN_OUT}/
COPY --from=tko     --chown=root:0 /usr/local/bin/tko ${BIN_OUT}/

COPY --chown=root:0 build-bin.sh ${WORKDIR}/
RUN cd ${WORKDIR} && \
    ./build-bin.sh

FROM ubuntu:noble@sha256:0d39fcc8335d6d74d5502f6df2d30119ff4790ebbb60b364818d5112d9e3e932
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
    libclang-dev && \
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

# Inject a copy of ffmpeg
ENV FFMPEG_PREFIX=/opt/ffmpeg
ENV FFMPEG_VERSION=8.0
ENV PATH="${FFMPEG_PREFIX}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${FFMPEG_PREFIX}/lib"
ENV PKG_CONFIG_PATH="${FFMPEG_PREFIX}/lib/pkgconfig"

RUN mkdir -p "$FFMPEG_PREFIX" && \
    curl -sL "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-shared-${FFMPEG_VERSION}.tar.xz" \
    | tar -xJC "$FFMPEG_PREFIX" --strip-components=1 --no-same-owner && \
    sed -i "s|^prefix=.*|prefix=$FFMPEG_PREFIX|" "$FFMPEG_PREFIX"/lib/pkgconfig/*.pc && \
    chmod -R g+r "$FFMPEG_PREFIX" && \
    find "$FFMPEG_PREFIX" -type d -exec chmod g+x {} +

# Add runtime paths for golang + builtin node + cargo to PATH
ENV PATH=/usr/local/go:${RUNTIME_HOME_DIR}/externals/node20/bin:${RUNTIME_HOME_DIR}/.cargo/bin:${PATH}

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
    echo \"ffmpeg: $(pkg-config --modversion --static libavformat)\"; \
    } | tee ${BASE_DIR}/versions.yaml && \
    chmod g+r ${BASE_DIR}/versions.yaml"]

USER $USERNAME

# Inject entrypoint
COPY --chown=root:0 ./entrypoint.sh ${BASE_DIR}/

WORKDIR ${RUNTIME_HOME_DIR}

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/home/runner_base/entrypoint.sh"]

