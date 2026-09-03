# 常见问题

## 构建与运行

**Q: `go build ./...` 报 `pattern all:dist: no matching files found`？**

`internal/web/fs.go` 通过 `//go:embed all:dist` 内嵌前端资源，必须先构建前端：

```bash
make frontend-dist   # 或 cd web && npm ci && npm run build
go build ./...
```

**Q: 在 Windows / macOS 上编译报 `undefined: syscall.SetsockoptString`、`undefined: syscall.Kill`？**

项目使用了 `SO_BINDTODEVICE` 等 Linux 专有接口，只能在 Linux 上本地编译。其他平台请交叉编译：

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -tags "with_utls nomsgpack" ./...
```

**Q: 启动时报 `读取配置文件失败` / 容器起来就退出？**

配置文件必须存在。指定路径：

```bash
vohive -c /path/to/config.yaml
# 或
CONFIG_PATH=/path/to/config.yaml vohive
```

Docker 镜像的入口脚本会在首次启动时自动生成 `/app/config/config.yaml`；裸机部署请先 `cp config/config.example.yaml config/config.yaml`。

**Q: 忘记 Web 登录密码怎么办？**

直接编辑配置文件中的 `web.username` / `web.password` 并重启服务。

## Docker

**Q: 为什么 `docker-compose.yml` 里没有 `ports` 映射？**

代理引擎通过 `SO_BINDTODEVICE` 把出口流量绑定到模组网卡，需要宿主机网络命名空间，因此使用 `network_mode: host`。此时端口映射无意义，服务直接绑定 `:7575`，代理端口也通过宿主机 IP 访问。

**Q: 容器里能点"在线更新"吗？**

不能。容器内请拉取新镜像后重建容器：

```bash
docker compose pull && docker compose up -d
```

界面检测到 `/.dockerenv` 时会提示改用镜像更新。

**Q: 插上新模组后容器里看不到设备？**

需要挂载 `/dev:/dev` 并以 `privileged: true` 运行，这样容器才能看到运行中添加的字符设备。

## 硬件与网络

**Q: 模组识别不到 / 串口不存在？**

1. 确认 `usbserial`/`option` 等内核驱动已加载：`lsmod | grep -E 'option|usbserial|qmi_wwan'`。
2. 确认容器/进程有 `/dev` 访问权限。
3. 用 `lsusb`、`dmesg | tail` 检查 USB 枚举与驱动绑定情况。
4. 部分模组需要切换 USB 模式（USBNET），可在设备配置中用 `usbnet_mode` 校验/设置。

**Q: 代理连上了但没有流量 / 走了宿主机默认路由？**

代理实例必须绑定 `device_id`，出口才会通过 `SO_BINDTODEVICE` 绑到对应网卡。请检查实例的 `device_id` 与设备 ID 是否一致，以及模组的数据连接是否已激活。

**Q: 轮换 IP（`POST /api/rotateip`）失败？**

通常需要重新拨号，检查：模组是否已注册网络、APN 是否正确（运行时策略按 ICCID 存储在数据库，可在 Web 界面「卡片策略」中调整）、运营商是否限制频繁重拨。

## VoWiFi / IMS

**Q: VoWiFi 无法建立隧道？**

VoWiFi/IMS 依赖内核 XFRM/IPsec。请安装与内核版本匹配的内核模块（不要跨内核强装 kmod）：

```text
kmod-ipsec  kmod-ipsec4  kmod-ipsec6
kmod-crypto-authenc  kmod-crypto-cbc  kmod-crypto-sha1
ip-full
```

同时需要 root 权限与 `CAP_NET_ADMIN`。

## eSIM

**Q: eSIM Profile 下载失败？**

- 确认 `esim_transport` 设置正确（`at` / `qmi` / `mbim`），不同模组支持情况不同。
- 下载流程会通过 `text/event-stream` 返回分步进度，可按 `step` 定位卡点（`preflight` / `auth_client` / `auth_server` / `install`）。
- 需要访问 SM-DP+ 服务器；国内网络可能需要配置 `HTTPS_PROXY`。

**Q: 切换 Profile 后模组无响应？**

可尝试在设备配置的 `esim_switch` 中开启 `event_gated_converge`、`radio_cycle`，或调整 `reinit_window_ms`（详见 [配置参考](CONFIGURATION.md)）。

## 通知

**Q: Telegram 推送收不到？**

- 服务器能直连 `api.telegram.org` 时无需额外配置；不能直连时填写 `telegram.base_url`（反代）或 `telegram.proxy`（HTTP 代理）。
- `chat_id` 必须正确；需要远程控制指令还要配置 `admin_id`。

**Q: 想自定义 Webhook 推送内容？**

修改 `webhook.text_template`，默认 `{{device_label}} {{text}}`，详见 [配置参考](CONFIGURATION.md)。

## 其他

**Q: 数据库在哪里？**

SQLite，路径由服务的数据目录决定（裸机默认 `data/`，Docker 为 `/app/data`，OpenWrt 为 `/var/lib/vohive/data`）。备份时请停止服务或确保无写入。

**Q: 可以商用吗？**

不可以。本项目采用 [PolyForm Noncommercial 1.0.0](../LICENSE)，仅限非商业用途。
