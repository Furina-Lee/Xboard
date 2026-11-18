# Migrate an existing Docker Compose deployment

The migration script replaces the Xboard service image in an existing MySQL deployment. It retains the base Compose file, existing override, environment file, mounts, network and reverse proxy configuration. It creates a MySQL dump and a local rollback image before stopping Xboard. The database schema can change during the migration.

## Preview and apply

Run from the existing deployment directory. Use Docker Compose v2 with support for the `!reset` Compose tag.

```bash
curl -fsSL https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/migrate-to-mx-mundo.sh -o migrate-to-mx-mundo.sh
bash migrate-to-mx-mundo.sh --edition standard --health-url http://127.0.0.1:7001/ --dry-run
bash migrate-to-mx-mundo.sh --edition standard --health-url http://127.0.0.1:7001/ --apply
```

Choose `--edition full` for built-in Caddy and the default WebSocket service. Choose `--edition standard` for direct Octane HTTP on port 7001, including 1Panel deployments backed by OpenResty. If the service is published on another port, pass the actual URL. Set `--compose FILE` or `--service NAME` if your setup uses different names. The script detects `compose.mx-mundo.override.yaml` and accepts `--override FILE` for other existing overrides. Pass the same options to preview and apply.

By default the script runs the MySQL dump client using the Xboard service network. Use `--mysql-service NAME` to select a different Compose service containing a compatible dump client, or use `--skip-db-backup` after making an external backup. Keep the snapshot private because it contains deployment credentials and database data.

## Start after migration

Use the exact Compose command printed by the script. For example, with both overrides:

```bash
docker compose -f compose.yaml -f compose.mx-mundo.override.yaml -f compose.mx-mundo.image.yaml up -d
```

For subsequent image updates, use that same file list with `pull xboard` and `up -d xboard`.

## Roll back the application image

From a trusted snapshot created by the script:

```bash
bash migrate-to-mx-mundo.sh --rollback /path/to/snapshot --yes
```

The script restarts the previous image and prints the rollback override to use for future starts. Database restoration is a separate operation. Review the migration log and the saved MySQL dump before restoring data.
