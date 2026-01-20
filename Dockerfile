FROM oven/bun:1-slim@sha256:9d20d1b535596c4a021ba2087d2d303c4098e96be15f47775729cf7a259bb41e AS bun
FROM denoland/deno:bin@sha256:892c168f8df9731133f76715f31ef01d502915a65e16f052f0c51ab187d474cb AS deno
FROM golang:latest@sha256:ce63a16e0f7063787ebb4eb28e72d477b00b4726f79874b3205a965ffd797ab2 AS golang
FROM ghcr.io/dskiff/tko:bin@sha256:9e489cde4eed73ad92dcf0bc110f4904b2d0b19e58fe0908ba1a67b598b324c2 AS tko

FROM ghcr.io/actions/actions-runner:latest@sha256:dced476aa42703ebd9aafc295ce52f160989c4528e831fc3be2aef83a1b3f6da AS base

FROM ubuntu:noble@sha256:cd1dba651b3080c3686ecf4e3c4220f026b521fb76978881737d24f200828b2b AS builder
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

FROM ubuntu:noble@sha256:cd1dba651b3080c3686ecf4e3c4220f026b521fb76978881737d24f200828b2b
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
    musl-tools \
    zlib1g-dev \
    ca-certificates \
    curl \
    git \
    git-lfs \
    jq \
    lsb-release \
    libicu-dev \
    unzip \
    wget \
    zstd && \
    ${BASE_DIR}/bin/installdependencies.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER $USERNAME

# Install rustup and stable Rust toolchain as runner user directly into BASE_DIR
# NOTE: At runtime, /home/runner is mounted as a volume. Any content that needs to be
# available in /home/runner at runtime must be installed in ${BASE_DIR} (/home/runner_base)
# at build time. The entrypoint script copies everything from ${BASE_DIR} to /home/runner.
RUN CARGO_HOME=${BASE_DIR}/.cargo RUSTUP_HOME=${BASE_DIR}/.rustup \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path

# Inject entrypoint
COPY --chown=root:0 ./entrypoint.sh ${BASE_DIR}/

# Generate versions.yaml file
USER root
RUN echo "# Build Tool Versions" > ${BASE_DIR}/versions.yaml && \
    echo "bun: $(bun --version)" >> ${BASE_DIR}/versions.yaml && \
    echo "deno: $(deno --version | head -n1 | awk '{print $2}')" >> ${BASE_DIR}/versions.yaml && \
    echo "go: $(go version | awk '{print $3}' | sed 's/go//')" >> ${BASE_DIR}/versions.yaml && \
    echo "ko: $(ko version | grep 'ko version' | awk '{print $3}')" >> ${BASE_DIR}/versions.yaml && \
    echo "node: $(${BASE_DIR}/externals/node20/bin/node --version | sed 's/v//')" >> ${BASE_DIR}/versions.yaml && \
    echo "rustc: $(CARGO_HOME=${BASE_DIR}/.cargo RUSTUP_HOME=${BASE_DIR}/.rustup ${BASE_DIR}/.cargo/bin/rustc --version | awk '{print $2}')" >> ${BASE_DIR}/versions.yaml && \
    echo "cargo: $(CARGO_HOME=${BASE_DIR}/.cargo RUSTUP_HOME=${BASE_DIR}/.rustup ${BASE_DIR}/.cargo/bin/cargo --version | awk '{print $2}')" >> ${BASE_DIR}/versions.yaml && \
    echo "tko: $(tko version)" >> ${BASE_DIR}/versions.yaml && \
    chown ${UID}:${GID} ${BASE_DIR}/versions.yaml && \
    cat ${BASE_DIR}/versions.yaml

USER $USERNAME

WORKDIR /home/${USERNAME}

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/home/runner_base/entrypoint.sh"]

