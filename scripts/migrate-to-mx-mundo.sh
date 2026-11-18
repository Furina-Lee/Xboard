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
HEALTH_TIMEOUT=600
IMAGE=""
EDITION=""
BASE_OVERRIDE=""
MODE="dry-run"
YES=0
PROXY_CONTAINERS=()
STOPPED_PROXIES=()
UPGRADE=0
TOUCHED_SERVICE=0
SKIP_DB_BACKUP=0

usage() {
  cat <<EOF
Usage:
  migrate-to-mx-mundo.sh [options]

Modes:
  --dry-run                 Inspect and print the planned migration (default)
  --apply                   Back up, pull, update, and start the target service
  --upgrade                 Update the currently installed GHCR edition
  --rollback SNAPSHOT_DIR   Restore the old image/configuration from a snapshot

Options:
  --root DIR                Existing Compose project directory (default: current)
  --compose FILE            Compose file (default: compose.yaml or compose.yml)
  --service NAME            Xboard service name (default: xboard)
  --mysql-service NAME      Compose service containing mysqldump (default: Xboard service)
  --backup-dir DIR          Snapshot destination (default: sibling backup directory)
  --health-url URL          URL to check after startup
  --health-timeout SEC      Startup grace period in seconds (default: 600)
  --edition standard|full   Published edition (interactive selection if omitted)
  --image IMAGE             Override the published image reference
  --override FILE           Existing Compose override (auto-detects compose.mx-mundo.override.yaml)
  --proxy-container NAME    Include a custom reverse proxy (repeatable)
  --yes                     Skip confirmation, including listed proxy stops
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
    --upgrade) MODE="apply"; UPGRADE=1; shift ;;
    --proxy-container) PROXY_CONTAINERS+=("${2:?--proxy-container needs a name}"); shift 2 ;;
    --rollback)
      [[ $# -ge 2 ]] || die "--rollback requires a snapshot directory"
      MODE="rollback"; BACKUP_DIR="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --compose) COMPOSE_FILE="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --mysql-service) MYSQL_SERVICE="$2"; shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --health-url) HEALTH_URL="$2"; shift 2 ;;
    --health-timeout) HEALTH_TIMEOUT="${2:?--health-timeout needs a value}"; shift 2 ;;
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

[[ "$HEALTH_TIMEOUT" =~ ^[1-9][0-9]{0,5}$ ]] || die "--health-timeout must be a positive number of seconds"

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
if [[ "$MODE" != rollback ]]; then
  OVERRIDE="$ROOT/compose.mx-mundo.image.yaml"
  ROLLBACK_OVERRIDE="$ROOT/compose.mx-mundo.rollback.yaml"
  OLD_IMAGE=""
  ROLLBACK_IMAGE=""
  if [[ "$UPGRADE" == 1 ]]; then
    current_compose=("${COMPOSE[@]}")
    [[ ! -f "$OVERRIDE" ]] || current_compose+=(-f "$OVERRIDE")
    current_image="$("${current_compose[@]}" config --images "$SERVICE")"
    case "$current_image" in
      xboard:mx-mundo-1panel|ghcr.io/furina-lee/xboard:standard|ghcr.io/furina-lee/xboard:1panel|ghcr.io/furina-lee/xboard:standard-*) current_edition=standard ;;
      ghcr.io/furina-lee/xboard:full|ghcr.io/furina-lee/xboard:latest|ghcr.io/furina-lee/xboard:full-*) current_edition=full ;;
      *) die "Cannot infer edition from $current_image. Migrate to a published edition first." ;;
    esac
    [[ -z "$EDITION" || "$EDITION" == "$current_edition" ]] || die "--upgrade keeps the current edition"
    [[ -z "$IMAGE" ]] || die "--upgrade uses the published tag for the current edition"
    EDITION="$current_edition"
  elif [[ -e "$OVERRIDE" ]]; then
    die "Migration override already exists: $OVERRIDE. Use --upgrade."
  elif [[ -z "$EDITION" && -t 0 ]]; then
    printf '1) 标准版 standard（无 Caddy）\n2) 完整版 full（内置 Caddy）\n请选择版本 [1/2]: ' >&2
    read -r choice
    case "$choice" in 1|standard) EDITION=standard ;; 2|full) EDITION=full ;; *) die "Invalid edition selection" ;; esac
  fi
  EDITION="${EDITION:-standard}"
  case "$EDITION" in standard|full) ;; *) die "Unknown edition: $EDITION" ;; esac
  IMAGE="${IMAGE:-ghcr.io/furina-lee/xboard:$EDITION}"
  [[ "$IMAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./:@-]*$ ]] || die "Invalid image reference"
fi

# Detect common proxy images/names and let the operator include custom ones.
list_proxies() {
  local containers id image name explicit
  local -A selected=()
  containers="$(docker ps --no-trunc --format '{{.ID}} {{.Image}} {{.Names}}')" || return 1
  while read -r id image name; do
    [[ -n "$id" ]] || continue
    if [[ "${image,,} ${name,,}" =~ (^|[^a-z0-9])(nginx|openresty|traefik|caddy|haproxy|swag|envoy|reverse[-_]?proxy|zoraxy)([^a-z0-9]|$) ]]; then
      selected["$id"]="$name ($image)"
    fi
  done <<< "$containers"
  for explicit in "${PROXY_CONTAINERS[@]}"; do
    read -r id name < <(docker inspect -f '{{.Id}} {{.Name}} {{.State.Running}}' "$explicit") || return 1
    [[ "$name" == *" true" ]] || continue
    selected["$id"]="${name% true}"
  done
  PROXY_CONTAINERS=()
  for id in "${!selected[@]}"; do
    PROXY_CONTAINERS+=("$id")
    log "proxy to stop: ${selected[$id]} ($id)"
  done
}

restore_proxies() {
  local id result=0
  for id in "${STOPPED_PROXIES[@]}"; do
    docker start "$id" >/dev/null || result=1
  done
  return "$result"
}

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
  case "${DB_CONNECTION:-mysql}" in
    mysql) [[ -n "$DB_HOST" && -n "$DB_DATABASE" && -n "$DB_USERNAME" ]] || die "DB_HOST, DB_DATABASE, and DB_USERNAME must be present in .env" ;;
    sqlite) DB_DATABASE="${DB_DATABASE:-.docker/.data/database.sqlite}" ;;
    *) die "Only MySQL and SQLite deployments are supported" ;;
  esac
fi
DB_PORT="${DB_PORT:-3306}"

print_plan() {
  log "mode: $( [[ "$UPGRADE" == 1 ]] && printf upgrade || printf "%s" "$MODE" )"
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

if [[ "$MODE" != rollback && "$UPGRADE" == 0 && "$EDITION" == full ]]; then
  list_proxies || die "Could not inspect running proxy containers"
fi

if [[ "$MODE" == "dry-run" ]]; then
  print_plan
  log "dry-run complete; no service, volume, database, or file was changed"
  exit 0
fi

umask 077

confirm() {
  [[ "$YES" == "1" ]] && return 0
  if (( ${#PROXY_CONTAINERS[@]} )); then
    warn "Stopping these reverse proxies can interrupt other websites on this host"
  fi
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
  [[ ! -f "$OVERRIDE" ]] || cp -p "$OVERRIDE" "$BACKUP_DIR/previous-image.override.yaml"
  [[ -z "$BASE_OVERRIDE" ]] || cp -p "$BASE_OVERRIDE" "$BACKUP_DIR/existing-override.yaml"
  printf '%s\n' "$COMPOSE_CONFIG" > "$BACKUP_DIR/compose.resolved.yaml"
  "${COMPOSE[@]}" ps -a > "$BACKUP_DIR/compose.ps.txt" || true
  "${COMPOSE[@]}" images > "$BACKUP_DIR/compose.images.txt" || true
  local cid
  cid="$( "${COMPOSE[@]}" ps -a -q "$SERVICE" | head -n 1 || true)"
  [[ -n "$cid" ]] || die "Could not find an existing Xboard container to roll back to"
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
  if [[ "$UPGRADE" == 1 && -f "$BACKUP_DIR/previous-image.override.yaml" ]]; then
    # Keep environment overrides from a previous migration, replacing just the image.
    sed "s|^    image: .*|    image: $IMAGE|" "$BACKUP_DIR/previous-image.override.yaml" > "$OVERRIDE"
  elif [[ "$UPGRADE" == 0 && "$EDITION" == full ]]; then
    cat >> "$OVERRIDE" <<'EOF'
    environment:
      ENABLE_CADDY: "true"
      ENABLE_WS_SERVER: "true"
      OCTANE_PORT: "7002"
      CADDY_LISTEN_PORT: "7001"
EOF
  elif [[ "$UPGRADE" == 0 ]]; then
    cat >> "$OVERRIDE" <<'EOF'
    environment:
      ENABLE_CADDY: "false"
      ENABLE_WS_SERVER: "false"
      OCTANE_PORT: "7001"
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
  TOUCHED_SERVICE=1
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
  local started=$SECONDS deadline=$((SECONDS + HEALTH_TIMEOUT)) next_notice=$((SECONDS + 30))
  local remaining probe_timeout
  log "waiting up to ${HEALTH_TIMEOUT}s for HTTP readiness"
  while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || break
    probe_timeout=$((remaining < 5 ? remaining : 5))
    if "${target_compose[@]}" ps --status running --services | grep -Fxq "$SERVICE"; then
      if [[ -n "$HEALTH_URL" ]]; then
        if curl -fsL --max-time "$probe_timeout" "$HEALTH_URL" >/dev/null 2>&1; then
          log "health check passed: $HEALTH_URL"
          return 0
        fi
      elif "${target_compose[@]}" exec -T "$SERVICE" php -r '
        $port = getenv("ENABLE_CADDY") === "true"
            ? (getenv("CADDY_LISTEN_PORT") ?: 7001)
            : (getenv("OCTANE_PORT") ?: 7001);
        $context = stream_context_create(["http" => ["timeout" => 3]]);
        exit(@file_get_contents("http://127.0.0.1:$port/", false, $context) === false ? 1 : 0);
      ' >/dev/null 2>&1; then
        log "internal HTTP health check passed"
        return 0
      fi
    fi
    if (( SECONDS >= next_notice )); then
      log "still waiting for HTTP readiness ($((SECONDS - started))s elapsed, timeout ${HEALTH_TIMEOUT}s)"
      next_notice=$((SECONDS + 30))
    fi
    remaining=$((deadline - SECONDS))
    if (( remaining > 0 )); then
      sleep "$((remaining < 5 ? remaining : 5))"
    fi
  done
  warn "HTTP readiness timed out after ${HEALTH_TIMEOUT}s"
  "${target_compose[@]}" logs --no-color --tail=100 "$SERVICE" > "$BACKUP_DIR/startup.log" 2>&1 || true
  warn "Container startup logs saved to $BACKUP_DIR/startup.log"
  return 1
}

rollback_service() {
  warn "starting rollback to the original Compose image"
  "${COMPOSE[@]}" stop "$SERVICE" || true
  local result=0
  if [[ -n "$ROLLBACK_IMAGE" ]] && docker image inspect "$ROLLBACK_IMAGE" >/dev/null 2>&1; then
    write_rollback_override
    log "use rollback override: $ROLLBACK_OVERRIDE"
    local previous=("${COMPOSE[@]}")
    [[ ! -f "$BACKUP_DIR/previous-image.override.yaml" ]] || previous+=(-f "$BACKUP_DIR/previous-image.override.yaml")
    "${previous[@]}" -f "$ROLLBACK_OVERRIDE" up -d --no-deps --no-build --pull never "$SERVICE" || result=$?
  else
    warn "the old image tag is unavailable; using the original Compose image reference"
    "${COMPOSE[@]}" up -d --no-deps --no-build --pull never "$SERVICE" || result=$?
  fi
  warn "Database changes were not reverted. Review any database dump in $BACKUP_DIR."
  return "$result"
}

restore_override() {
  if [[ -f "$BACKUP_DIR/previous-image.override.yaml" ]]; then
    cp -p "$BACKUP_DIR/previous-image.override.yaml" "$OVERRIDE"
  elif [[ "$OVERRIDE" == "$ROOT/compose.mx-mundo.image.yaml" ]]; then
    rm -f "$OVERRIDE"
  fi
}

load_stopped_proxies() {
  [[ ! -f "$BACKUP_DIR/stopped-proxies.txt" ]] || mapfile -t STOPPED_PROXIES < "$BACKUP_DIR/stopped-proxies.txt"
}

if [[ "$MODE" == rollback ]]; then
  load_stopped_proxies
  result=0
  rollback_service || result=1
  restore_override || result=1
  restore_proxies || result=1
  [[ "$result" == 0 ]] || die "Rollback was incomplete; review $BACKUP_DIR"
  exit 0
fi

print_plan
[[ -z "$HEALTH_URL" ]] || command -v curl >/dev/null || die "curl is required with --health-url"
confirm
mkdir -p "$(dirname "$BACKUP_DIR")"
mkdir "$BACKUP_DIR"
if [[ "$SKIP_DB_BACKUP" == 1 ]]; then
  warn "--skip-db-backup was supplied; no database dump will be created"
elif [[ "$DB_CONNECTION" == sqlite ]]; then
  "${COMPOSE[@]}" exec -T "$SERVICE" sqlite3 -bail "$DB_DATABASE" .dump | gzip -c > "$BACKUP_DIR/sqlite.sql.gz"
  gzip -t "$BACKUP_DIR/sqlite.sql.gz"
else
  backup_mysql
fi
backup_state
pull_target

recover_on_exit() {
  local status="$1" result=0
  trap - EXIT INT TERM
  [[ "$status" != 0 ]] || return 0
  if [[ "$TOUCHED_SERVICE" == 1 ]]; then
    rollback_service || result=1
  fi
  restore_override || result=1
  restore_proxies || result=1
  if [[ "$result" == 0 ]]; then
    warn "Previous application and proxy configuration restored; see $BACKUP_DIR"
  else
    warn "Rollback was incomplete; see $BACKUP_DIR"
  fi
  exit "$status"
}
trap 'recover_on_exit $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
write_override
"${COMPOSE[@]}" -f "$OVERRIDE" config --quiet || die "Compose could not validate the image override"

for id in "${PROXY_CONTAINERS[@]}"; do
  [[ "$UPGRADE" == 0 && "$EDITION" == full ]] || break
  STOPPED_PROXIES+=("$id")
  printf '%s\n' "$id" >> "$BACKUP_DIR/stopped-proxies.txt"
  docker stop "$id" >/dev/null
done

run_update || die "xboard:update failed; review $BACKUP_DIR"
start_and_check || die "Target service failed health checks; review $BACKUP_DIR"
trap - EXIT INT TERM

log "migration/upgrade completed"
log "snapshot: $BACKUP_DIR"
printf "[migrate] keep using:"; printf " %q" "${COMPOSE[@]}" -f "$OVERRIDE" up -d; printf "\n"
if (( ${#STOPPED_PROXIES[@]} )); then
  log "External proxy containers remain stopped. Review $BACKUP_DIR/stopped-proxies.txt."
fi
