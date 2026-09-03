# VoHive

4G/5G 模组管理平台 - 支持移远 EC20/EC25/RM500Q 等移远模组的统一管理与代理服务。

## 🚀 快速开始

### 1. 创建目录与配置文件

```bash
mkdir -p vohive/{config,data,logs}
cd vohive
curl -fsSL https://raw.githubusercontent.com/musicclub1563/vohive/master/docker-compose.hub.yml -o docker-compose.yml
```

首次启动会在 `./config` 下自动生成 `config.yaml`（由入口脚本从示例配置复制），之后可直接在宿主机编辑并重启容器生效。

### 2. 启动服务

```bash
docker compose up -d
docker compose logs -f
```

### 3. 访问 Web 界面

打开浏览器访问: `http://<宿主机 IP>:7575`

默认账号: `admin` / `admin123`，**登录后请立即在「设置」中修改密码**。

> 使用 `network_mode: host`，端口映射不生效，服务直接绑定 `:7575`。
> 代理端口同样通过宿主机 IP 访问，无需单独映射。

## 📦 镜像标签

镜像发布在 GitHub Container Registry：

| 标签 | 说明 |
|------|------|
| `ghcr.io/musicclub1563/vohive:latest` | 最新稳定版 |
| `ghcr.io/musicclub1563/vohive:<version>` | 指定版本号（如 `1.0.0`） |

多架构 manifest 覆盖 `linux/amd64` 与 `linux/arm64`；需要 `armv7` 请使用 Release 二进制。

## 🔧 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CONFIG_PATH` | `/app/config/config.yaml` | 配置文件路径 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `HTTP_PROXY` / `HTTPS_PROXY` | 空 | 可选出站代理，用于 Telegram / SM-DP+ / 更新检查 |

其余配置项通过 `config.yaml` 设置，详见 [docs/CONFIGURATION.md](docs/CONFIGURATION.md)。

## 📁 数据卷

| 路径 | 说明 |
|------|------|
| `/app/config` | 配置文件目录（首次启动自动播种） |
| `/app/data` | SQLite 数据库与持久化状态 |
| `/app/logs` | 日志文件 |
| `/dev` | 模组热插拔与 USB 设备发现所需 |

## 🔄 更新

容器内不支持二进制热替换，请拉取新镜像后重建容器：

```bash
docker compose pull
docker compose up -d
```

## 🖥️ 支持架构

- `linux/amd64` (x86_64)
- `linux/arm64` (ARM64/aarch64)

## 📖 文档

- [配置参考](docs/CONFIGURATION.md)
- [部署指南](docs/DEPLOYMENT.md)
- [API 说明](docs/API.md)
- [常见问题](docs/FAQ.md)

完整文档见仓库根目录 [README.md](README.md)。

## 📝 License

本项目基于 [PolyForm Noncommercial License 1.0.0](LICENSE) 开源，**仅限非商业用途**：可自由查看、使用、修改、分发源码用于个人学习、研究、测试等非商业场景；**禁止任何形式的商业使用**（包括但不限于销售、提供付费服务、用于盈利性产品或业务）。如需商业授权，请联系作者另行协商。
