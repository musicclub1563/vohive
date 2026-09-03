# Web 管理界面（Vue 3 + Vite）

该目录是 VoHive 的前端工程，提供设备状态、短信、代理实例、eSIM、VoWiFi 与系统设置等管理功能。

技术栈：Vue 3 + Vite + TypeScript + Element Plus + TailwindCSS + Pinia + ECharts。

## 依赖与约定

- 后端默认监听 `:7575`，API 前缀为 `/api`。
- 前端开发服务器默认监听 `:5173`，并通过 Vite 代理把 `/api` 转发到 `http://127.0.0.1:7575`（可用 `VITE_API_PROXY_TARGET` 覆盖，见 `vite.config.ts`）。

## 开发运行

```bash
npm ci
npm run dev
```

默认访问 `http://127.0.0.1:5173/`。

如需在远程/容器里对外暴露，可使用：

```bash
npm run dev -- --host 0.0.0.0 --port 5174
```

## 构建

```bash
npm run build     # 先执行 vue-tsc 类型检查，再执行 vite build
```

构建产物输出到 `web/dist`。后端通过 `internal/web/fs.go` 的 `//go:embed all:dist` 把该目录内嵌进二进制，因此**后端构建前必须先构建前端**：

```bash
make frontend-dist   # 等价于 npm ci && npm run build && cp -R web/dist internal/web/dist
```

未命中路由时回落到 `index.html`，由前端路由接管。

## 测试与检查

```bash
npm test          # tsx --test tests/*.test.ts
npm run typecheck # vue-tsc --noEmit
npm run lint      # eslint
```

## 目录结构

```text
src/api/          后端接口封装
src/views/        页面组件
src/components/   通用组件
src/composables/  组合式逻辑
src/stores/       Pinia 状态
src/services/     业务服务
src/types/        TypeScript 类型
src/utils/        工具函数
tests/            单元测试（Node test runner）
```

## 相关文档

- 后端与整体项目说明见 [../README.md](../README.md)
- 本地开发流程见 [../docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)
