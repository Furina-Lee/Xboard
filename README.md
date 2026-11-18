# Xboard MX / Mundo Edition

基于 Xboard 的代理协议管理面板，支持 MX 节点、Mundo Connect 1（`mc1`）、Mundo RDP（`mundordp`）和通用订阅中的 `mx://` URI。订阅客户端需要支持对应协议和传输方式。

## Docker 镜像

| 镜像 | 用途 | 架构 |
| --- | --- | --- |
| `ghcr.io/furina-lee/xboard:latest` | 标准部署，包含 Caddy 和 WebSocket 服务 | AMD64、ARM64 |
| `ghcr.io/furina-lee/xboard:1panel` | 1Panel，由 Octane 在 7001 提供 HTTP | AMD64、ARM64 |

默认分支 `master` 由 GitHub Actions 构建。也可使用带完整提交 SHA 的 `latest-<SHA>` 或 `1panel-<SHA>` 标签固定版本。

## 全新安装

在 Linux 上准备 [Docker Engine 和 Docker Compose v2](https://docs.docker.com/engine/install/)，确认 `docker compose version` 可以运行。以下命令使用 SQLite 和内置 Redis。

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

按提示填写管理员邮箱，保存安装程序输出的管理员凭据和后台路径。浏览器访问 `http://服务器地址:7001`，正式使用时由反向代理提供 HTTPS。排查启动问题可运行 `docker compose logs --tail=100 xboard`。

### MySQL 和面板管理

- **MySQL**：在安装命令中去掉 `-e ENABLE_SQLITE=true`，选择 MySQL，填写容器可访问的数据库地址和凭据。
- **1Panel**：下载 [1Panel Compose 模板](./compose.1panel.sample.yaml) 保存为 `compose.yaml`。确认数据库容器接入 `1panel-network`，安装时填写数据库容器名。使用 1Panel 的反向代理指向宿主机 `127.0.0.1:7001`。
- **aaPanel**：使用标准 Compose 模板，站点反向代理指向宿主机 `127.0.0.1:7001`。需要宿主机网络时，使用 [host 模板](./compose.host.sample.yaml)。

## 更新现有 Docker 部署

先备份数据库、`.env` 和现有 Compose 文件，记录当前镜像版本。在当前部署目录中执行：

```bash
docker compose pull xboard
docker compose up -d xboard
docker compose ps
docker compose logs --tail=100 xboard
```

从自建镜像切换到 GHCR 时，在正在使用的 Compose 文件（含 override）中，把 Xboard 服务的 `image:` 改成对应的 GHCR 镜像并移除该服务的 `build:`。先用 `docker compose config --images` 核对最终生效的镜像，再执行更新。保留现有数据库、挂载、网络和端口。已有部署无需运行 `xboard:install`。

- [已有部署迁移补充说明](./docs/en/installation/migrate-existing-compose.md)
- [GitHub Actions 构建记录](https://github.com/Furina-Lee/Xboard/actions/workflows/docker-publish.yml)
- [GitHub Container Registry](https://github.com/Furina-Lee/Xboard/pkgs/container/xboard)
