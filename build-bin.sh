#!/bin/env bash

set -eoux pipefail

function fetch {
  local package=$1
  local filename_prefix=$2

  local releases_url=https://github.com/${package}/releases/latest
  local tag=$(curl -sSLfI -o /dev/null -w '%{url_effective}' ${releases_url} | awk -F/ '{print $NF}')
  local artifact=${filename_prefix}_${tag:1}_linux_x86_64
  local url=https://github.com/${package}/releases/download/${tag}/${artifact}.tar.gz

  mkdir -p ${filename_prefix}

  curl -sSLf -O $url
  tar fxzp ${artifact}.tar.gz -C ${filename_prefix}
  rm ${artifact}.tar.gz

  mv ${filename_prefix}/${filename_prefix} ${BIN_OUT}/${filename_prefix}
}

function fetch_zig {
  local destination=${OPT_OUT}/zig
  local version=$(npm view --silent @zigc/linux-x64 version)
  local tmp_dir=$(mktemp -d)

  npm install --silent \
    --prefix ${tmp_dir}/zig \
    --no-package-lock \
    --ignore-scripts \
    --omit=dev \
    @zigc/linux-x64@${version} \
    @zigc/lib@${version}

  rm -rf ${destination}
  mkdir -p ${destination}
  cp ${tmp_dir}/zig/node_modules/@zigc/linux-x64/bin/zig ${destination}/zig
  cp -r ${tmp_dir}/zig/node_modules/@zigc/lib ${destination}/lib
  rm -rf ${tmp_dir}
}

fetch "ko-build/ko" "ko"
fetch_zig
