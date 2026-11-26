#!/usr/bin/env bash
set -euo pipefail

edition="${1:-standard}"
template=compose.sample.yaml
usage() { printf '用法：install.sh [standard|full|1panel]（安装到当前目录）\n'; }
if [[ $edition == -h || $edition == --help ]]; then
  usage
  exit 0
fi
if (( $# > 1 )); then
  usage >&2
  exit 2
fi
case "$edition" in
  standard|full) ;;
  1panel) template=compose.1panel.sample.yaml ;;
  *) usage >&2; exit 2 ;;
esac

command -v curl >/dev/null
docker compose version >/dev/null
[[ -t 0 ]] || { printf '请在交互式终端运行安装脚本。\n' >&2; exit 1; }
umask 077
lock=./.xboard-install.lock
mkdir -- "$lock" || { printf '当前目录无法加锁，或已有安装在运行。\n' >&2; exit 1; }
tmp="$lock/compose.template"
trap 'rm -f -- "$tmp"; rmdir -- "$lock"' EXIT

for path in .env .docker storage plugins compose.yaml compose.yml docker-compose.yaml docker-compose.yml \
    compose.override.yaml compose.override.yml docker-compose.override.yaml docker-compose.override.yml; do
  if [[ -e $path || -L $path ]]; then
    printf '当前目录已有 %s。请切换到新的部署目录后再运行。\n' "$path" >&2
    exit 1
  fi
done

curl -fsSL --proto '=https' --proto-redir '=https' \
  "https://raw.githubusercontent.com/Furina-Lee/Xboard/master/$template" -o "$tmp"

image=standard
[[ "$edition" != full ]] || image=full
sed -e "s|ghcr.io/furina-lee/xboard:standard|ghcr.io/furina-lee/xboard:$image|" \
    -e 's|      - redis-data:/data|      - ./.docker/redis:/data|' \
    -e '/^volumes:$/d' -e '/^  redis-data:$/d' \
    "$tmp" > compose.yaml
touch .env
compose=(docker compose -f compose.yaml)
"${compose[@]}" config --quiet
"${compose[@]}" pull xboard
"${compose[@]}" run --rm -e ENABLE_SQLITE= -e ENABLE_REDIS=true xboard sh -c \
  'php artisan xboard:install && grep -qE "^INSTALLED=(1|true)$" /www/.env' \
  || { printf 'Xboard 初始化未完成。部署文件保留在 %s。\n' "$PWD" >&2; exit 1; }
"${compose[@]}" up -d
"${compose[@]}" ps
printf '部署目录：%s\n' "$PWD"
