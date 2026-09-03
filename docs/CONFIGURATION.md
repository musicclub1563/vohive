# 配置参考

VoHive 使用单个 YAML 配置文件。路径由 `-c` 参数或 `CONFIG_PATH` 环境变量指定，默认 `config/config.yaml`。

```bash
cp config/config.example.yaml config/config.yaml
```

- 配置文件**必须存在**，缺失时服务会直接退出（Docker 镜像的入口脚本会在首次启动时自动从示例配置生成）。
- 修改配置后需要重启服务生效；部分运行时策略（APN、IP 版本、飞行模式等）可在 Web 界面直接调整并落库。
- 环境变量可覆盖任意配置项：前缀 `PROXY_`，层级分隔符 `.` 替换为 `_`，例如 `PROXY_SERVER_PORT=:8080`、`PROXY_DEVICES_0_APN=cmnet`。

## server

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `port` | string | `7575` | HTTP 监听端口，可写 `7575` 或 `:7575`。 |
| `debug` | bool | `false` | 开启 Gin/日志调试模式。 |

## web

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `username` | string | `admin` | Web 控制台登录用户名。 |
| `password` | string | `admin` | Web 控制台登录密码，**首次登录后请立即修改**。 |

## devices

设备列表，数组。多数路径类字段由运行时自动探测（配置里写了也不会读取）。

```yaml
devices:
  - device_backend: qmi      # 设备后端: at|qmi|mbim|auto，默认 at
    id: wwan0                # 设备标识（通常对应网卡名）
    name: "SIM 卡 1"         # 显示名称
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 设备标识。 |
| `name` | string | 显示名称。 |
| `modem_imei` | string | 可选，按 IMEI 绑定设备，避免插拔后顺序变化导致错位。 |
| `device_backend` | string | 设备后端模式：`at` / `qmi` / `mbim` / `auto`。 |
| `esim_transport` | string | eSIM 通道：`at`（默认）/ `qmi` / `mbim`。 |
| `mbim_transport` | string | MBIM 传输：`auto`（默认）/ `proxy` / `direct`。 |
| `qmi_use_proxy` | bool | 是否通过 libqmi `qmi-proxy` 打开 QMI 控制口。 |
| `qmi_proxy_path` | string | 可选，`qmi-proxy` abstract socket 名称，留空用默认值。 |
| `qmi_proxy_executable` | string | 可选，`qmi-proxy` 可执行文件路径，留空用默认值。 |
| `usbnet_mode` | int | 可选，用于校验/设置 Quectel USBNET 模式。 |
| `proxy_port` | int | 该设备默认代理端口。 |
| `operator_selection_mode` | string | 运营商选择模式。 |
| `operator_selection_plmn` | string | 运营商选择 PLMN。 |
| `operator_selection_rat` | string | 运营商选择接入技术。 |
| `baud_rate` / `data_bits` / `stop_bits` / `parity` | int/int/int/string | 串口参数，留空使用默认值。 |
| `esim_switch` | object | eSIM 切换行为微调，见下表。 |

以下字段为**运行时策略**（按 ICCID 投影自数据库中的 `card_policies`），配置文件中的同名项不会被读取：`apn`、`network_enabled`、`ip_version`、`vowifi_enabled`、`airplane_enabled`、`sms_enabled`。

### devices[].esim_switch

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `use_refresh_true` | bool | 主切换路径使用 `refresh=true`。 |
| `event_gated_converge` | bool | 使用 UIM indication 事件来门控切换后的收敛。 |
| `radio_cycle` | bool | 在切换前后执行 LowPower → Online 射频循环。 |
| `reinit_window_ms` | int | UIM 重初始化窗口（毫秒），`0` 表示关闭。仅在 `event_gated_converge=true` 时生效。 |

## proxy

代理内核实例列表。通常直接在 Web 界面「代理」页面管理，配置文件的改动会在保存时写回。

```yaml
proxy:
  instances:
    - id: p1
      name: "卡1代理"
      device_id: wwan0        # 绑定设备，出口流量按网卡绑定
      enabled: true
      mode: socks5            # socks5|http
      listen_addr: 0.0.0.0
      listen_port: 10801
      auth_enabled: false
      username: ""
      password: ""
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 实例唯一标识。 |
| `name` | string | 显示名称。 |
| `device_id` | string | 绑定设备 ID，出口流量通过 `SO_BINDTODEVICE` 严格绑定该设备网卡。 |
| `enabled` | bool | 是否启用。 |
| `mode` | string | `socks5` 或 `http`。 |
| `listen_addr` | string | 监听地址。 |
| `listen_port` | int | 监听端口，取值 `1`–`65535`。 |
| `auth_enabled` | bool | 是否启用代理认证。启用时 `username`/`password` 不能为空。 |

## telegram

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | 是否启用。 |
| `bot_token` | string | - | BotFather 签发的 Token。 |
| `chat_id` | int64 | `0` | 接收通知的会话 ID。 |
| `admin_id` | int64 | `0` | 允许下发控制指令的管理员 ID。 |
| `base_url` | string | - | Telegram API 反代地址，形如 `https://api.telegram.org/bot%s/%s`。 |
| `proxy` | string | - | 出站 HTTP 代理，形如 `http://127.0.0.1:7890`。 |

## feishu

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `enabled` | bool | 是否启用。 |
| `app_id` / `app_secret` | string | 飞书开放平台应用凭证。 |
| `chat_ids` | []string | 接收通知的群聊 chat_id 列表。 |
| `chat_id` | string | 兼容旧配置的单个 chat_id，为空且 `chat_ids` 为空时会自动迁移。 |

## qq

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `enabled` | bool | 是否启用。 |
| `app_id` / `app_secret` | string | QQ 开放平台应用凭证。 |
| `group_ids` | string | 逗号分隔的群组 OpenID。 |
| `direct_ids` | string | 逗号分隔的私聊 OpenID。 |

## webhook

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | 是否启用。 |
| `urls` | []string | - | 接收推送的地址列表。 |
| `text_template` | string | `{{device_label}} {{text}}` | 文本模板，支持 `{{device_label}}`、`{{text}}` 等占位符。 |
| `headers` | map | - | 附加请求头。 |
| `secret` | string | - | 签名密钥。 |
| `timeout_ms` | int | `5000` | 单次请求超时（毫秒）。 |
| `retry_max` | int | `3` | 最大重试次数。 |

## bark

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | 是否启用。 |
| `urls` | []string | - | Bark 推送地址列表。 |
| `group` | string | `vohive` | 推送分组。 |
| `icon` | string | - | 推送图标 URL。 |
| `level` | string | `active` | 推送级别。 |

## email

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | 是否启用。 |
| `use_ssl` | bool | `false` | 是否使用 SSL（否则按需 STARTTLS）。 |
| `smtp_host` | string | - | SMTP 服务器地址。 |
| `smtp_port` | int | `0` | SMTP 端口。 |
| `username` / `password` | string | - | SMTP 账号密码。 |
| `from_address` | string | - | 发件人地址。 |
| `to_addresses` | []string | - | 收件人地址列表。 |

## pushplus

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `enabled` | bool | `false` | 是否启用。 |
| `token` | string | - | PushPlus Token。 |
| `topic` | string | - | 群组编码。 |
| `channel` | string | `wechat` | 推送渠道。 |

## vowifi

```yaml
vowifi:
  enabled: false
  device_id: ""          # 留空则取第一个设备
  mode: vowifi           # vowifi|volte（当前会回退为 vowifi）
  voice_gateway:
    sip:
      listen: "0.0.0.0:5060"
      transport: udp     # udp|tcp|tls
      realm: vohive
      external_ip: ""    # 公网 IP，可选
    users:
      - username: "1001"
        password: "secret"
        display_name: "分机 1001"
        device_id: wwan0 # 绑定的设备
    media:
      rtp_port_min: 20000
      rtp_port_max: 20100
      codecs: ["PCMU", "PCMA"]
    linphone_push:
      linphone_user: ""
      linphone_password: ""
```

`sip.listen` 非空时语音网关自动启用。VoWiFi/IMS 依赖内核 XFRM/IPsec，详见 [FAQ](FAQ.md)。

## 安全建议

- 不要把 `config/config.yaml` 提交到仓库（已被 `.gitignore` 排除），只提交 `config.example.yaml`。
- Bot Token、SMTP 密码、Webhook secret 等敏感信息优先通过环境变量或受保护的文件注入。
