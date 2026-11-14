#!/bin/env bash

set -eoux pipefail

function fetch {
  local package=$1
  local filename_prefix=$2

  local releases_api=https://api.github.com/repos/${package}/releases/latest
  local tag=$(curl -sSLf -H 'Accept: application/json' ${releases_api} | jq -r '.tag_name')
  local artifact=${filename_prefix}_${tag:1}_linux_x86_64
  local url=https://github.com/${package}/releases/download/${tag}/${artifact}.tar.gz

  mkdir -p ${filename_prefix}

  curl -sSLf -O $url
  tar fxzp ${artifact}.tar.gz -C ${filename_prefix}
  rm ${artifact}.tar.gz

  mv ${filename_prefix}/${filename_prefix} ${BIN_OUT}/${filename_prefix}
}

# Zig: the official release tarball (latest stable unless ZIG_VERSION is set), extracted to $1.
# Follows https://ziglang.org/download/community-mirrors/ : ziglang.org asks automated downloads
# to use the community mirrors (shuffled, with ziglang.org itself as the last resort), and every
# download must pass minisign verification against the ZSF key from https://ziglang.org/download/
# with the signature's "file:" trusted comment matching the requested tarball (no downgrades).
ZIG_PUBKEY=RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U

function fetch_zig {
  local out=$1
  local version tarball file mirrors url comment

  curl -sSLf -o zig-index.json https://ziglang.org/download/index.json
  version=${ZIG_VERSION:-$(jq -r 'keys[] | select(. != "master")' zig-index.json | sort -V | tail -n1)}
  tarball=$(jq -er --arg v "${version}" --arg t "$(uname -m)-linux" '.[$v][$t].tarball' zig-index.json)
  rm zig-index.json
  file=${tarball##*/}
  mirrors=$(curl -sSLf https://ziglang.org/download/community-mirrors.txt | shuf)

  for url in ${mirrors} ${tarball%/*}; do
    rm -f "${file}" "${file}.minisig"
    if curl -sSLf --connect-timeout 10 --speed-limit 102400 --speed-time 30 \
          -o "${file}" "${url}/${file}?source=docker-image-build" &&
       curl -sSLf --connect-timeout 10 --max-time 30 \
          -o "${file}.minisig" "${url}/${file}.minisig?source=docker-image-build" &&
       comment=$(minisign -V -Q -P "${ZIG_PUBKEY}" -m "${file}") &&
       grep -Fxq "file:${file}" <<<"${comment//$'\t'/$'\n'}"; then
      mkdir -p "${out}"
      tar -xJf "${file}" -C "${out}" --strip-components=1 --no-same-owner
      rm -f "${file}" "${file}.minisig"
      return 0
    fi
  done

  echo "failed to fetch a verified ${file} from any mirror or ziglang.org" >&2
  return 1
}

fetch "ko-build/ko" "ko"
fetch_zig "${ZIG_OUT}"
