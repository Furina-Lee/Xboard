# Install Xboard with Docker Compose

Install Docker Engine and Docker Compose v2. For a new installation with SQLite and embedded Redis, run:

```bash
mkdir -p ~/xboard
cd ~/xboard
curl -fL https://raw.githubusercontent.com/Furina-Lee/Xboard/master/compose.sample.yaml -o compose.yaml
touch .env
docker compose pull
docker compose run --rm -e ENABLE_SQLITE=true -e ENABLE_REDIS=true xboard php artisan xboard:install
docker compose up -d
docker compose ps
```

The template uses the standard image. To use the full image with Caddy and WebSocket enabled by default, set the image tag to `full` in `compose.yaml` before pulling.

Save the admin credentials and URL printed by the installer. Open port 7001 through your HTTPS reverse proxy, or visit `http://SERVER:7001` for the initial check. To use MySQL, omit `-e ENABLE_SQLITE=true` and provide the database address reachable from the container.

For existing installations, follow the [image upgrade procedure](../../../README.md#更新现有-docker-部署).
