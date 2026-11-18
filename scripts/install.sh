#!/usr/bin/env bash
set -euo pipefail

edition="${1:-standard}"
project_dir="${2:-$HOME/xboard}"
template=compose.sample.yaml
database_env=(-e ENABLE_SQLITE=true)
case "$edition" in
  standard|full) ;;
  1panel)
    template=compose.1panel.sample.yaml
    database_env=()
    ;;
  *) printf 'Usage: install.sh [standard|full|1panel] [directory]\n' >&2; exit 2 ;;
esac

command -v curl >/dev/null
docker compose version >/dev/null
[[ -t 0 ]] || { printf 'Run the installer in an interactive terminal.\n' >&2; exit 1; }
mkdir -p "$project_dir"
cd "$project_dir"
if [[ -n "$(find . -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  printf 'Choose an empty directory for a fresh install: %s\n' "$PWD" >&2
  exit 1
fi

umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "https://raw.githubusercontent.com/Furina-Lee/Xboard/master/$template" -o "$tmp"
if [[ "$edition" == full ]]; then
  sed 's|ghcr.io/furina-lee/xboard:standard|ghcr.io/furina-lee/xboard:full|' "$tmp" > compose.yaml
else
  cp "$tmp" compose.yaml
fi
touch .env
docker compose config --quiet
docker compose pull xboard
docker compose run --rm "${database_env[@]}" -e ENABLE_REDIS=true xboard sh -c \
  'php artisan xboard:install && grep -qE "^INSTALLED=(1|true)$" /www/.env' \
  || { printf 'Xboard initialization did not complete.\n' >&2; exit 1; }
docker compose up -d
docker compose ps
printf 'Deployment directory: %s\n' "$PWD"
