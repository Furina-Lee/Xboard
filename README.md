# Xboard MX / Mundo Edition

基于 Xboard 的代理协议管理面板，支持 MX 节点、Mundo Connect 1（`mc1`）、Mundo RDP（`mundordp`）和通用订阅中的 `mx://` URI。订阅客户端需要支持对应协议和传输方式。

## 用户端默认主题

内置 `Xboard` 主题使用 achen 1.4.4。新站点和已使用内置 `Xboard` 主题的站点升级后会直接加载新界面，已选用其他主题的站点保留原选择。可在后台配置主题颜色、背景及各平台客户端下载地址。

## 管理后台主题

管理员登录后，在右下角打开 **后台主题**，选择 **简约主题**、**原始主题**或已安装主题，再点 **应用到所有管理员**。选项保存在服务器中，其他管理员重新打开或刷新后台后会看到同一主题。首次设置前使用 `XBOARD_ADMIN_THEME` 指定的部署默认值，未指定时为简约主题。

### 创建并上传自己的主题

1. 保存以下内容为 `my-theme.json`，修改 ID 和配色。浅色与深色各至少填一项，未填写的颜色继承简约主题。颜色格式为整数 HSL 通道（色相 0–360，饱和度和亮度 0%–100%）。

   ```json
   {
     "id": "my-theme",
     "light": { "primary": "163 69% 26%", "primary-foreground": "0 0% 100%" },
     "dark": { "primary": "153 56% 69%", "primary-foreground": "163 44% 11%" }
   }
   ```

2. 在 **后台主题** 选择文件，点击 **校验并保存**。服务端检查文件大小（最多 4 KB）、JSON 结构、主题 ID、重复名称、允许的颜色变量与数值范围。校验通过后才会把色板写入数据库。上传支持 JSON 色板，样式表、脚本、归档和外部资源地址均不接受。
3. 在下拉列表中选择新主题，再点 **应用到所有管理员**。上传本身不会切换主题。

开发者可在 [后台前端产物仓库](https://github.com/Furina-Lee/xboard-admin-dist/tree/master) 复制 `themes/minimal/theme.css`，修改主题 ID 和选择器并用 `preview.html` 预览。需要自定义 CSS 布局时，将主题作为受信任的构建产物提交，更新主仓库的 `public/assets/admin` 子模块指针并部署新镜像。部署后，在后台选中新主题并点击 **应用到所有管理员**。完整的目录约定和预览步骤见[后台主题开发指南](https://github.com/Furina-Lee/xboard-admin-dist/blob/master/README.md#新建主题)。

## 机器与节点的 SSH 入口

1. 在 Apache Guacamole 创建 SSH 连接，配置 SSH 主机密钥校验，并为有权限的 Guacamole 账号授权。
2. 用该账号打开连接，从地址栏复制 `#/client/` 后面的客户端标识。若标识包含百分号转义，先解码一次。标识可能包含数据源信息，应使用浏览器地址中的标识。
3. 在 Xboard 的机器管理列表读取该机器的 `SID`。在部署目录的 `.env` 配置 HTTPS 网关和以 SID 为键的 JSON 对象：

   ```dotenv
   XBOARD_SSH_GATEWAY_URL=https://guacamole.example.com/guacamole
   XBOARD_SSH_CONNECTIONS='{"12":"MTIAYwBteXNxbA"}'
   ```

4. 在部署目录运行 `docker compose exec xboard php artisan config:clear`，然后运行 `docker compose restart xboard`。如部署使用多个 Compose 文件，请沿用相同的 `-f` 参数。

配置了连接的机器会显示 **SSH**，节点管理的部署方式列也会在所属机器旁显示入口。浏览器会在新标签页打开 Guacamole，由 Guacamole 处理登录、授权和 SSH 会话。

机器安装命令默认使用 [Furina-Lee/Xboard-Node](https://github.com/Furina-Lee/Xboard-Node) 的 `v1.13-furina.1` 安装脚本和二进制。在 **系统配置 → 节点设置** 可填写 `XBOARD_NODE_INSTALLER_URL` 和 `XBOARD_NODE_INSTALLER_VERSION`，点击 **保存节点安装设置** 后立即用于新生成的命令。地址使用兼容脚本的 HTTPS 原始文件地址，版本使用对应的发布标签。清空字段并保存会恢复部署默认值，可在 `.env` 中设置同名变量覆盖默认值。自有脚本需要支持机器模式、`--machine-id` 和 `--version`，并从预期仓库下载二进制。

Docker 部署节点可使用 `ghcr.io/furina-lee/xboard-node:v1.13-furina.1`。机器模式使用面板地址、SID 和机器 Token，分别对应 `API_HOST`、`MACHINE_ID` 和 `MACHINE_TOKEN`，也可以在 Compose 挂载的配置文件中填写。面板中的安装地址和版本字段用于 systemd 安装命令。参见 [节点 Docker Compose 说明](https://github.com/Furina-Lee/Xboard-Node/tree/compose)。

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
curl -fsSL --retry 3 https://raw.githubusercontent.com/Furina-Lee/Xboard/master/scripts/migrate-to-mx-mundo.sh -o migrate-to-mx-mundo.sh.new &&
bash -n migrate-to-mx-mundo.sh.new &&
mv migrate-to-mx-mundo.sh.new migrate-to-mx-mundo.sh
bash migrate-to-mx-mundo.sh --health-url http://127.0.0.1:7001/ --dry-run
bash migrate-to-mx-mundo.sh --health-url http://127.0.0.1:7001/ --apply
```

也可传 `--edition standard` 或 `--edition full`。迁移会备份 MySQL 或 SQLite 及部署配置、拉取镜像并更新数据库。完整版迁移会先列出并停止检测到的反向代理容器。自定义代理可用 `--proxy-container 容器名` 补充。代理停机可能影响同机其他站点。迁移失败时脚本会尝试恢复原镜像、原 Compose override 和本次停止的代理。数据库变更需根据备份单独处理。基础 Compose 和 `.env` 保持原样。迁移后按脚本打印的 Compose 命令启动，保留命令中的所有 `-f` 文件。详细参数及回滚见下文。

## 更新现有 Docker 部署

适用于本仓库的 GHCR 镜像及旧版 1Panel 本地镜像 `xboard:mx-mundo-1panel`。在原部署目录下载上面的最新版脚本后执行：

```bash
bash migrate-to-mx-mundo.sh --upgrade --health-url http://127.0.0.1:7001/
```

脚本识别现有版本，备份后拉取同版最新镜像，执行更新并检查 HTTP。首次启动默认最多等待 600 秒，可用 `--health-timeout 900` 延长到 15 分钟。超时时会在快照目录保存 `startup.log`。升级失败会尝试恢复旧镜像。升级保持外部代理运行。自定义 Compose 文件或 override 可通过 `--compose` 和 `--override` 指定。

### 下载返回 503 时

可通过 GitHub API 下载同一份脚本：

```bash
curl -fsSL --retry 3 \
  -H 'Accept: application/vnd.github.raw+json' \
  'https://api.github.com/repos/Furina-Lee/Xboard/contents/scripts/migrate-to-mx-mundo.sh?ref=master' \
  -o migrate-to-mx-mundo.sh.new &&
bash -n migrate-to-mx-mundo.sh.new &&
mv migrate-to-mx-mundo.sh.new migrate-to-mx-mundo.sh
```

MySQL 和 MariaDB 的备份命令使用 `--no-tablespaces`，应用账号无需为表空间导出获得 `PROCESS` 权限。如果旧脚本报这个错误，重新下载后再运行原命令。

### 手动回退

```bash
bash migrate-to-mx-mundo.sh --rollback /path/to/snapshot --yes
```

将路径替换为脚本输出的快照目录。手动回退恢复原应用镜像和部署配置，数据库使用备份单独恢复。

### 迁移脚本参数

| 参数 | 用途 |
| --- | --- |
| `--dry-run` | 默认模式，仅预览。加在 `--upgrade` 后可预览升级。 |
| `--apply` | 执行迁移。 |
| `--upgrade` | 识别当前版本并升级到对应的 GHCR 镜像。 |
| `--rollback SNAPSHOT_DIR` | 从指定快照回退，需加 `--yes`。 |
| `--edition standard\|full` | 指定标准版或完整版。迁移时交互终端省略此参数会提示选择，非交互默认标准版。 |
| `--root DIR` | 原部署目录，默认当前目录。 |
| `--compose FILE` | 主 Compose 文件，默认使用 `compose.yaml` 或 `compose.yml`。 |
| `--override FILE` | 已有 override 文件，默认检测 `compose.mx-mundo.override.yaml`。 |
| `--service NAME` | Xboard 服务名，默认 `xboard`。 |
| `--mysql-service NAME` | 执行 MySQL 导出的 Compose 服务，默认使用 Xboard 服务。 |
| `--backup-dir DIR` | 快照目录，默认在部署目录的上一级创建带时间戳的备份目录。 |
| `--image IMAGE` | 迁移时指定镜像，可填写固定版本标签。`--upgrade` 自动选取当前版本对应的发布标签。 |
| `--health-url URL` | 指定宿主机可访问的检查地址。省略时检查容器内的 HTTP。 |
| `--health-timeout SEC` | 等待 HTTP 就绪的秒数，默认 600。可传 `--health-timeout 900`。 |
| `--proxy-container NAME` | 迁移完整版时将自定义代理加入停机列表，可重复传入。 |
| `--skip-db-backup` | 跳过脚本的数据库备份，仅在已有外部备份时使用。 |
| `--yes` | 跳过确认，包括已列出的代理停机。 |
| `-h`、`--help` | 显示用法。 |
| `--dockerfile FILE` | 兼容旧命令。`Dockerfile` 对应完整版，`Dockerfile.1panel` 对应标准版。 |

例如，先预览 1Panel 升级，并给冷启动留出 15 分钟：

```bash
bash migrate-to-mx-mundo.sh --upgrade --dry-run \
  --health-url http://127.0.0.1:7001/ --health-timeout 900
```

- [已有部署迁移补充说明](./docs/en/installation/migrate-existing-compose.md)
- [GitHub Actions 构建记录](https://github.com/Furina-Lee/Xboard/actions/workflows/docker-publish.yml)
- [GitHub Container Registry](https://github.com/Furina-Lee/Xboard/pkgs/container/xboard)
