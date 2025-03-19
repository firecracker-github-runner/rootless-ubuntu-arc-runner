FROM oven/bun:distroless@sha256:c578688b82a68441510d5ae8b34c55bd415b838812ed18892e75b6ad1058b5e0 AS bun
FROM denoland/deno:bin@sha256:8b94e5acfdb2405544cb01f1d5abd9ab829d1aab6f6a0571230d403b492275bf AS deno
FROM golang:latest@sha256:af0bb3052d6700e1bc70a37bca483dc8d76994fd16ae441ad72390eea6016d03 AS golang
FROM ghcr.io/dskiff/tko:bin@sha256:7d1389c1655096ac1abef3b3e569d322e648b83815404cb0c102b139e97ab8f5 AS tko

FROM ghcr.io/actions/actions-runner:latest@sha256:c02e8e1b479ea39b196c3bb0a40a66a191302654a6ef5c042eafe11c13323137 AS base

FROM ubuntu:noble@sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782 AS builder
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

FROM ubuntu:noble@sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782
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
    libicu-dev \
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

