# Xboard MX / Mundo Edition

基于 Xboard 的代理协议管理面板，支持 MX 节点、Mundo Connect 1（`mc1`）、Mundo RDP（`mundordp`）和通用订阅中的 `mx://` URI。订阅客户端需要支持对应协议和传输方式。

## 用户端默认主题

内置 `Xboard` 主题使用 achen 1.4.4。新站点和已使用内置 `Xboard` 主题的站点升级后会直接加载新界面，已选用其他主题的站点保留原选择。可在后台配置主题颜色、背景及各平台客户端下载地址。

## 管理后台主题

管理员登录后，在侧栏 **主题配置** 下方打开 **后台主题**，可查看 **简约主题**、**原始主题**、**Liquid Glass** 和已上传的主题。在主题卡片上点击 **应用到所有管理员** 即可切换。选项保存在服务器中，其他管理员重新打开或刷新后台后会看到同一主题。首次设置前使用 `XBOARD_ADMIN_THEME` 指定的部署默认值，未指定时为简约主题。

### 创建并上传自己的主题

1. 保存以下内容为 `my-theme.json`，修改 ID 和配色。浅色与深色各至少填一项，未填写的颜色继承简约主题。颜色格式为整数 HSL 通道（色相 0–360，饱和度和亮度 0%–100%）。

   ```json
   {
     "id": "my-theme",
     "light": { "primary": "163 69% 26%", "primary-foreground": "0 0% 100%" },
     "dark": { "primary": "153 56% 69%", "primary-foreground": "163 44% 11%" }
   }
   ```

2. 在 **后台主题** 点击 **上传主题**，选择 JSON 色板。服务端检查文件大小（最多 4 KB）、JSON 结构、主题 ID、重复名称、允许的颜色变量与数值范围。校验通过后才会把色板写入数据库。上传支持 JSON 色板，样式表、脚本、归档和外部资源地址均不接受。
3. 在下拉列表中选择新主题，再点 **应用到所有管理员**。上传本身不会切换主题。

开发者可在 [后台前端产物仓库](https://github.com/Furina-Lee/xboard-admin-dist/tree/master) 复制 `themes/minimal/theme.css`，修改主题 ID 和选择器并用 `preview.html` 预览。需要自定义 CSS 布局时，将主题作为受信任的构建产物提交，更新主仓库的 `public/assets/admin` 子模块指针并部署新镜像。部署后，在后台选中新主题并点击 **应用到所有管理员**。完整的目录约定和预览步骤见[后台主题开发指南](https://github.com/Furina-Lee/xboard-admin-dist/blob/master/README.md#新建主题)。

## 选择节点部署方式

| 场景 | 部署方式 | 凭据 |
| --- | --- | --- |
| 新装机器，或一台机器管理多个节点 | [从服务器管理一键安装](https://github.com/Furina-Lee/MX-WebSocket-Node/blob/dev/README.md#a-服务器管理一键安装) | 机器 ID 和机器 Token，面板自动加入命令 |
| 新装独立单节点或单独测试 MX | [手动安装独立单节点](https://github.com/Furina-Lee/MX-WebSocket-Node/blob/dev/README.md#b-手动安装独立单节点) | 节点 ID 和面板服务端通信密钥 |
| 维护已有的旧版 Xboard-Node 容器 | [旧版节点 Docker Compose](https://github.com/Furina-Lee/MX-WebSocket-Node/tree/compose) | 沿用旧版部署的配置 |

新版 MX 节点需使用节点机上已有的原版 `proxy-node`，全新机器先解压对应架构的二进制。面板需启用 WebSocket，反代需支持 `/ws` 升级，并执行 `node_traffic_reports` 数据库迁移。

在 **系统配置 → 节点设置** 可覆盖节点安装地址和版本。默认地址为 `https://raw.githubusercontent.com/Furina-Lee/MX-WebSocket-Node/dev/install.sh`。版本覆盖会传给安装脚本作为 `--version`，仅使用包含新版安装器及配套文件的 Git 标签或提交。清空并保存可恢复部署默认；如部署的 `.env` 仍定义 `XBOARD_NODE_INSTALLER_URL` 或 `XBOARD_NODE_INSTALLER_VERSION`，也需核对其中的值。自定义脚本须兼容 `--mode machine --panel --token --machine-id`，固定版本时还须兼容 `--version`。

### Loon 完整配置

在后台 **系统配置 → 订阅模板 → Loon** 编辑模板，修改后自动保存。`[Proxy]` 段中保留独占一行的 `{{PROXIES}}`，面板会在此填入用户有权使用的兼容节点。策略组里可以用 `{{PROXY_NAMES}}` 引用这些节点，无兼容节点时替换为 `DIRECT`。DNS、分流和远程规则可按 Loon 的配置格式编写。

在用户的订阅链接后添加 `?format=loon-config`。如果已经有查询参数，用 `&format=loon-config`。把生成的 URL 作为 **远程配置** 导入 Loon。用户订阅 API 也会返回 `loon_config_url`。在 **系统配置 → 订阅设置** 打开 **Loon 通用订阅下发完整配置** 后，Loon 的「远程配置」可直接使用通用订阅链接。此开关默认关闭。打开后，旧的 Loon 远程节点订阅可在链接上添加 `format=loon-nodes`，继续获取节点列表。

### 部署 MX 节点

在面板创建并启用 MX 节点，绑定到目标机器，再从 **服务器管理** 复制机器安装命令。新版独立节点会发现已启用的节点并获取配置。准备原版 `proxy-node` 与核验 WebSocket 的步骤见 [MX WebSocket 节点安装说明](https://github.com/Furina-Lee/MX-WebSocket-Node/blob/dev/README.md)。

#### MC1 配置模板

选择 MX 的 Mundo Connect 1 传输后，协议配置编辑器可插入 MC1 模板。默认 `mode` 为 `auto`，`host` 取 TLS 的 SNI，`path` 为斜杠加 16 位随机十六进制字符。每次插入模板或复制节点会生成新的路径。保存已有节点时保留明确填写的路径和 Host。

SNI 输入框右侧的按钮可生成形如 `mx-<随机值>.example` 的合法域名。该名称用于配置，无需 DNS 解析。若启用常规证书校验，应使用与实际服务端证书匹配的 SNI。无 Docker 的部署在更新管理后台文件后，可运行 `php scripts/patch-admin-mc1.php` 生成新版管理后台资源。

#### MundoRDP 配置模板

MX 节点的传输选择切到 MundoRDP 后，协议配置立即载入一个只含 `username` 的模板。用户名由 `user` 加 12 位随机十六进制字符组成。打开已有 MundoRDP 节点时会保留现有配置；可以在协议配置编辑器中主动插入新模板。

### 升级到流量配额修复版

先在面板部署目录按[更新现有 Docker 部署](#更新现有-docker-部署)升级 Xboard。更新脚本会备份数据库并执行迁移。面板恢复访问后，确认配额上报迁移状态为 **Ran**：

```bash
docker compose exec xboard php artisan migrate:status | grep node_traffic_reports
```

若部署使用多个 Compose 文件，请沿用实际部署的全部 `-f` 参数。确认迁移完成后，继续使用旧版 Docker 节点的机器可按 [旧版 Compose 升级说明](https://github.com/Furina-Lee/MX-WebSocket-Node/tree/compose) 更新到 `v1.13-furina.7`。迁移到新版独立节点时，按 [MX WebSocket 安装说明](https://github.com/Furina-Lee/MX-WebSocket-Node/blob/dev/README.md) 操作，并在迁移窗口释放旧监听端口。若面板曾保存自定义安装地址或版本，还需检查面板设置及 `.env`，清除旧覆盖后重新生成机器安装命令。

## Docker 镜像

两个版本使用相同的 Xboard 面板代码，均支持 MX/Mundo、内置 Redis 和 Linux AMD64 / ARM64。两种镜像都默认启动节点 WebSocket worker，HTTP 和 WebSocket 的入口方式不同。

| | 标准版 | 完整版 |
| --- | --- | --- |
| 镜像 | `ghcr.io/furina-lee/xboard:standard` | `ghcr.io/furina-lee/xboard:full` |
| HTTP 入口 | Octane 直接监听 `7001` | Caddy 监听 `7001`，转发给 Octane |
| 节点 WebSocket | worker 默认开启，外部反代将 `/ws` 转发到 `8076` | worker 默认开启，内置 Caddy 在 `7001` 处理 `/ws` |
| 适用场景 | 1Panel OpenResty、aaPanel Nginx 等外部反向代理，以及直接访问面板 | 希望通过同一个容器入口代理 HTTP 和 WebSocket |

完整版的 Caddy 在容器内提供 HTTP 转发。公网 HTTPS 可交由宿主机上的反向代理处理。WebSocket 入口与 MX 节点兼容性还取决于节点端实现。

GitHub Actions 从 `master` 构建镜像。可用 `standard-<SHA>` 或 `full-<SHA>` 固定版本。兼容标签 `1panel` 对应标准版，`latest` 对应完整版。

### 节点 WebSocket 与 1Panel 反代

| 参数 | 标准版默认值 | 完整版默认值 | 用途 |
| --- | --- | --- | --- |
| `ENABLE_WS_SERVER` | `true` | `true` | 是否启动节点 WebSocket worker |
| `ENABLE_CADDY` | `false` | `true` | 是否使用容器内 Caddy |
| `OCTANE_PORT` | `7001` | `7002` | 面板 HTTP 服务在容器内的监听端口 |
| `WS_HOST` | `0.0.0.0` | `127.0.0.1` | worker 在容器内的绑定地址 |
| `WS_PORT` | `8076` | `8076` | worker 在容器内的监听端口 |
| `CADDY_LISTEN_PORT` | 未使用 | `7001` | 完整版容器的 HTTP / WebSocket 统一入口 |

Xboard 后台「系统配置 → 节点配置」的 WebSocket 开关与容器变量分开生效。后台需要开启 WebSocket，且能从缓存读取 worker 心跳，才会向节点公布 WebSocket 地址。使用 HTTPS 面板时，节点应收到可访问的 `wss://你的面板域名/ws`。若 TLS 在反代终止，请正确转发 `X-Forwarded-Proto`；也可在后台显式设置完整的 `wss://` 地址。

**1Panel / 标准版**

1. 在「容器 → 编排」检查 Xboard 服务的 Compose 配置。旧编排或旧迁移生成的 override 可能仍有 `ENABLE_WS_SERVER: "false"`，需要改为 `"true"` 或删除该覆盖。要应用镜像或环境变量变更，请重新创建容器。单纯重启不会加载新的 Compose 环境变量。
2. 宿主机运行 OpenResty 时，保留现有 HTTP 映射，并增加 `127.0.0.1:8076:8076`。新版 [1Panel Compose 模板](./compose.1panel.sample.yaml) 已包含此映射。若已有端口占用，可用 `127.0.0.1:18076:8076`，并把反代上游端口改成 `18076`。如果反代本身在容器内，且与 Xboard 在同一 Docker 网络，用 Xboard 容器的网络别名和 `8076`，不要用反代容器自己的 `127.0.0.1`。
3. 在 1Panel 对应网站的 OpenResty 配置中，站点原来的 HTTP 上游继续指向 `7001`。在同一个 `server` 块内添加或修改下面的 `/ws` 规则。此例适用于宿主机上的 OpenResty。

```nginx
location = /ws {
    proxy_pass http://127.0.0.1:8076;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
    access_log off;
}
```

**完整版**

外部 HTTPS 反代只需将面板 HTTP 和 `/ws` 都送到 `7001`，并传递 WebSocket 升级头。容器内 Caddy 会把 `/ws` 转到 worker，无需向宿主机发布 `8076`。

**验收**

```bash
docker compose ps
docker compose logs --tail=100 xboard | grep -Ei 'Starting services|ws-server|websocket'
```

容器启动日志应出现 `ws=true`，随后出现 `ws-server` 进入 `RUNNING` 的记录。若 worker 已运行但面板依然返回 `websocket.enabled=false`，检查后台开关及 Web 与 worker 是否使用同一缓存连接和前缀。若已经返回地址却无法连接，检查 HTTPS 证书、`/ws` 代理和访问规则。最后在节点机确认日志出现 `Machine WebSocket connected with traffic acknowledgements`，用测试节点产生一笔流量并到面板确认入账。

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
