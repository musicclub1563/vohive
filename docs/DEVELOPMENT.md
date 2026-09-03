# 开发指南

## 环境要求

- Go 1.26+（`go.mod` 中声明的版本，CI 使用 `go-version-file: go.mod` 自动匹配）
- Node.js 20+ 与 npm
- Linux 主机（代码使用了 `SO_BINDTODEVICE`、`syscall.Kill` 等 Linux 专有接口，在 Windows/macOS 上 **`go build ./...` 会失败**）

Windows 上做静态检查时请交叉编译目标平台：

```powershell
$env:GOOS="linux"; $env:GOARCH="amd64"; $env:CGO_ENABLED="0"
go build -tags "with_utls nomsgpack" ./...
```

## 常用命令

```bash
make help              # 查看全部目标
make frontend-install  # npm ci
make frontend-dev      # 前端开发服务器 :5173
make run               # 运行后端（读取 config/config.yaml）
make test              # go test ./...
make test-race         # 竞态检测
make cover             # 覆盖率，输出 coverage.out
make vet               # go vet
make lint              # gofmt -s 检查 + go vet
make fmt               # gofmt -s -w
make tidy              # go mod tidy
make build             # 构建 linux/amd64 产物（含前端）
make build-all         # amd64 / arm64 / armv7
make docker-build      # 构建本地镜像 vohive:local
make clean
```

## 前端内嵌机制（重要）

`internal/web/fs.go` 中：

```go
//go:embed all:dist
var distFS embed.FS
```

`internal/web/dist` 由 `make frontend-dist` 生成（`web/dist` 复制而来），并被 `.gitignore` 排除。
**因此没有构建前端之前，任何涉及 `internal/web` 的 `go build` / `go test` / `go vet` 都会失败**，这是预期行为。

```bash
make frontend-dist    # 生成 internal/web/dist
go build ./...
```

前端开发模式下 Vite 监听 `:5173`，并把 `/api` 代理到 `http://127.0.0.1:7575`
（可用 `VITE_API_PROXY_TARGET` 覆盖，见 `web/vite.config.ts`）。

## 前端测试

```bash
cd web
npm test          # tsx --test tests/*.test.ts
npm run typecheck # vue-tsc --noEmit
npm run lint      # eslint
```

## 代码结构约束

仓库中有若干"架构守卫"测试，违反会直接让 `go test` 失败：

| 测试 | 约束 |
| --- | --- |
| `internal/device/vowifi_external_boundary_test.go` | `cmd/` 与 `internal/` 只能引用 `github.com/1239t/vowifi-go/runtimehost` 下的公开包（`engine/` 子包除外），且不得引用旧的 `internal/vowifi`。 |
| 同名文件中的行数约束 | `internal/device/pool_vowifi_runtime.go` 保持在 650 行以内。 |
| `vowifi_start_orchestrator.go` 归属 | 启动编排逻辑必须留在编排器文件中，不得回迁到 `pool_vowifi_runtime.go`。 |
| `internal/api/openapi_test.go` | `openapi.vohive.yaml` 必须是合法 YAML 且声明 `openapi` 版本。 |

## 构建标签

编译统一使用 `-tags "with_utls nomsgpack"`（`Makefile`、`Dockerfile`、CI 均已配置）。缺少标签可能导致依赖行为不一致。

## 第三方替换

`go.mod` 末尾：

```go
replace github.com/emiago/sipgo => ./third_party/sipgo
```

SIP 栈使用仓库内的 `third_party/sipgo` 副本。改动该目录会影响 VoWiFi/IMS 通话，请谨慎。

## 提交前的自检清单

```bash
make lint
make test
make build
```

CI（`.github/workflows/ci.yml`）会在 push / PR 时执行：前端 lint + typecheck + 单测 + 构建，后端 `go mod tidy` 校验、gofmt 检查、`go vet`、`go test -race` 与 `linux/amd64` 构建。

## 发布

```bash
git tag v1.0.0
git push origin v1.0.0
```

- `binary-release` 工作流：构建 amd64 / arm64 / armv7 产物与 `SHA256SUMS`，发布到 GitHub Release。
  产物命名 `vohive_<tag>_linux_<arch>`，`internal/updater` 依赖该命名做架构匹配，修改命名需同步更新 updater。
- `docker` 工作流：构建 `linux/amd64` + `linux/arm64` 镜像并推送到 GHCR，推送前执行冒烟测试。
