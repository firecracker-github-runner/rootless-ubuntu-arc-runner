FROM oven/bun:1-slim@sha256:5d5863f35ad9b3acceee8dc134fb2b89f07831129eaeec81af2b19a23dabe3e0 AS bun
FROM denoland/deno:bin@sha256:764a91cef86118b822ce1770c512bf1ea2a73fd5af4a504fdb915dfe2fd9e15b AS deno
FROM golang:latest@sha256:fb612b7831d53a89cbc0aaa7855b69ad7b0caf603715860cf538df854d047b84 AS golang
FROM ghcr.io/dskiff/tko:bin@sha256:52f19f8267880047dc7a3f5b124a52000ed8d68425ec449375d79712250ef26a AS tko

FROM ghcr.io/actions/actions-runner:latest@sha256:8c3f5970b8ceb90cbd3e89b80c6806bb74d9c31686e9177c743323a4539d12f5 AS base

FROM ubuntu:noble@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9 AS builder
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

FROM ubuntu:noble@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9
# see: https://github.com/actions/runner/blob/main/images/Dockerfile

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

ENV BIN_DIR=/usr/bin
ENV UID=1001
ENV GID=0
ENV USERNAME="runner"
ENV BASE_DIR=/home/${USERNAME}_base

# Add deps from images
COPY --from=golang  --chown=root:0 /usr/local/go /usr/local/
COPY --from=builder --chown=root:0 /work/bin/* ${BIN_DIR}/

# Add golang + builtin node + cargo to PATH
ENV PATH=/usr/local/go:${BASE_DIR}/externals/node20/bin:${BASE_DIR}/.cargo/bin:${PATH}

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
    } | tee ${BASE_DIR}/versions.yaml && \
    chmod g+r ${BASE_DIR}/versions.yaml"]

USER $USERNAME

# Inject entrypoint
COPY --chown=root:0 ./entrypoint.sh ${BASE_DIR}/

WORKDIR /home/${USERNAME}

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/home/runner_base/entrypoint.sh"]

