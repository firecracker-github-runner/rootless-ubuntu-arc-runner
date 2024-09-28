FROM oven/bun:distroless@sha256:4bc651b35eec7df5aeae5337d056e452dab23ca4897734779d0db9d1dfce82f9 AS bun
FROM denoland/deno:bin@sha256:9b2cd796333a48d256576e40cd911c3a5ee72d75154c721de93870f70972f1d7 AS deno
FROM golang:latest@sha256:4f063a24d429510e512cc730c3330292ff49f3ade3ae79bda8f84a24fa25ecb0 AS golang
FROM ghcr.io/dskiff/tko:bin@sha256:e075199e765f3143387e3782328f80af2a7f73e3389097e851c7322b07e51d77 AS tko

FROM ghcr.io/actions/actions-runner:latest@sha256:30a523019a27c97da3f2145252dad9478b7427a8b484a0c775f3a8605d84d35d AS base

FROM ubuntu:noble@sha256:dfc10878be8d8fc9c61cbff33166cb1d1fe44391539243703c72766894fa834a AS builder
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

FROM ubuntu:noble@sha256:dfc10878be8d8fc9c61cbff33166cb1d1fe44391539243703c72766894fa834a
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

