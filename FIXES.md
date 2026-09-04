# 已修复的 BUG

汇总本项目修复过的主要问题，按主题分组，不区分版本。每条附提交哈希便于溯源。

---

## 一、运营商扫描与前端

### 1. 运营商手动扫描返回 0x0046 时前端显示原始 QMI 字节
- **现象**：在「运营商网络选择」弹窗点击「扫描可用网络」，当模组已联网 / 数据业务忙时扫描被拒绝（QMI `service=0x03 msg=0x0021 error=0x0046`），前端直接把一串原始错误字节显示给用户，无法理解。
- **根因**：后端只在 `QMIErrInternal(0x0003)` 时才归类为「可重试」并给出友好提示。而 `0x0046`（模组忙 / 当前射频态下无法扫描）不等于 `0x0003`，分类未命中，于是把 `Err` 原始字段直接抛给前端；前端又仅在非 retryable 时显示错误，结果把原始字节显示了出来。
- **修复**：
  - `internal/device/operator_selection.go`：将 `0x0046`、`0x0047`、`0x005E`、`0x0005`、`0x0006`、`0x000F` 等 NAS 主动扫描被拒的状态码全部纳入可重试识别（`isRetryableOperatorScanError`），并对 `0x0046` 返回专用中文提示：「模组拒绝了网络扫描（QMI 内部错误 0x0046）：常见于模组已联网、正在使用数据业务时无法并发执行主动扫描。建议先在【设备】中断开数据连接后重试，或等待网络空闲。」
  - `internal/backend/qmi_operator_selection.go`：主动扫描被拒绝时不再直接失败，而是改用 `NASForceNetworkSearch` 触发模组重新搜网，并轮询其被动上报的**增量扫描**快照，多数情况下仍能返回可用的运营商候选列表。
- 提交：`172397c`

### 2. 可重试错误在弹窗内重复显示两次
- **现象**：扫描返回可重试错误时，友好提示文字在「运营商网络选择」弹窗内出现**两次**。
- **根因**：`web/src/components/OperatorSelectionDialog.vue` 中两个显示区域不在同一个 `v-if / v-else-if` 互斥链内——第 162 行 `v-if="scanning || scanMessage || scanError"` 的小提示条，与第 192 行 `v-else-if="scanRetryable"` 的居中大块——可重试时两者条件同时成立，同一段中文被渲染两遍。
- **修复**：将三类提示拆分为互斥的单一职责显示点——红色小条仅展示**非可重试**的原始错误（保留原始字节便于调试）；灰色大块展示扫描进行中；琥珀色大块展示可重试的友好提示。
- 提交：`4781fd1`

---

## 二、配置与安装

### 3. 全新安装后设备列表缺少 SIM 设备 / 默认配置无 devices 字段
- **现象**：默认配置（`config.example.yaml`）与打包内预置了 `wwan0`/`wwan1` 两个 SIM 设备条目，与 OpenWrt 打包及「默认无设备」要求不符，导致用户设备上出现 broken config。
- **根因**：默认配置预置了设备条目。
- **修复**：移除预置的 `wwan0`/`wwan1` 设备，全新安装以空设备列表启动，用户在 UI 中手动添加自己的 SIM 设备。
- 提交：`db0247b`

### 4. 保存配置时因只读文件系统失败（/etc/vohive 不可写）
- **现象**：在 `ProtectSystem=strict` 下保存配置报只读文件系统错误，配置写不进去。
- **根因**：systemd 服务未授予 `/etc/vohive` 写权限。
- **修复**：在 `packaging/systemd/vohive.service` 与 `scripts/install.sh` 中将 `/etc/vohive` 加入 `ReadWritePaths`；同时重置设备列表为空默认，由用户从 UI 添加。
- 提交：`524cc21`

### 5. 安装脚本在 `set -u` 下 EXIT trap 命中未绑定变量
- **现象**：安装脚本因 `set -u` 导致 EXIT trap 引用未定义变量 `tmp` 而报错中断。
- **根因**：`tmp` 为函数内局部变量，EXIT trap 在 `set -u` 下访问了未绑定变量。
- **修复**：将 `tmp` 改为全局变量，避免 EXIT trap 命中未绑定变量。
- 提交：`cbd9aa0`

---

## 三、依赖与构建

### 6. swu-go armv7 Timeval 不兼容
- **现象**：armv7 平台构建或运行异常（Timeval 结构不兼容）。
- **根因**：依赖 `swu-go` 旧版本在 armv7 上 Timeval 处理有误。
- **修复**：升级 `swu-go` 到 v0.0.2（armv7 Timeval 修复）。
- 提交：`69ecce8`

### 7. swu-go 平台相关 Timeval 问题
- **现象**：跨平台构建 / 运行仍因 Timeval 结构差异出错。
- **根因**：`swu-go` 对平台相关的 Timeval 处理不完整。
- **修复**：升级 `swu-go` 到 v0.0.3（平台相关 Timeval）。
- 提交：`7c6914c`

### 8. swu-go 校验和与版本号无效
- **现象**：依赖校验和不匹配，且旧 pseudo-version 无法解析。
- **根因**：`swu-go` 引用的伪版本无效，且 `vowifi-go` 校验和不正确。
- **修复**：更新 `swu-go` 到正确的 v0.0.1 tag（旧 pseudo-version 无效）；更新 `vowifi-go` 到 v1.1.3 并使用正确校验和。
- 提交：`bdd57ef`、`2620cfd`

### 9. Release 步骤缺少 files 参数导致二进制无法上传
- **现象**：发版时二进制资产未能上传到 Release。
- **根因**：release 步骤缺少 `files` 参数。
- **修复**：为 release 步骤添加 `files` 参数。
- 提交：`0965af3`

---

## 四、测试与 CI

### 10. 测试中断言错误（MCC 断言损坏、调试用 db 测试）
- **现象**：部分单元测试因 MCC 断言损坏而失败；存在仅调试用的数据库测试。
- **根因**：断言逻辑错误，且包含不应进入 CI 的调试测试。
- **修复**：修正损坏的 MCC 断言，移除仅调试用的 db 测试，CI 跳过依赖硬件 / 凭据的包。
- 提交：`ec2a474`

### 11. CI Node 20 弃用 + 模块下载偶发失败
- **现象**：CI 报告 Node 20 已弃用；`go mod download` 偶发失败导致流水线不稳定。
- **根因**：Node.js 20 被 runner 弃用；模块下载无重试，网络抖动即失败。
- **修复**：Node.js 20 升级到 22；为 `go mod download` 增加 3 次重试；为 `1239t` 模块设置 `GONOSUMCHECK`/`GONOSUMDB`；`cancel-in-progress` 改为 `false`。
- 提交：`4cce599`
