# API 使用说明

VoHive 的 HTTP API 前缀统一为 `/api`，与主服务共用同一个端口（默认 `7575`）。

## 在线文档

服务内建 Swagger UI 与 OpenAPI 3.0 规格，随二进制一起发布，无需额外部署：

| 路径 | 说明 |
| --- | --- |
| `GET /api/docs` | Swagger UI 页面。页面本身公开可访问，会在浏览器内读取 `localStorage.token` 后加载受保护的规格。 |
| `GET /api/openapi.yaml` | OpenAPI 规格（YAML，需鉴权）。 |
| `GET /api/openapi.json` | OpenAPI 规格（JSON，需鉴权）。 |

规格源文件位于 `internal/api/openapi.vohive.yaml`，修改后请同步更新（`internal/api/openapi_test.go` 会校验 YAML 合法性）。

## 鉴权

1. 调用 `POST /api/auth/login` 获取会话 token。
2. 后续请求在 Header 中携带 `Authorization: Bearer <token>`。

登录接口有频率限制，短时间内失败过多会返回 `429` 与 `code: rate_limited`。

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:7575/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin123"}' | jq -r .token)

curl -s http://127.0.0.1:7575/api/devices \
  -H "Authorization: Bearer $TOKEN"
```

登录成功响应：

```json
{
  "status": "ok",
  "token": "<session-token>",
  "expires_at": "2026-09-04T12:00:00Z"
}
```

失败响应示例：

```json
{
  "status": "error",
  "code": "rate_limited",
  "message": "登录尝试过于频繁，请稍后再试",
  "request_id": "..."
}
```

## 免鉴权接口

| 接口 | 说明 |
| --- | --- |
| `POST /api/auth/login` | 登录。 |
| `POST /api/rotateip` | 轮换公网 IP。支持 Bearer token，或请求体/表单里的 `username`、`password`。 |
| `GET /api/docs`、`GET /api/docs/assets/*` | 文档页与静态资源。 |
| `POST /api/system/uninstall` | 系统卸载（请谨慎调用）。 |
| `/api/websheets/*` | Web 表单会话，使用一次性会话 token 鉴权。 |

其余接口均需 Bearer token，缺失或过期返回 `401`。

## 主要分组

| 分组 | 说明 |
| --- | --- |
| `auth` | 登录、会话与 IP 轮换。 |
| `dashboard` | 仪表盘与全局状态。 |
| `devices` | 设备发现、生命周期、AT 指令、USSD、飞行模式、eSIM、E911、流量统计。 |
| `proxy` | SOCKS5/HTTP 代理实例的增删改查与启停。 |
| `sms` | 短信收发、会话与联系人。 |
| `settings` | 通知渠道等系统设置。 |
| `system` | 版本信息、更新检查、日志流。 |

完整路径、请求体与响应 schema 以 Swagger UI / OpenAPI 规格为准。

## 事件流

部分长任务以 `text/event-stream` 返回进度，例如 eSIM Profile 下载：

```text
{"step":"preflight","msg":"正在检查 eUICC 剩余空间...","pct":10}
{"step":"auth_client","msg":"...","pct":30}
{"step":"auth_server","msg":"...","pct":60}
{"step":"install","msg":"...","pct":80}
{"step":"notify","msg":"...","pct":90}
{"step":"done","msg":"Profile 下载完成","pct":100}
```

客户端需使用 `EventSource`（或等价实现）并保持连接直到收到 `done`。

## 推送回调

Webhook 通知会按 `webhook.text_template` 渲染文本后 POST 到配置的 `urls`，并附加 `webhook.headers` 中的自定义请求头；配置了 `secret` 时会附带签名，失败按 `retry_max` 重试。
