#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Safely replace an existing Docker Compose Xboard service with the MX/Mundo build.
# The base compose file and .env are never modified. Keep using the generated
# override file for subsequent starts.
set -Eeuo pipefail

ROOT="$(pwd)"
COMPOSE_FILE=""
SERVICE="xboard"
MYSQL_SERVICE=""
BACKUP_DIR=""
HEALTH_URL=""
IMAGE=""
EDITION=""
BASE_OVERRIDE=""
MODE="dry-run"
YES=0
SKIP_DB_BACKUP=0

usage() {
  cat <<EOF
Usage:
  migrate-to-mx-mundo.sh [options]

Modes:
  --dry-run                 Inspect and print the planned migration (default)
  --apply                   Back up, pull, update, and start the target service
  --rollback SNAPSHOT_DIR   Restore the old image/configuration from a snapshot

Options:
  --root DIR                Existing Compose project directory (default: current)
  --compose FILE            Compose file (default: compose.yaml or compose.yml)
  --service NAME            Xboard service name (default: xboard)
  --mysql-service NAME      Compose service containing mysqldump (default: Xboard service)
  --backup-dir DIR          Snapshot destination (default: sibling backup directory)
  --health-url URL          URL to check after startup
  --edition standard|full   Published edition (default: standard)
  --image IMAGE             Override the published image reference
  --override FILE           Existing Compose override (auto-detects compose.mx-mundo.override.yaml)
  --yes                     Do not ask for the apply confirmation
  --skip-db-backup          Skip the script's MySQL dump (use only after an external backup)
  -h, --help                Show this help

The script does not run xboard:install, does not edit .env, and never uses
'docker compose down -v'. The generated compose.mx-mundo.image.yaml must be
used for future starts:
  docker compose -f compose.yaml -f compose.mx-mundo.image.yaml up -d
EOF
}

log() { printf '[migrate] %s\n' "$*"; }
warn() { printf '[migrate] WARNING: %s\n' "$*" >&2; }
die() { printf '[migrate] ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --rollback)
      [[ $# -ge 2 ]] || die "--rollback requires a snapshot directory"
      MODE="rollback"; BACKUP_DIR="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --compose) COMPOSE_FILE="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --mysql-service) MYSQL_SERVICE="$2"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --health-url) HEALTH_URL="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --edition) EDITION="${2:?--edition needs a value}"; shift 2 ;;
    --override) BASE_OVERRIDE="${2:?--override needs a path}"; shift 2 ;;
    --dockerfile)
      case "${2:-}" in
        Dockerfile) EDITION=full ;;
        Dockerfile.1panel) EDITION=standard ;;
        *) die "Use --edition standard or --edition full" ;;
      esac
      shift 2 ;;
    --yes) YES=1; shift ;;
    --skip-db-backup) SKIP_DB_BACKUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

if [[ "$MODE" == "rollback" ]]; then
  [[ -d "$BACKUP_DIR" && -f "$BACKUP_DIR/metadata.env" ]] || die "Snapshot metadata.env is missing"
  [[ "$YES" == "1" ]] || die "Repeat with --yes after reviewing $BACKUP_DIR"
  # A rollback may be launched from outside the original deployment directory.
  . "$BACKUP_DIR/metadata.env"
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || die "Project directory does not exist: $ROOT"
else
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || die "Project directory does not exist: $ROOT"
fi
if [[ -n "$COMPOSE_FILE" && "$COMPOSE_FILE" != /* ]]; then
  COMPOSE_FILE="$ROOT/$COMPOSE_FILE"
fi
[[ -n "$COMPOSE_FILE" ]] || {
  [[ -f "$ROOT/compose.yaml" ]] && COMPOSE_FILE="$ROOT/compose.yaml" || COMPOSE_FILE="$ROOT/compose.yml"
}
[[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"
[[ -f "$ROOT/.env" ]] || die "Missing $ROOT/.env; refusing to guess database settings"

command -v docker >/dev/null 2>&1 || die "Docker is required"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required"
if [[ "$MODE" != rollback && -z "$BASE_OVERRIDE" && -f "$ROOT/compose.mx-mundo.override.yaml" ]]; then
  BASE_OVERRIDE="$ROOT/compose.mx-mundo.override.yaml"
fi
if [[ -n "$BASE_OVERRIDE" ]]; then
  [[ "$BASE_OVERRIDE" == /* ]] || BASE_OVERRIDE="$ROOT/$BASE_OVERRIDE"
  [[ -f "$BASE_OVERRIDE" ]] || die "Override not found: $BASE_OVERRIDE"
fi
COMPOSE=(docker compose --project-directory "$ROOT" -f "$COMPOSE_FILE")
[[ -z "$BASE_OVERRIDE" ]] || COMPOSE+=(-f "$BASE_OVERRIDE")
COMPOSE_CONFIG="$("${COMPOSE[@]}" config)" || die "docker compose config failed"
mapfile -t SERVICES < <("${COMPOSE[@]}" config --services)
if ! printf '%s\n' "${SERVICES[@]}" | grep -Fxq "$SERVICE"; then
  die "Service '$SERVICE' was not found. Available services: ${SERVICES[*]}"
fi

if [[ -z "$BACKUP_DIR" ]]; then
  PARENT="$(dirname "$ROOT")"
  BACKUP_DIR="$PARENT/xboard-migration-backups/$(date -u +%Y%m%dT%H%M%SZ)"
fi
EDITION="${EDITION:-standard}"
case "$EDITION" in standard|full) ;; *) die "Unknown edition: $EDITION" ;; esac
IMAGE="${IMAGE:-ghcr.io/furina-lee/xboard:$EDITION}"
[[ "$IMAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./:@-]*$ ]] || die "Invalid image reference"
OVERRIDE="$ROOT/compose.mx-mundo.image.yaml"
if [[ "$MODE" != rollback && -e "$OVERRIDE" ]]; then
  die "Migration override already exists: $OVERRIDE. Use it for regular Docker updates."
fi
ROLLBACK_OVERRIDE="$ROOT/compose.mx-mundo.rollback.yaml"
OLD_IMAGE=""
ROLLBACK_IMAGE=""

# Simple .env reader for the DB_* values used by mysqldump. It intentionally
# supports the normal KEY=value form used by Xboard's installer.
env_value() {
  local key="$1" value
  value="$(awk -v key="$key" 'index($0, key "=") == 1 {sub("^[^=]*=", ""); print; exit}' "$ROOT/.env" || true)"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  printf '%s' "$value"
}

DB_CONNECTION="$(env_value DB_CONNECTION)"
DB_HOST="$(env_value DB_HOST)"
DB_PORT="$(env_value DB_PORT)"
DB_DATABASE="$(env_value DB_DATABASE)"
DB_USERNAME="$(env_value DB_USERNAME)"
DB_PASSWORD="$(env_value DB_PASSWORD)"

if [[ "$MODE" != "rollback" ]]; then
  [[ "${DB_CONNECTION:-mysql}" == "mysql" ]] || die "This script requires DB_CONNECTION=mysql"
  [[ -n "$DB_HOST" && -n "$DB_DATABASE" && -n "$DB_USERNAME" ]] || die "DB_HOST, DB_DATABASE, and DB_USERNAME must be present in .env"
fi
DB_PORT="${DB_PORT:-3306}"

print_plan() {
  log "mode: $MODE"
  log "project: $ROOT"
  log "compose: $COMPOSE_FILE"
  log "service: $SERVICE"
  log "mysqldump service: ${MYSQL_SERVICE:-$SERVICE}"
  log "target image: $IMAGE"
  log "existing override: ${BASE_OVERRIDE:-none}"
  log "snapshot: $BACKUP_DIR"
  log "database: $DB_USERNAME@$DB_HOST:$DB_PORT/$DB_DATABASE"
  log "base compose and .env will not be modified"
  printf "[migrate] future start command:"; printf " %q" "${COMPOSE[@]}" -f "$OVERRIDE" up -d; printf "\n"
}

if [[ "$MODE" == "dry-run" ]]; then
  print_plan
  log "dry-run complete; no service, volume, database, or file was changed"
  exit 0
fi

umask 077

confirm() {
  [[ "$YES" == "1" ]] && return 0
  printf '[migrate] Type APPLY to continue: ' >&2
  read -r answer
  [[ "$answer" == "APPLY" ]] || die "Migration cancelled"
}

backup_mysql() {
  local dump="$BACKUP_DIR/mysql.sql.gz"
  log "creating MySQL backup: $dump"
  # The password is passed through MYSQL_PWD inside a disposable container and
  # never appears as a mysqldump command-line argument.
  local dump_runner="$SERVICE"
  if [[ -n "${MYSQL_SERVICE:-}" ]]; then
    dump_runner="$MYSQL_SERVICE"
  fi
  "${COMPOSE[@]}" run --rm --no-deps -T \
    -e "DB_HOST=$DB_HOST" -e "DB_PORT=$DB_PORT" \
    -e "DB_DATABASE=$DB_DATABASE" -e "DB_USERNAME=$DB_USERNAME" \
    -e "MYSQL_PWD=$DB_PASSWORD" \
    --entrypoint /bin/sh "$dump_runner" -c \
    'dump="$(command -v mariadb-dump || command -v mysqldump)" || { echo "No MySQL dump client in the selected service" >&2; exit 127; }; \
     "$dump" --single-transaction --quick --routines --triggers \
       -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" "$DB_DATABASE"' \
    | gzip -c > "$dump"
  [[ -s "$dump" ]] || die "MySQL dump is empty"
  gzip -t "$dump" || die "MySQL dump is not a valid gzip file"
}

backup_state() {
  log "saving configuration and runtime state"
  cp -p "$ROOT/.env" "$BACKUP_DIR/.env"
  cp -p "$COMPOSE_FILE" "$BACKUP_DIR/$(basename "$COMPOSE_FILE")"
  [[ -z "$BASE_OVERRIDE" ]] || cp -p "$BASE_OVERRIDE" "$BACKUP_DIR/existing-override.yaml"
  printf '%s\n' "$COMPOSE_CONFIG" > "$BACKUP_DIR/compose.resolved.yaml"
  "${COMPOSE[@]}" ps -a > "$BACKUP_DIR/compose.ps.txt" || true
  "${COMPOSE[@]}" images > "$BACKUP_DIR/compose.images.txt" || true
  local cid
  cid="$( "${COMPOSE[@]}" ps -a -q "$SERVICE" | head -n 1 || true)"
  if [[ -n "$cid" ]]; then
    docker inspect "$cid" > "$BACKUP_DIR/container-$cid.json"
    OLD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    ROLLBACK_IMAGE="xboard:rollback-$(date -u +%s)"
    docker tag "$(docker inspect -f '{{.Image}}' "$cid")" "$ROLLBACK_IMAGE"
    log "old image: ${OLD_IMAGE:-unknown}; rollback tag: ${ROLLBACK_IMAGE:-unavailable}"
  fi
  for dir in .docker/.data storage/logs storage/theme plugins; do
    if [[ -d "$ROOT/$dir" ]]; then
      tar -czf "$BACKUP_DIR/$(echo "$dir" | tr '/' '_').tar.gz" -C "$ROOT" "$dir"
    fi
  done
  docker volume ls --format '{{.Name}}' | while read -r volume; do
    [[ -n "$volume" ]] || continue
    if docker volume inspect "$volume" >/dev/null 2>&1; then
      docker volume inspect "$volume" > "$BACKUP_DIR/volume-$volume.json" 2>/dev/null || true
    fi
  done
  cat > "$BACKUP_DIR/metadata.env" <<EOF
ROOT=$(printf '%q' "$ROOT")
COMPOSE_FILE=$(printf '%q' "$COMPOSE_FILE")
SERVICE=$(printf '%q' "$SERVICE")
BASE_OVERRIDE=$(printf '%q' "$BASE_OVERRIDE")
IMAGE=$(printf '%q' "$IMAGE")
OLD_IMAGE=$(printf '%q' "$OLD_IMAGE")
ROLLBACK_IMAGE=$(printf '%q' "$ROLLBACK_IMAGE")
OVERRIDE=$(printf '%q' "$OVERRIDE")
ROLLBACK_OVERRIDE=$(printf '%q' "$ROLLBACK_OVERRIDE")
EOF
}

write_override() {
  cat > "$OVERRIDE" <<EOF
# Generated by scripts/migrate-to-mx-mundo.sh. Do not delete while using the MX build.
services:
  $SERVICE:
    image: $IMAGE
    build: !reset null
EOF
}

write_rollback_override() {
  [[ -n "$ROLLBACK_IMAGE" ]] || return 0
  cat > "$ROLLBACK_OVERRIDE" <<EOF
# Generated rollback override. Keep until the migration is accepted.
services:
  $SERVICE:
    image: $ROLLBACK_IMAGE
    build: !reset null
EOF
}

pull_target() {
  log "pulling target image $IMAGE"
  docker pull "$IMAGE"
  docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
    'grep -q TYPE_MX /www/app/Models/Server.php && grep -q buildMxUri /www/app/Utils/Helper.php && grep -q "Mundo Connect 1" /www/public/assets/admin/assets/*.js' \
    || die "Target image does not contain the MX implementation and admin assets"
}

run_update() {
  local update_log="$BACKUP_DIR/xboard-update.log"
  log "stopping only service $SERVICE"
  "${COMPOSE[@]}" stop "$SERVICE" || return 1
  log "running database migrations and xboard:update"
  local target_compose=("${COMPOSE[@]}" -f "$OVERRIDE")
  if ! "${target_compose[@]}" run --rm --no-deps --pull never -T \
    -e CACHE_DRIVER=array -e QUEUE_CONNECTION=sync -e SESSION_DRIVER=array \
    --entrypoint /bin/sh "$SERVICE" -c \
    'php artisan migrate --force --no-interaction && php artisan xboard:update --no-interaction' \
    2>&1 | tee "$update_log"; then
    return 1
  fi
  if grep -Eiq 'SQLSTATE\[|Migration table not found|\b(exception|fatal error|error):' "$update_log"; then
    warn "update output contains an error marker; see $update_log"
    return 1
  fi
}

start_and_check() {
  local target_compose=("${COMPOSE[@]}" -f "$OVERRIDE")
  log "starting target service"
  "${target_compose[@]}" up -d --no-deps --no-build --pull never "$SERVICE" || return 1
  for _ in $(seq 1 30); do
    if "${target_compose[@]}" ps --status running --services | grep -Fxq "$SERVICE"; then
      if [[ -z "$HEALTH_URL" ]]; then
        log "service is running; no health URL was supplied"
        return 0
      fi
      if command -v curl >/dev/null 2>&1 && curl -fsSL --max-time 10 "$HEALTH_URL" >/dev/null; then
        log "health check passed: $HEALTH_URL"
        return 0
      fi
    fi
    sleep 2
done
  return 1
}

rollback_service() {
  warn "starting rollback to the original Compose image"
  "${COMPOSE[@]}" stop "$SERVICE" || true
  local result=0
  if [[ -n "$ROLLBACK_IMAGE" ]] && docker image inspect "$ROLLBACK_IMAGE" >/dev/null 2>&1; then
    write_rollback_override
    log "use rollback override: $ROLLBACK_OVERRIDE"
    "${COMPOSE[@]}" -f "$ROLLBACK_OVERRIDE" up -d --no-deps --no-build --pull never "$SERVICE" || result=$?
  else
    warn "the old image tag is unavailable; using the original Compose image reference"
    "${COMPOSE[@]}" up -d --no-deps --no-build --pull never "$SERVICE" || result=$?
  fi
  warn "database was not automatically restored; use $BACKUP_DIR/mysql.sql.gz only after reviewing migration impact"
  return "$result"
}

if [[ "$MODE" == "rollback" ]]; then
  log "rollback restores the previous image/configuration only; database restore is manual"
  rollback_service || die "Could not restart the previous image"
  [[ "$OVERRIDE" != "$ROOT/compose.mx-mundo.image.yaml" ]] || rm -f "$OVERRIDE"
  exit 0
fi

print_plan
confirm
mkdir -p "$BACKUP_DIR"
if [[ "$SKIP_DB_BACKUP" == "1" ]]; then
  warn "--skip-db-backup was supplied; database rollback will not be available"
else
  backup_mysql
fi
backup_state
write_rollback_override
pull_target
write_override
"${COMPOSE[@]}" -f "$OVERRIDE" config --quiet || { rm -f "$OVERRIDE"; die "Compose could not validate the image override"; }

if ! run_update; then
  rollback_service || die "Rollback could not restart the old service; review $BACKUP_DIR"
  rm -f "$OVERRIDE"
  die "xboard:update failed; old service was restarted, review $BACKUP_DIR"
fi

if ! start_and_check; then
  rollback_service || die "Rollback could not restart the old service; review $BACKUP_DIR"
  rm -f "$OVERRIDE"
  die "target service failed health checks; old service was restarted, review $BACKUP_DIR"
fi

log "migration completed"
log "snapshot: $BACKUP_DIR"
printf "[migrate] keep using:"; printf " %q" "${COMPOSE[@]}" -f "$OVERRIDE" up -d; printf "\n"
log "the original compose file, .env, database, volumes, and reverse proxy were preserved"
