# Install Xboard with 1Panel and Docker Compose

Follow the [Docker Compose setup](./docker-compose.md) with the [1Panel Compose template](../../../compose.1panel.sample.yaml) saved as `compose.yaml`. It uses the `ghcr.io/furina-lee/xboard:standard` image and joins the external `1panel-network`. For MySQL, omit `-e ENABLE_SQLITE=true` and use the database container name on that network. Configure the 1Panel reverse proxy to use host port 7001.

For an existing deployment, preserve the database, volumes, network and effective Compose overrides when [switching images](../../../README.md#更新现有-docker-部署).
