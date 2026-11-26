#!/usr/bin/env bash
set -euo pipefail

if (( $# > 0 )); then
  printf '用法：bash install-1panel.sh（安装到当前目录）\n' >&2
  exit 2
fi

installer="$(curl -fsSL --proto '=https' --proto-redir '=https' \
  https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/install.sh)"
exec bash -c "$installer" -- 1panel
