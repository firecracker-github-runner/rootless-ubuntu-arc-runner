FROM oven/bun:distroless@sha256:4404da9fe53549042fcc4d72012e13f93083c109442f09865a4a5c04af72c508 as bun
FROM denoland/deno:bin@sha256:ef5d391400a7ea855e8766dc1005f2dad5f7845f8438cdb1a9dd9424198b5338 as deno
FROM golang:latest@sha256:829eff99a4b2abffe68f6a3847337bf6455d69d17e49ec1a97dac78834754bd6 as golang
FROM ghcr.io/dskiff/tko:bin@sha256:d9b52ab6ef952fc7fd233a6d738050ad6c2ad14f5fd318ae2e3a7ab92f28d9d3 as tko

FROM ghcr.io/actions/actions-runner:latest@sha256:95db6fbb020b9f734e8a00389291dae766f0e6ad3d1171ae2d68e9ad8ac4a985 as base

FROM ubuntu:jammy@sha256:340d9b015b194dc6e2a13938944e0d016e57b9679963fdeb9ce021daac430221 as builder
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

FROM ubuntu:jammy@sha256:340d9b015b194dc6e2a13938944e0d016e57b9679963fdeb9ce021daac430221
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

# Add golang + builtin node to PATH
ENV PATH=/usr/local/go:${BASE_DIR}/externals/node20/bin:${PATH}

# Setup runner
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
    unzip \
    wget \
    zstd && \
    ${BASE_DIR}/bin/installdependencies.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Inject entrypoint
COPY --chown=root:0 ./entrypoint.sh ${BASE_DIR}/

USER $USERNAME
WORKDIR /home/${USERNAME}

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/home/runner_base/entrypoint.sh"]

