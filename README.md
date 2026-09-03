# VoHive

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm--Noncommercial--1.0.0-blue.svg)](https://polyformproject.org/licenses/noncommercial/1.0.0)
[![Go](https://img.shields.io/badge/Go-1.26%2B-00ADD8?logo=go)](go.mod)
[![Vue 3](https://img.shields.io/badge/Vue-3-42b883?logo=vue.js)](web/package.json)

> 面向高通 4G/LTE/5G 模组（Quectel EC20/EC25/EC21/EG25/EM20 等）的综合管理与代理服务平台。

VoHive 把模组热插拔管理、SOCKS5/HTTP 代理编排、短信收发、VoWiFi/IMS 通话、eSIM 全生命周期管理整合到一个服务里，并提供一套现代化的响应式 Web 管理后台。

## 核心特性

| 模块 | 说明 |
| --- | --- |
| 多模组并发管理 | USB 热插拔自动发现（ttyUSB 等）、多设备实时状态监控 |
| 轻量级代理引擎 | 内建 SOCKS5 / HTTP 代理内核，支持多实例并发；基于 `SO_BINDTODEVICE` 按设备网卡严格绑定出站流量 |
| 通信与短信中心 | 统一界面/API 处理 AT 短信收发、会话与联系人管理、USSD 交互，短信落库可查 |
| eSIM 管理 | 通过 AT 指令通道直接管理 eSIM 芯片，支持 Profile 下载、启用/停用、重命名、删除 |
| 全渠道通知 | 重要短信及系统告警可推送至 Telegram、Email、PushPlus、Bark、飞书（Lark/Feishu）、QQ 等 |
| 多架构构建 | 原生支持 amd64 / arm64 / armv7 跨平台编译，路由器到边缘节点均可部署 |

## 典型应用场景

- **私有 IP 代理池**：单主机挂载多张物理 SIM 卡或多张 eSIM，每张网卡对应独立的 SOCKS5/HTTP 实例，组建自己的移动网络代理。
- **统一接码/验证码中心**：Web 界面或 API 并行收发多卡短信，并通过 Webhook/Bot 实时推送到个人终端。
- **VoWiFi 零信号通信**：地下室、弱覆盖场景下，借助宽带网络隧道建立 IMS 连接，保证业务不掉线。

## 快速开始

### Docker Compose（推荐）

```bash
mkdir -p vohive/{config,data,logs}
cd vohive
curl -fsSL https://raw.githubusercontent.com/1239t/vohive/master/docker-compose.hub.yml -o docker-compose.yml
docker compose up -d
```

首次启动会在 `./config` 下生成 `config.yaml`（由入口脚本从 `config.example.yaml` 复制），随后可直接在宿主机上编辑并 `docker compose restart` 生效。

打开 `http://<宿主机 IP>:7575`，默认账号 `admin` / `admin123`，**登录后请立即在「设置」中修改密码**。

> 代理引擎通过 `SO_BINDTODEVICE` 把出口流量绑定到模组网卡，需要宿主机网络命名空间，因此 Compose 使用 `network_mode: host`，端口映射不生效。

### 从源码构建本地镜像

```bash
git clone https://github.com/1239t/vohive.git
cd vohive
docker compose up -d --build     # 使用仓库根目录的 docker-compose.yml
```

### 预编译二进制

从 [GitHub Releases](https://github.com/1239t/vohive/releases) 下载对应架构的产物并校验：

| 平台 | Release 文件 |
| --- | --- |
| Linux x86-64 | `vohive_vX.Y.Z_linux_amd64` |
| Linux ARM64 | `vohive_vX.Y.Z_linux_arm64` |
| Linux ARMv7 | `vohive_vX.Y.Z_linux_armv7` |

```bash
sha256sum -c SHA256SUMS --ignore-missing
sudo install -d -m 0755 /opt/vohive/bin /opt/vohive/data /etc/vohive
sudo install -m 0755 vohive_vX.Y.Z_linux_amd64 /opt/vohive/bin/vohive
sudo cp config/config.example.yaml /etc/vohive/config.yaml
sudo /opt/vohive/bin/vohive -c /etc/vohive/config.yaml
```

作为常驻服务运行请参考 [部署文档](docs/DEPLOYMENT.md)，其中含 systemd 单元与 OpenWrt 打包说明。

## 配置

VoHive 读取单个 YAML 配置文件，路径由 `-c` 参数或 `CONFIG_PATH` 环境变量指定，默认 `config/config.yaml`。

```bash
cp config/config.example.yaml config/config.yaml
```

完整配置项（服务端、账号、设备、通知渠道、VoWiFi、上游代理等）见 **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)**。

部分字段支持环境变量覆盖（前缀 `PROXY_`，点号替换为下划线），例如 `PROXY_SERVER_PORT=:8080`。

## API 文档

服务内建 Swagger UI 与 OpenAPI 3.0 规格，随二进制一起发布：

| 路径 | 说明 |
| --- | --- |
| `GET /api/docs` | Swagger UI 页面（公开访问，浏览器内读取本地 token） |
| `GET /api/openapi.yaml` | OpenAPI 规格（YAML） |
| `GET /api/openapi.json` | OpenAPI 规格（JSON） |

调用方式：`POST /api/auth/login` 获取 token，之后请求头携带 `Authorization: Bearer <token>`。

## 开发

环境要求：Go 1.26+、Node.js 20+。

```bash
make frontend-dev   # 前端开发服务器 :5173（已配置 /api 反向代理到 :7575）
make run            # 运行后端
make test           # Go 单元测试
make lint           # gofmt 检查 + go vet
make build          # 构建 linux/amd64 产物（含前端）
make build-all      # 构建 amd64 / arm64 / armv7
make help           # 查看全部目标
```

> `internal/web/fs.go` 通过 `//go:embed all:dist` 内嵌前端资源，因此**在构建前端之前，`go build ./...` 会失败**。先执行 `make frontend-dist`（`make build` 已自动依赖该步骤）。

更多内容见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 发布流程

推送版本标签后会触发两个 GitHub Actions 工作流：

- `binary-release` 构建并发布 amd64 / arm64 / armv7 二进制与 `SHA256SUMS`；
- `docker` 构建并推送多架构镜像到 GHCR。

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 项目结构

```text
cmd/vohive/              主服务入口
cmd/vohive-relay/        中继组件
cmd/mbimprobe/           MBIM 探测工具
internal/api/            HTTP API、OpenAPI 规格与 Swagger UI 资源
internal/device/         模组发现、热插拔与设备控制
internal/modem/          AT 会话与响应处理
internal/qmi/            QMI 通道与网络配置
internal/mbim/           MBIM 通道
internal/esim/           eSIM/eUICC 生命周期管理
internal/proxy/          SOCKS5/HTTP 代理内核与流量统计
internal/sms/            短信收发与编解码
internal/notify/         多渠道通知（Telegram/飞书/QQ/Bark/Email/PushPlus/Webhook）
internal/vowifihost/     VoWiFi/IMS 通话宿主
internal/db/             SQLite 持久化（GORM）
internal/web/            内嵌前端资源（go:embed all:dist）
web/                     Vue 3 + Vite + TypeScript + Element Plus 前端
packaging/openwrt/       OpenWrt 软件包
packaging/systemd/       systemd 服务单元
scripts/                 容器入口脚本等运维脚本
docs/                    文档
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | 全部配置项说明 |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Docker、二进制、systemd、OpenWrt 部署 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 本地开发、测试、代码结构约束 |
| [docs/API.md](docs/API.md) | API 鉴权与调用示例 |
| [docs/FAQ.md](docs/FAQ.md) | 常见问题与排查 |

## 免责声明

- **用途定位**：本项目主要面向个人学习、技术研究与功能测试场景，不建议直接用于生产环境或关键业务系统；由此产生的部署及使用风险由使用者自行承担。
- **非官方项目**：VoHive 为第三方独立开发的开源软件，与 Quectel（高通模组厂商）、高通公司及其他任何模组/芯片厂商均无官方关联、授权或合作关系，亦不对模组硬件本身的功能、质量或安全性负责。
- **合规使用**：使用本项目搭建的服务时，请自行确保符合所在地区的法律法规及电信运营商的服务条款，不得用于任何违法违规用途。因违规使用造成的一切法律责任由使用者自行承担，与本项目作者及贡献者无关。
- **无担保**：本软件按"现状"提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性及不侵权担保。因使用或无法使用本软件（含数据丢失、设备异常、业务中断等）造成的任何直接或间接损失，作者及贡献者不承担任何责任。

## License

本项目基于 [PolyForm Noncommercial License 1.0.0](LICENSE) 开源，**仅限非商业用途**：可自由查看、使用、修改、分发源码用于个人学习、研究、测试等非商业场景；**禁止任何形式的商业使用**（包括但不限于销售、提供付费服务、用于盈利性产品或业务）。如需商业授权，请联系作者另行协商。
