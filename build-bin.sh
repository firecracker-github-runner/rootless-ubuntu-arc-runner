#!/bin/env bash

set -eoux pipefail

function latest_release_tag {
  local package=$1

  basename "$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${package}/releases/latest")"
}

function fetch_ko {
  local package=ko-build/ko
  local tag=$(latest_release_tag "${package}")
  local version=${tag#v}
  local artifact=ko_${version}_Linux_x86_64.tar.gz
  local url=https://github.com/${package}/releases/download/${tag}/${artifact}

  curl -fsSL "${url}" | tar -xz -C "${BIN_OUT}" ko
}

fetch_ko
