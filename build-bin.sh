#!/bin/env bash

set -eoux pipefail

function verify_npm_integrity {
  local file=$1
  local expected=$2
  local actual=$(node -e "const crypto = require('node:crypto'); const fs = require('node:fs'); process.stdout.write('sha512-' + crypto.createHash('sha512').update(fs.readFileSync(process.argv[1])).digest('base64'))" ${file})

  if [[ "${actual}" != "${expected}" ]]; then
    echo "integrity check failed for ${file}" >&2
    echo "expected: ${expected}" >&2
    echo "actual:   ${actual}" >&2
    return 1
  fi
}

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
  local tmp_dir=$(mktemp -d)
  local zig_tarball=$(cd ${tmp_dir} && npm pack --silent @zigc/linux-x64@${ZIG_VERSION})
  local lib_tarball=$(cd ${tmp_dir} && npm pack --silent @zigc/lib@${ZIG_VERSION})

  verify_npm_integrity ${tmp_dir}/${zig_tarball} ${ZIG_LINUX_X64_INTEGRITY}
  verify_npm_integrity ${tmp_dir}/${lib_tarball} ${ZIG_LIB_INTEGRITY}

  mkdir -p ${tmp_dir}/zig ${tmp_dir}/lib
  tar -xzf ${tmp_dir}/${zig_tarball} -C ${tmp_dir}/zig
  tar -xzf ${tmp_dir}/${lib_tarball} -C ${tmp_dir}/lib

  rm -rf ${destination}
  mkdir -p ${destination} ${destination}/lib
  cp ${tmp_dir}/zig/package/bin/zig ${destination}/zig
  cp -r ${tmp_dir}/lib/package/. ${destination}/lib
  rm -rf ${tmp_dir}
}

fetch "ko-build/ko" "ko"
fetch_zig
