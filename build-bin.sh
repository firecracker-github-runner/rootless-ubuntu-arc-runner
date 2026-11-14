#!/bin/env bash

set -eoux pipefail

# Fetch the latest release of a GitHub project via the github.com
# `releases/latest/download/<asset>` redirect. Unlike the REST API
# (api.github.com), this isn't subject to the 60 req/hour unauthenticated rate
# limit, which shared GitHub-hosted runner IPs regularly exhaust (-> HTTP 403).
function fetch {
  local package=$1
  local filename_prefix=$2
  local artifact=$3

  local base_url=https://github.com/${package}/releases/latest/download

  mkdir -p ${filename_prefix}

  curl -sSLf --retry 3 -O ${base_url}/${artifact}
  curl -sSLf --retry 3 -O ${base_url}/checksums.txt
  sha256sum --check --ignore-missing --strict checksums.txt

  tar fxzp ${artifact} -C ${filename_prefix}
  rm ${artifact} checksums.txt

  mv ${filename_prefix}/${filename_prefix} ${BIN_OUT}/${filename_prefix}
}

fetch "ko-build/ko" "ko" "ko_Linux_x86_64.tar.gz"
