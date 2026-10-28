#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# Safely replace an existing Docker Compose Xboard service with the MX/Mundo build.
# The base compose file and .env are never modified. Keep using the generated
# override file for subsequent starts.
set -Eeuo pipefail

REPO_URL="https://github.com/Furina-Lee/Xboard.git"
BRANCH="feature/mx-mundo-transport"
BACKEND_REF="884f9a52bb4ad02f523a307eedfb07e93539081b"
ADMIN_REF="a0db13aa0ba9a861f1fbcb4a4ce4e8d612af5e2e"
ROOT="$(pwd)"
COMPOSE_FILE=""
SERVICE="xboard"
MYSQL_SERVICE=""
BACKUP_DIR=""
HEALTH_URL=""
IMAGE=""
MODE="dry-run"
YES=0
SKIP_DB_BACKUP=0
DISABLE_CADDY=0

usage() {
  cat <<EOF
Usage:
  migrate-to-mx-mundo.sh [options]

Modes:
  --dry-run                 Inspect and print the planned migration (default)
  --apply                   Back up, build, update, and start the target service
  --rollback SNAPSHOT_DIR   Restore the old image/configuration from a snapshot

Options:
  --root DIR                Existing Compose project directory (default: current)
  --compose FILE            Compose file (default: compose.yaml or compose.yml)
  --service NAME            Xboard service name (default: xboard)
  --mysql-service NAME      Compose service containing mysqldump (default: Xboard service)
  --backup-dir DIR          Snapshot destination (default: sibling backup directory)
  --health-url URL          URL to check after startup
  --image IMAGE             Target image tag (default: xboard:mx-mundo-<commit>)
  --yes                     Do not ask for the apply confirmation
  --skip-db-backup          Skip the script's MySQL dump (use only after an external backup)
  --disable-caddy            Disable embedded Caddy for an external reverse proxy such as 1Panel
  -h, --help                Show this help

The script does not run xboard:install, does not edit .env, and never uses
'docker compose down -v'. The generated compose.mx-mundo.override.yaml must be
used for future starts:
  docker compose -f compose.yaml -f compose.mx-mundo.override.yaml up -d
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
    --yes) YES=1; shift ;;
    --skip-db-backup) SKIP_DB_BACKUP=1; shift ;;
    --disable-caddy) DISABLE_CADDY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

if [[ "$MODE" == "rollback" && -f "$BACKUP_DIR/metadata.env" ]]; then
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
command -v git >/dev/null 2>&1 || die "Git is required"

COMPOSE=(docker compose -f "$COMPOSE_FILE")
COMPOSE_CONFIG="$("${COMPOSE[@]}" config)" || die "docker compose config failed"
mapfile -t SERVICES < <(printf '%s\n' "$COMPOSE_CONFIG" | awk '/^  [A-Za-z0-9_.-]+:$/ {gsub(":", "", $1); print $1}')
if ! printf '%s\n' "${SERVICES[@]}" | grep -Fxq "$SERVICE"; then
  die "Service '$SERVICE' was not found. Available services: ${SERVICES[*]}"
fi

if [[ -z "$BACKUP_DIR" ]]; then
  PARENT="$(dirname "$ROOT")"
  BACKUP_DIR="$PARENT/xboard-migration-backups/$(date -u +%Y%m%dT%H%M%SZ)"
fi
if [[ -z "$IMAGE" ]]; then
  IMAGE="xboard:mx-mundo-${BACKEND_REF:0:8}"
fi
OVERRIDE="$ROOT/compose.mx-mundo.override.yaml"
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
  log "disable embedded Caddy: $DISABLE_CADDY"
  log "target repository: $REPO_URL"
  log "target ref: $BRANCH ($BACKEND_REF)"
  log "target admin gitlink: $ADMIN_REF"
  log "target image: $IMAGE"
  log "build checkout: $BACKUP_DIR/source"
  log "snapshot: $BACKUP_DIR"
  log "database: $DB_USERNAME@$DB_HOST:$DB_PORT/$DB_DATABASE"
  log "base compose and .env will not be modified"
  log "future start command: docker compose -f $(basename "$COMPOSE_FILE") -f $(basename "$OVERRIDE") up -d"
}

if [[ "$MODE" == "dry-run" ]]; then
  print_plan
  log "dry-run complete; no service, volume, database, or file was changed"
  exit 0
fi

mkdir -p "$BACKUP_DIR"

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
  local dump_runner="${SERVICE}"
  if [[ -n "${MYSQL_SERVICE:-}" ]]; then
    dump_runner="$MYSQL_SERVICE"
  fi
  "${COMPOSE[@]}" run --rm --no-deps -T \
    -e "DB_HOST=$DB_HOST" -e "DB_PORT=$DB_PORT" \
    -e "DB_DATABASE=$DB_DATABASE" -e "DB_USERNAME=$DB_USERNAME" \
    -e "MYSQL_PWD=$DB_PASSWORD" \
    --entrypoint /bin/sh "$dump_runner" -c \
    'command -v mysqldump >/dev/null 2>&1 || { echo "mysqldump is unavailable in the selected service" >&2; exit 127; }; \
     mysqldump --single-transaction --quick --routines --triggers \
       -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" "$DB_DATABASE"' \
    | gzip -c > "$dump"
  [[ -s "$dump" ]] || die "MySQL dump is empty"
  gzip -t "$dump" || die "MySQL dump is not a valid gzip file"
}

backup_state() {
  log "saving configuration and runtime state"
  cp -p "$ROOT/.env" "$BACKUP_DIR/.env"
  cp -p "$COMPOSE_FILE" "$BACKUP_DIR/$(basename "$COMPOSE_FILE")"
  printf '%s\n' "$COMPOSE_CONFIG" > "$BACKUP_DIR/compose.resolved.yaml"
  docker compose -f "$COMPOSE_FILE" ps -a > "$BACKUP_DIR/compose.ps.txt" || true
  docker compose -f "$COMPOSE_FILE" images > "$BACKUP_DIR/compose.images.txt" || true
  local cid
  cid="$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE" | head -n 1 || true)"
  if [[ -n "$cid" ]]; then
    docker inspect "$cid" > "$BACKUP_DIR/container-$cid.json"
    OLD_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    ROLLBACK_IMAGE="xboard:rollback-${BACKEND_REF:0:8}-$(date -u +%s)"
    docker tag "$OLD_IMAGE" "$ROLLBACK_IMAGE" 2>/dev/null || true
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
EOF
  if [[ "$DISABLE_CADDY" == "1" ]]; then
    cat >> "$OVERRIDE" <<EOF
    environment:
      ENABLE_CADDY: "false"
    ports:
      - "127.0.0.1:8076:8076"
EOF
  fi
}

write_rollback_override() {
  [[ -n "$ROLLBACK_IMAGE" ]] || return 0
  cat > "$ROLLBACK_OVERRIDE" <<EOF
# Generated rollback override. Keep until the migration is accepted.
services:
  $SERVICE:
    image: $ROLLBACK_IMAGE
EOF
}

prepare_build_checkout() {
  local checkout="$BACKUP_DIR/source"
  if [[ -d "$checkout/.git" ]]; then
    log "reusing build checkout $checkout"
    git -C "$checkout" fetch --depth 1 origin "$BRANCH"
    git -C "$checkout" reset --hard "$BACKEND_REF"
  else
    log "cloning target source into $checkout"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$checkout"
    git -C "$checkout" fetch --depth 1 origin "$BACKEND_REF"
    git -C "$checkout" reset --hard "$BACKEND_REF"
  fi
  git -C "$checkout" submodule update --init --recursive --force
  local actual_admin
  actual_admin="$(git -C "$checkout" ls-tree HEAD public/assets/admin | awk '{print $3}')"
  [[ "$actual_admin" == "$ADMIN_REF" ]] || die "Target admin gitlink is $actual_admin, expected $ADMIN_REF"
  [[ "$(git -C "$checkout" rev-parse HEAD)" == "$BACKEND_REF" ]] || die "Target backend ref verification failed"
}

build_target() {
  local checkout="$BACKUP_DIR/source"
  prepare_build_checkout
  log "building target image $IMAGE"
  docker build --pull \
    --build-arg "REPO_URL=$REPO_URL" \
    --build-arg "BRANCH_NAME=$BRANCH" \
    --build-arg "CACHEBUST=$BACKEND_REF" \
    -t "$IMAGE" "$checkout"
  docker image inspect "$IMAGE" >/dev/null || die "Target image was not created"
  docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
    "grep -q 'TYPE_MX' /www/app/Models/Server.php && grep -q 'buildMxUri' /www/app/Utils/Helper.php && grep -q 'Mundo Connect 1' /www/public/assets/admin/assets/*.js" \
    || die "Target image does not contain the MX implementation and admin assets"
}

run_update() {
  local update_log="$BACKUP_DIR/xboard-update.log"
  log "stopping only service $SERVICE"
  "${COMPOSE[@]}" stop "$SERVICE"
  log "running controlled xboard:update with target image"
  local target_compose=(docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE")
  # Keep the image entrypoint so it can select array/sync drivers when the
  # embedded Redis process is not available in this disposable container.
  # Overriding the entrypoint bypasses that fallback and makes PhpRedis try a
  # missing socket/host during xboard:update.
  if ! "${target_compose[@]}" run --rm --no-deps -T "$SERVICE" sh -c 'exit 0' 2>&1 | tee "$update_log"; then
    return 1
  fi
  if grep -Eiq 'SQLSTATE\[|Migration table not found|\b(exception|fatal error|error):' "$update_log"; then
    warn "update output contains an error marker; see $update_log"
    return 1
  fi
}

start_and_check() {
  local target_compose=(docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE")
  log "starting target service"
  "${target_compose[@]}" up -d --no-build "$SERVICE"
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
  if [[ -n "$ROLLBACK_IMAGE" ]] && docker image inspect "$ROLLBACK_IMAGE" >/dev/null 2>&1; then
    write_rollback_override
    docker compose -f "$COMPOSE_FILE" -f "$ROLLBACK_OVERRIDE" up -d --no-build "$SERVICE" || true
  else
    warn "the old image tag is unavailable; using the original Compose image reference"
    "${COMPOSE[@]}" up -d --no-build "$SERVICE" || true
  fi
  warn "database was not automatically restored; use $BACKUP_DIR/mysql.sql.gz only after reviewing migration impact"
}

if [[ "$MODE" == "rollback" ]]; then
  [[ -d "$BACKUP_DIR" ]] || die "Snapshot directory not found: $BACKUP_DIR"
  [[ "$YES" == "1" ]] || die "Rollback is destructive; repeat with --yes after reviewing $BACKUP_DIR"
  [[ -f "$BACKUP_DIR/metadata.env" ]] || die "Snapshot metadata.env is missing"
  . "$BACKUP_DIR/metadata.env"
  [[ -n "${COMPOSE_FILE:-}" && -f "$COMPOSE_FILE" ]] || die "Snapshot metadata has no valid compose file"
  COMPOSE=(docker compose -f "$COMPOSE_FILE")
  log "rollback restores the previous image/configuration only; database restore is manual"
  if [[ -n "${ROLLBACK_IMAGE:-}" ]] && docker image inspect "$ROLLBACK_IMAGE" >/dev/null 2>&1; then
    cat > "$ROLLBACK_OVERRIDE" <<EOF
# Generated rollback override. Keep until the migration is accepted.
services:
  $SERVICE:
    image: $ROLLBACK_IMAGE
EOF
    "${COMPOSE[@]}" stop "$SERVICE" 2>/dev/null || true
    docker compose -f "$COMPOSE_FILE" -f "$ROLLBACK_OVERRIDE" up -d --no-build "$SERVICE"
  else
    warn "rollback image tag is unavailable; starting the original Compose definition"
    "${COMPOSE[@]}" stop "$SERVICE" 2>/dev/null || true
    "${COMPOSE[@]}" up -d --no-build "$SERVICE"
  fi
  exit 0
fi

print_plan
confirm
if [[ "$SKIP_DB_BACKUP" == "1" ]]; then
  warn "--skip-db-backup was supplied; database rollback will not be available"
else
  backup_mysql
fi
backup_state
write_rollback_override
build_target
write_override

if ! run_update; then
  rollback_service
  die "xboard:update failed; old service was restarted, review $BACKUP_DIR"
fi

if ! start_and_check; then
  rollback_service
  die "target service failed health checks; old service was restarted, review $BACKUP_DIR"
fi

log "migration completed"
log "snapshot: $BACKUP_DIR"
log "keep using: docker compose -f $(basename "$COMPOSE_FILE") -f $(basename "$OVERRIDE") up -d"
log "the original compose file, .env, database, volumes, and reverse proxy were preserved"
