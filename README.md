# Xboard MX / Mundo Edition

基于 Xboard 的代理协议管理面板，支持 MX 节点、Mundo Connect 1（`mc1`）、Mundo RDP（`mundordp`）和通用订阅中的 `mx://` URI。订阅客户端需要支持对应协议和传输方式。

## Docker 镜像

两个版本使用相同的 Xboard 面板代码，均支持 MX/Mundo、内置 Redis 和 Linux AMD64 / ARM64。区别在于 HTTP 入口和节点 WebSocket 的默认配置。

| | 标准版 | 完整版 |
| --- | --- | --- |
| 镜像 | `ghcr.io/furina-lee/xboard:standard` | `ghcr.io/furina-lee/xboard:full` |
| HTTP 入口 | Octane 直接监听 `7001` | Caddy 监听 `7001`，转发给 Octane |
| 节点 WebSocket | 独立服务默认关闭 | 独立服务默认开启，由 Caddy 转发 `/ws`，沿用 `7001` |
| 适用场景 | 1Panel OpenResty、aaPanel Nginx 等外部反向代理，以及直接访问面板 | 需要默认启用 Xboard-Node WebSocket 入口的部署 |

完整版的 Caddy 在容器内提供 HTTP 转发。公网 HTTPS 可交由宿主机上的反向代理处理。WebSocket 入口与 MX 节点兼容性还取决于节点端实现。

GitHub Actions 从 `master` 构建镜像。可用 `standard-<SHA>` 或 `full-<SHA>` 固定版本。兼容标签 `1panel` 对应标准版，`latest` 对应完整版。

## 全新安装

在 Linux 上准备 [Docker Engine 和 Docker Compose v2](https://docs.docker.com/engine/install/) 及 `curl`。以下两条命令任选其一，在终端执行。安装器会使用空目录、SQLite 和内置 Redis，并提示输入管理员邮箱。

**标准版**

```bash
installer="$(curl -fsSL https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/install.sh)" && bash -c "$installer" -- standard "$HOME/xboard"
```

**完整版**

```bash
installer="$(curl -fsSL https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/install.sh)" && bash -c "$installer" -- full "$HOME/xboard"
```

保存安装程序输出的管理员凭据和后台路径，访问 `http://服务器地址:7001`。排查启动问题可在部署目录执行 `docker compose logs --tail=100 xboard`。

### MySQL 和面板管理

- **1Panel**：将安装命令中的 `standard` 换成 `1panel`。安装器使用[专用 Compose 模板](./compose.1panel.sample.yaml)，连接外部 Docker 网络 `1panel-network`。选择 MySQL 时填写该网络上的数据库容器名。反向代理指向宿主机 `127.0.0.1:7001`。
- **其他 MySQL 部署**：按 [Compose 手动安装教程](./docs/en/installation/docker-compose.md) 初始化，安装时选择 MySQL。
- **aaPanel**：使用标准版并将站点反向代理指向 `127.0.0.1:7001`。需要宿主机网络时，可使用 [host 模板](./compose.host.sample.yaml)。

## 迁移已有 Docker 部署

在现有部署目录下载脚本并预览，确认输出的 Compose 文件、服务名、镜像、已有 override 和备份目录。在终端省略 `--edition` 会提示选择标准版或完整版。

```bash
curl -fsSL https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/migrate-to-mx-mundo.sh -o migrate-to-mx-mundo.sh
bash migrate-to-mx-mundo.sh --health-url http://127.0.0.1:7001/ --dry-run
bash migrate-to-mx-mundo.sh --health-url http://127.0.0.1:7001/ --apply
```

也可传 `--edition standard` 或 `--edition full`。迁移会备份 MySQL 或 SQLite 及部署配置、拉取镜像并更新数据库。完整版迁移会先列出并停止检测到的反向代理容器。自定义代理可用 `--proxy-container 容器名` 补充。代理停机可能影响同机其他站点。迁移失败时脚本会尝试恢复原镜像、原 Compose override 和本次停止的代理。数据库变更需根据备份单独处理。基础 Compose 和 `.env` 保持原样。迁移后按脚本打印的 Compose 命令启动，保留命令中的所有 `-f` 文件。详细参数及回滚见[迁移教程](./docs/en/installation/migrate-existing-compose.md)。

## 更新现有 Docker 部署

对于已使用本仓库 GHCR 镜像的部署，在原部署目录运行：

```bash
curl -fsSL https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/migrate-to-mx-mundo.sh -o migrate-to-mx-mundo.sh
bash migrate-to-mx-mundo.sh --upgrade --health-url http://127.0.0.1:7001/
```

脚本识别现有版本，备份后拉取同版最新镜像，执行更新并检查 HTTP。升级失败会尝试恢复旧镜像。升级保持外部代理运行。自定义 Compose 文件或 override 可通过 `--compose` 和 `--override` 指定。

- [已有部署迁移补充说明](./docs/en/installation/migrate-existing-compose.md)
- [GitHub Actions 构建记录](https://github.com/Furina-Lee/Xboard/actions/workflows/docker-publish.yml)
- [GitHub Container Registry](https://github.com/Furina-Lee/Xboard/pkgs/container/xboard)
