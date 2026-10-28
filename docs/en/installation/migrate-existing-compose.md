# Migrating an Existing Docker Compose Deployment

This procedure replaces the Xboard application image with the MX/Mundo build while preserving an existing MySQL database, `.env`, Compose networks, ports, volumes, and reverse proxy configuration.

The migration script is:

```text
scripts/migrate-to-mx-mundo.sh
```

It targets:

```text
Repository: https://github.com/Furina-Lee/Xboard.git
Ref:        feature/mx-mundo-transport
Backend:    180297ef9c8152b3f8d57ae34dfec79a32a22e69
Admin:      a0db13aa0ba9a861f1fbcb4a4ce4e8d612af5e2e
```

## Before You Start

Run the script from the existing Compose deployment directory, not from a fresh source checkout. The directory must contain the existing `.env` and Compose file.

Do not run `php artisan xboard:install` against the existing database. Installation can detect a non-empty database and offer to wipe it.

The script does not run `docker compose down -v`, does not edit `.env`, and does not delete named volumes.

## Dry Run

Copy the script into the existing deployment directory, make it executable, and inspect the planned values:

```bash
chmod +x scripts/migrate-to-mx-mundo.sh
./scripts/migrate-to-mx-mundo.sh --dry-run
```

For a deployment with a non-default service name or Compose file:

```bash
./scripts/migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --dry-run
```

The dry run does not stop containers, write the backup directory, change Compose, or touch MySQL.

## MySQL Backup Requirement

The script expects `DB_CONNECTION=mysql`, `DB_HOST`, `DB_DATABASE`, and `DB_USERNAME` in `.env`. It runs `mysqldump` in a disposable Compose container. If the Xboard image does not contain `mysqldump`, use a MySQL service from the same Compose project:

```bash
./scripts/migrate-to-mx-mundo.sh \
  --mysql-service mysql \
  --dry-run
```

The selected service must be able to reach the configured `DB_HOST` and contain `mysqldump`. The dump is written as `mysql.sql.gz` in the snapshot directory and is checked with `gzip -t` before the migration proceeds.

If the database is managed outside Docker and no Compose service has `mysqldump`, create a verified backup separately and only then use `--skip-db-backup` with an explicit understanding that the script cannot perform an automatic database restore.

## Apply

Use a backup directory outside the live deployment directory when possible:

```bash
./scripts/migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --backup-dir /var/backups/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url https://panel.example.com/ \
  --apply
```

The script asks you to type `APPLY`. To run it non-interactively:

```bash
./scripts/migrate-to-mx-mundo.sh \
  --backup-dir /var/backups/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url https://panel.example.com/ \
  --apply --yes
```

The script:

1. Resolves the current Compose project and service.
2. Backs up MySQL, `.env`, Compose output, runtime container metadata, and bind-mounted state.
3. Clones and verifies the target backend/admin commits into the snapshot directory.
4. Builds a separately tagged image with explicit repository/ref build arguments.
5. Stops only the Xboard service.
6. Runs `php artisan xboard:update` once using the target image.
7. Starts the target service with a generated `compose.mx-mundo.override.yaml`.
8. Checks the service state and optional health URL.

Existing MySQL, Redis, reverse-proxy, ports, networks, volumes, and `.env` are reused.

## After a Successful Migration

Use the generated override on future starts:

```bash
docker compose \
  -f compose.yaml \
  -f compose.mx-mundo.override.yaml \
  up -d
```

Do not remove the override until the target image has been intentionally replaced by another image.

## 1Panel Deployment

For a 1Panel deployment, run the migration from the existing site directory, normally:

```bash
cd /opt/1panel/apps/openresty/openresty/www/sites/xboard/index
```

Confirm that the current Compose file is the 1Panel variant and that it still joins the external `1panel-network`:

```bash
grep -n "1panel-network" compose.yaml
docker compose config >/dev/null
```

Copy the migration script into this directory. If the script has already been pushed to your GitHub branch, you can download it with:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Furina-Lee/Xboard/feature/mx-mundo-transport/scripts/migrate-to-mx-mundo.sh \
  -o migrate-to-mx-mundo.sh
chmod +x migrate-to-mx-mundo.sh
```

Run a dry run first:

```bash
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --dry-run
```

Then apply the migration. Keep the existing `.env` values unchanged, especially the 1Panel MySQL container hostname, database name, username, password, and `REDIS_*` settings. Since 1Panel OpenResty is the external reverse proxy, disable the embedded Caddy and use a local health URL:

```bash
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --backup-dir /opt/1panel/backup/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url http://127.0.0.1:7001/ \
  --disable-caddy \
  --skip-db-backup \
  --apply
```

`--disable-caddy` writes `ENABLE_CADDY=false` to the generated override and publishes the container's WebSocket port on `127.0.0.1:8076`. Configure OpenResty to proxy `/ws` to that port and the remaining HTTP traffic to `127.0.0.1:7001`.

The Xboard service must be able to reach the existing 1Panel MySQL container through `1panel-network`. Do not replace `compose.1panel.yaml` with the default bridge template during this migration. The script changes the application image and the requested Caddy/WS override while leaving `.env`, the database, and the OpenResty configuration untouched.

If the existing Xboard image does not contain `mysqldump`, identify the 1Panel MySQL container service name and pass it explicitly:

```bash
./migrate-to-mx-mundo.sh \
  --mysql-service 1Panel-mysql-xxxx \
  --backup-dir /opt/1panel/backup/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --apply
```

Use the exact container/service name shown in 1Panel. The service must be attached to the same network and contain the MySQL client tools.

After a successful migration, keep using the generated override:

```bash
docker compose \
  -f compose.yaml \
  -f compose.mx-mundo.override.yaml \
  up -d
```

## aaPanel + Docker Deployment

For aaPanel + Docker, the recommended existing layout uses `compose.host.yaml` and `network_mode: host`. Run the migration from the current website directory:

```bash
cd /www/wwwroot/your-domain
```

Do not run `git reset --hard`, `update.sh`, or `xboard:install` in this directory. Preserve the current `.env`, `compose.yaml`, and aaPanel Nginx configuration.

Download the migration script:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Furina-Lee/Xboard/feature/mx-mundo-transport/scripts/migrate-to-mx-mundo.sh \
  -o migrate-to-mx-mundo.sh
chmod +x migrate-to-mx-mundo.sh
```

Run the dry run:

```bash
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --dry-run
```

Then apply it:

```bash
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --backup-dir /www/backup/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url https://panel.example.com/ \
  --apply
```

Because host networking is preserved, the existing MySQL host value must remain valid inside the container. For example, do not change a working external MySQL hostname to `localhost` or `127.0.0.1` unless that is how the current deployment already connects. The script preserves the existing port and host-network setup; aaPanel Nginx continues proxying to the same address and port.

If the current aaPanel Compose file uses bridge mode instead of host mode, do not switch modes as part of this migration. Keep the current network and port mapping, and use the same command with that existing `compose.yaml`.

After the migration:

```bash
docker compose \
  -f compose.yaml \
  -f compose.mx-mundo.override.yaml \
  up -d
```

If aaPanel uses Supervisor for any separate Octane or WebSocket process, restart only those processes if they are part of the current deployment. The all-in-one Docker image normally manages its own web and WebSocket processes.

## Rollback

The script restores the old Compose service configuration and image reference from the original Compose file. It does not blindly reverse database migrations:

```bash
./migrate-to-mx-mundo.sh \
  --rollback /var/backups/xboard/mx-mundo-YYYYMMDDTHHMMSSZ \
  --yes
```

For 1Panel or aaPanel, rollback must use the same original Compose file and network mode. Do not restore with a different `compose.sample.yaml`, because that can detach the service from `1panel-network` or change host networking and break the existing MySQL/reverse-proxy path.

If the target update changed the database and the old image cannot run with the new schema, restore `mysql.sql.gz` manually after reviewing the consequences. A database restore is destructive and should be done only with a separate maintenance window and an additional current backup.
