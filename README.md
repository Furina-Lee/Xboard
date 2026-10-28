# Xboard MX / Mundo Edition

Xboard 是一个基于 Laravel 和 Docker 的代理协议管理面板。本分支在 `cedar2025/Xboard` 基础上增加了：

- `mx` 节点类型
- Mundo Connect 1 传输协议，标识为 `mc1`
- Mundo RDP 传输协议，标识为 `mundordp`
- 通用订阅中的 `mx://` URI
- 管理端 MX 节点和 Mundo 传输选项

## 版本信息

本仓库的部署目标：

```text
项目仓库： https://github.com/Furina-Lee/Xboard.git
分支：     feature/mx-mundo-transport
后端提交： 180297ef9c8152b3f8d57ae34dfec79a32a22e69
管理端：   Furina-Lee/xboard-admin-dist
管理端提交：a0db13aa0ba9a861f1fbcb4a4ce4e8d612af5e2e
```

Docker 容器内部需要 PHP 8.2.35 或更高版本。宿主机不需要安装 PHP，Docker 镜像会提供运行环境。

## 目录

- [协议支持](#协议支持)
- [部署前准备](#部署前准备)
- [全新 Docker Compose 部署](#全新-docker-compose-部署)
- [全新 Docker Compose + MySQL 部署](#全新-docker-compose--mysql-部署)
- [1Panel 部署](#1panel-部署)
- [aaPanel + Docker 部署](#aapanel--docker-部署)
- [已有 Xboard 无缝迁移](#已有-xboard-无缝迁移)
- [迁移脚本参数](#迁移脚本参数)
- [日常维护](#日常维护)
- [常见问题](#常见问题)
- [安全注意事项](#安全注意事项)

## 协议支持

### MX 节点

后台新增节点时选择：

```text
MX
```

通用订阅会生成 `mx://` URI。

### Mundo Connect 1

Mundo Connect 1 是传输协议，标识为：

```text
mc1
```

可配置 `tcp`、WebSocket、mKCP 等模式需要的 `path`、`host`、`mode` 和 `cidrSegments` 参数。

### Mundo RDP

Mundo RDP 是传输协议，标识为：

```text
mundordp
```

支持以下设置：

- `username`
- `certificateFingerprint`
- `fakeTitle`
- `fakeMessage`
- `acceptProxyProtocol`
- `useTLSCertificate`

通用订阅可以输出这些传输参数。不同客户端对 MX、Mundo Connect 1 和 Mundo RDP 的支持范围不同，不支持的客户端格式可能会过滤这些节点。

## 部署前准备

### 推荐配置

- Linux VPS：Ubuntu 22.04+、Debian 12+ 或同等发行版
- Docker Engine
- Docker Compose v2
- 2 GB 以上内存
- 10 GB 以上可用磁盘空间
- 一个域名，推荐配置 HTTPS
- MySQL 5.7+ 或 MariaDB

安装 Docker：

```bash
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
docker --version
docker compose version
```

开放端口时通常只需要开放 80/443。应用内部默认使用 7001，建议只让 Nginx、OpenResty、Caddy 或 Cloudflare Tunnel 访问，不要直接暴露给公网。

## 全新 Docker Compose 部署

适用于没有旧版 Xboard 数据需要保留的全新部署。

### 1. 下载代码

```bash
mkdir -p /opt/xboard
cd /opt/xboard
git clone --recurse-submodules \
  -b feature/mx-mundo-transport \
  https://github.com/Furina-Lee/Xboard.git .
```

确认分支和子模块：

```bash
git branch --show-current
git submodule status
```

### 2. 创建 Compose 文件

普通部署使用：

```bash
cp compose.sample.yaml compose.yaml
```

这个模板使用桥接网络并发布 `7001:7001`。

### 3. 初始化安装

SQLite 适合测试或小规模使用：

```bash
docker compose run -it --rm \
  -e ENABLE_SQLITE=true \
  -e ENABLE_REDIS=true \
  -e ADMIN_ACCOUNT=admin@example.com \
  xboard php artisan xboard:install
```

安装程序会创建 `.env`。请保存输出的管理员账号、密码和后台地址。

### 4. 启动服务

```bash
docker compose up -d
docker compose ps
docker compose logs -f xboard
```

访问：

```text
http://服务器IP:7001
```

生产环境建议在反向代理后使用域名和 HTTPS。

## 全新 Docker Compose + MySQL 部署

适用于新建 MySQL 数据库的部署。

### 1. 准备 MySQL

创建数据库和用户，例如：

```text
数据库：xboard
用户：  xboard
权限：  xboard 数据库全部权限
```

确保 Xboard 容器可以访问 MySQL 主机和 3306 端口。

### 2. 下载并配置

```bash
mkdir -p /opt/xboard
cd /opt/xboard
git clone --recurse-submodules \
  -b feature/mx-mundo-transport \
  https://github.com/Furina-Lee/Xboard.git .
cp compose.sample.yaml compose.yaml
```

### 3. 初始化

```bash
docker compose run -it --rm xboard php artisan xboard:install
```

安装时填写：

- 数据库类型：MySQL
- 数据库地址：MySQL 容器名或可访问的数据库地址
- 数据库端口：3306
- 数据库名：xboard
- 数据库用户：xboard
- 数据库密码：创建用户时设置的密码
- Redis：根据提示选择内置 Redis 或现有 Redis

### 4. 启动

```bash
docker compose up -d
```

### 重要区别

`xboard:install` 只用于全新安装。已有 Xboard 数据库迁移时不要运行它，应该使用后面的迁移脚本。

## 1Panel 部署

1Panel 部署使用 1Panel 管理的 MySQL，并让 Xboard 加入外部 Docker 网络 `1panel-network`。

### 全新安装

进入 1Panel 网站目录：

```bash
cd /opt/1panel/apps/openresty/openresty/www/sites/xboard/index
```

下载代码：

```bash
git clone --recurse-submodules \
  -b feature/mx-mundo-transport \
  https://github.com/Furina-Lee/Xboard.git .
cp compose.1panel.sample.yaml compose.yaml
```

`compose.1panel.sample.yaml` 使用专用的 `Dockerfile.1panel`，保持原作者 1Panel 的无 Caddy 镜像方式：Octane 直接监听 7001，由 1Panel OpenResty 统一反向代理。该模板仍加入外部 Docker 网络 `1panel-network`。

初始化：

```bash
docker compose run -it --rm xboard php artisan xboard:install
```

数据库地址优先使用 1Panel 数据库连接信息中的容器连接地址。通常填写：

- 数据库主机：`mysql` 或 1Panel 显示的容器主机名
- 数据库端口：`3306`
- 数据库名：`xboard`
- 数据库用户：创建的数据库用户
- 数据库密码：创建数据库时保存的密码

启动：

```bash
docker compose up -d
```

### 1Panel 反向代理

原作者 1Panel 方式只需要将域名反向代理到容器的 7001 端口。此 1Panel 镜像不包含 Caddy；按原始配置不单独暴露或代理 8076。

```nginx
location ^~ / {
    proxy_pass http://127.0.0.1:7001;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_read_timeout 60s;
    proxy_buffering off;
    proxy_cache off;
}
```

### 1Panel 已有部署迁移

不要重新执行 `xboard:install`，不要更换为普通 `compose.sample.yaml`，也不要移除 `1panel-network`。

```bash
cd /opt/1panel/apps/openresty/openresty/www/sites/xboard/index
curl -fsSL \
  https://raw.githubusercontent.com/Furina-Lee/Xboard/feature/mx-mundo-transport/scripts/migrate-to-mx-mundo.sh \
  -o migrate-to-mx-mundo.sh
chmod +x migrate-to-mx-mundo.sh
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --dockerfile Dockerfile.1panel \
  --dry-run
```

确认计划中的 Dockerfile 是 `Dockerfile.1panel`、目标镜像名正确，参数无误后执行：

```bash
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --dockerfile Dockerfile.1panel \
  --image xboard:mx-mundo-1panel \
  --backup-dir /opt/1panel/backup/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url http://127.0.0.1:7001/ \
  --skip-db-backup \
  --apply
```

`Dockerfile.1panel` 基于原作者的无 Caddy 1Panel 镜像方式构建 MX 代码；外部 OpenResty 仍只代理到 7001，原有 Compose 网络、`.env` 和端口配置保持不变。因为已由 1Panel 完成数据库备份，此例使用 `--skip-db-backup`。

如果 Xboard 容器没有 `mysqldump`，指定 1Panel MySQL 服务名：

```bash
./migrate-to-mx-mundo.sh \
  --mysql-service 你的1Panel数据库服务名 \
  --backup-dir /opt/1panel/backup/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --apply
```

## aaPanel + Docker 部署

推荐使用 Docker 和 `compose.host.sample.yaml`，保持 `network_mode: host`，由 aaPanel Nginx 处理域名和 HTTPS。

### 全新安装

```bash
cd /www/wwwroot/your-domain
git clone --recurse-submodules \
  -b feature/mx-mundo-transport \
  https://github.com/Furina-Lee/Xboard.git .
cp compose.host.sample.yaml compose.yaml
docker compose run -it --rm xboard php artisan xboard:install
docker compose up -d
```

### aaPanel Nginx 反向代理

```nginx
location ^~ / {
    proxy_pass http://127.0.0.1:7001;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_read_timeout 60s;
    proxy_buffering off;
    proxy_cache off;
}
```

### aaPanel 已有 Docker 部署迁移

进入当前已有部署目录：

```bash
cd /www/wwwroot/your-domain
curl -fsSL \
  https://raw.githubusercontent.com/Furina-Lee/Xboard/feature/mx-mundo-transport/scripts/migrate-to-mx-mundo.sh \
  -o migrate-to-mx-mundo.sh
chmod +x migrate-to-mx-mundo.sh
./migrate-to-mx-mundo.sh --compose compose.yaml --service xboard --dry-run
```

确认无误后：

```bash
./migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --backup-dir /www/backup/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url https://你的域名/ \
  --apply
```

不要在迁移过程中：

- 执行 `git reset --hard`
- 执行 `update.sh`
- 执行 `xboard:install`
- 把 host network 改成普通桥接网络
- 把现有 MySQL 地址改成 `localhost` 或 `127.0.0.1`

必须保留当前 `.env`、MySQL 地址、端口、Nginx 配置和 Compose 网络模式。

## 已有 Xboard 无缝迁移

迁移脚本：

```text
scripts/migrate-to-mx-mundo.sh
```

适用于已经运行的 Docker Compose + MySQL、1Panel 和 aaPanel + Docker 部署。

### 迁移前原则

脚本：

- 不运行 `xboard:install`
- 不执行 `docker compose down -v`
- 不删除命名卷
- 不改写原始 `.env`
- 不改写原始 `compose.yaml`
- 保留现有 MySQL、Redis、端口、网络、卷和反向代理
- 默认先要求完成 MySQL 备份

### 先执行 dry-run

```bash
chmod +x scripts/migrate-to-mx-mundo.sh
./scripts/migrate-to-mx-mundo.sh --dry-run
```

指定 Compose 文件和服务：

```bash
./scripts/migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --dry-run
```

### 执行迁移

```bash
./scripts/migrate-to-mx-mundo.sh \
  --compose compose.yaml \
  --service xboard \
  --backup-dir /var/backups/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --health-url https://你的域名/ \
  --apply
```

脚本会要求输入：

```text
APPLY
```

### MySQL 服务没有 mysqldump 时

如果 Xboard 应用镜像不包含 `mysqldump`，可以指定同一个 Compose 项目中的 MySQL 服务：

```bash
./scripts/migrate-to-mx-mundo.sh \
  --mysql-service mysql \
  --backup-dir /var/backups/xboard/mx-mundo-$(date -u +%Y%m%dT%H%M%SZ) \
  --apply
```

MySQL 服务必须能访问 `.env` 中配置的 `DB_HOST`，并且容器中包含 `mysqldump`。

### 迁移过程

脚本会：

1. 检查 Docker、Compose、`.env` 和 Compose 服务。
2. 备份 MySQL 数据库。
3. 备份 `.env`、Compose 文件、容器信息和绑定目录。
4. 拉取并校验目标后端和管理端提交。
5. 构建目标 MX/Mundo 镜像。
6. 验证镜像内包含 MX 后端和管理端资源。
7. 只停止 Xboard 应用服务。
8. 执行 `php artisan xboard:update`。
9. 使用生成的 Compose override 启动新镜像。
10. 执行容器状态和可选 URL 健康检查。

### 迁移完成后启动

迁移成功后需要使用 override 文件：

```bash
docker compose \
  -f compose.yaml \
  -f compose.mx-mundo.override.yaml \
  up -d
```

不要删除：

```text
compose.mx-mundo.override.yaml
```

除非你已经决定切换到其他镜像。

### 回滚

```bash
./scripts/migrate-to-mx-mundo.sh \
  --rollback /var/backups/xboard/mx-mundo-备份时间 \
  --yes
```

回滚时必须继续使用原来的 Compose 文件和网络模式。不要使用另一份示例 Compose 文件替代原配置。

如果目标版本已经修改数据库，恢复旧镜像不等于恢复数据库。需要在维护窗口中根据备份的 `mysql.sql.gz` 手动恢复，并且恢复前应再次备份当前数据库。

## 日常维护

查看容器状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f xboard
```

重启服务：

```bash
docker compose \
  -f compose.yaml \
  -f compose.mx-mundo.override.yaml \
  restart xboard
```

升级前建议再次执行：

```bash
./scripts/migrate-to-mx-mundo.sh --dry-run
```

## 备份建议

至少备份以下内容：

- MySQL 数据库
- `.env`
- `compose.yaml`
- `.docker/.data`
- `storage/logs`
- `storage/theme`
- `plugins`
- Redis 命名卷或 Redis 数据
- 反向代理配置

不要把 `.env`、数据库密码、API 密钥、私钥或数据库备份提交到 GitHub。

## 常见问题

### 管理后台没有 MX 选项

确认使用了目标分支和管理端子模块：

```bash
git branch --show-current
git submodule status
git submodule update --init --recursive --force
```

如果使用迁移脚本，检查镜像是否构建自：

```text
Furina-Lee/Xboard
feature/mx-mundo-transport
```

不要使用默认的：

```text
ghcr.io/cedar2025/xboard:latest
```

### 502 或网站打不开

检查：

```bash
docker compose ps
docker compose logs --tail=200 xboard
```

然后确认：

- 反向代理目标端口是否仍为 7001
- 端口是否被其他程序占用
- 1Panel 是否仍连接 `1panel-network`
- aaPanel 是否仍使用原来的 host network 或端口映射
- `.env` 中 `APP_URL` 是否正确

### MySQL 连接失败

不要随意修改 `.env`。检查：

```bash
grep -E '^(DB_CONNECTION|DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME)=' .env
```

1Panel 部署优先使用容器连接地址；aaPanel Docker 部署必须保持当前能工作的数据库地址。

### WebSocket 连接失败

保留反向代理中的：

```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $http_connection;
```

如果是分离部署，还要确认 WebSocket 服务端口和 `/ws/` 路径配置。

## 安全注意事项

- 生产环境使用 HTTPS。
- 7001 不要直接暴露到公网，除非你明确知道风险。
- MySQL 不要开放给所有公网地址。
- 定期备份数据库并验证备份可恢复。
- 不要使用 `--skip-db-backup`，除非已经在其他位置完成并验证了数据库备份。
- 不要对已有数据库运行 `xboard:install`。
- 保留旧镜像和迁移快照，确认运行稳定后再清理。
- 升级前确认服务器磁盘空间足够，Docker 构建可能占用数 GB 空间。

## 相关文档

- [Docker Compose 详细部署](./docs/en/installation/docker-compose.md)
- [1Panel 原始部署说明](./docs/en/installation/1panel.md)
- [aaPanel + Docker 原始部署说明](./docs/en/installation/aapanel-docker.md)
- [已有部署迁移详细说明](./docs/en/installation/migrate-existing-compose.md)
- [插件开发指南](./docs/en/development/plugin-development-guide.md)

## License

本项目使用 MIT License，详见 [LICENSE](./LICENSE)。
