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
  local releases_url=https://github.com/ziglang/zig/releases/latest
  local tag=$(curl -sSLfI -o /dev/null -w '%{url_effective}' ${releases_url} | awk -F/ '{print $NF}')
  local artifact=zig-x86_64-linux-${tag}
  local archive=${artifact}.tar.xz
  local signature=${archive}.minisig
  local public_key=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
  local destination=${OPT_OUT}/zig
  local tmp_dir=$(mktemp -d)

  local mirrors=(
    https://pkg.machengine.org/zig
    https://zigmirror.hryx.net/zig
    https://ziglang.freetls.fastly.net
    https://zig.linus.dev/zig
    https://zig.squirl.dev
  )

  for mirror in "${mirrors[@]}"; do
    rm -f ${tmp_dir}/${archive} ${tmp_dir}/${signature}
    if curl -sSLf -o ${tmp_dir}/${archive} ${mirror}/${archive} && \
      curl -sSLf -o ${tmp_dir}/${signature} ${mirror}/${signature} && \
      minisign -Vm ${tmp_dir}/${archive} -P ${public_key} -x ${tmp_dir}/${signature}; then
      mkdir -p ${tmp_dir}/extract
      tar -xJf ${tmp_dir}/${archive} -C ${tmp_dir}/extract
      rm -rf ${destination}
      mv ${tmp_dir}/extract/${artifact} ${destination}
      rm -rf ${tmp_dir}
      return
    fi
  done

  rm -rf ${tmp_dir}
  echo "failed to download and verify Zig ${tag}" >&2
  return 1
}

fetch "ko-build/ko" "ko"
fetch_zig
