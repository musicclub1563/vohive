# 部署指南

## 前置条件

- Linux 主机（x86-64 / ARM64 / ARMv7），root 权限。
- 已正确识别的高通模组（`/dev/ttyUSB*`、`/dev/cdc-wdm*` 或 MBIM 节点）。
- 访问 USB 设备与网卡管理的能力：容器需 `privileged: true` + `network_mode: host`；裸机部署需 root。
- 启用 VoWiFi/IMS 时，内核需支持 XFRM/IPsec，并具备 `ip-full` 等用户态工具。

## Docker Compose

```bash
mkdir -p vohive/{config,data,logs}
cd vohive
curl -fsSL https://raw.githubusercontent.com/1239t/vohive/master/docker-compose.hub.yml -o docker-compose.yml
docker compose up -d
docker compose logs -f
```

要点：

- 首次启动由 `scripts/docker-entrypoint.sh` 从镜像内的 `config.example.yaml` 生成 `config/config.yaml`，之后可直接在宿主机编辑并 `docker compose restart`。
- 使用 `network_mode: host`，**端口映射不生效**；服务直接绑定 `:7575`，代理端口同样通过宿主机 IP 访问。
- 挂载 `/dev:/dev` 以支持模组热插拔与运行中添加设备。
- 国内服务器访问 Telegram / eSIM SM-DP+ / 更新检查时，可在 `environment` 中追加 `HTTPS_PROXY`。

从源码构建镜像：

```bash
git clone https://github.com/1239t/vohive.git
cd vohive
docker compose up -d --build   # 使用仓库根目录的 docker-compose.yml
# 或
make docker-build
```

## 二进制 + systemd

```bash
# 1. 下载并校验
sha256sum -c SHA256SUMS --ignore-missing

# 2. 安装
sudo install -d -m 0755 /opt/vohive/bin /opt/vohive/data /opt/vohive/logs /etc/vohive
sudo install -m 0755 vohive_vX.Y.Z_linux_amd64 /opt/vohive/bin/vohive
sudo cp config/config.example.yaml /etc/vohive/config.yaml
sudo chmod 0600 /etc/vohive/config.yaml

# 3. 安装服务单元
sudo cp packaging/systemd/vohive.service /etc/systemd/system/vohive.service
sudo systemctl daemon-reload
sudo systemctl enable --now vohive
sudo systemctl status vohive
```

服务单元要点：

- `ExecStart=/opt/vohive/bin/vohive -c /etc/vohive/config.yaml`。
- 通过 `EnvironmentFile=-/etc/vohive/vohive.env` 注入可选环境变量（文件不存在时忽略）。
- 需要网卡与原始套接字能力，因此保留 `CAP_NET_ADMIN`、`CAP_NET_RAW` 且 `PrivateDevices=false`。
- 数据目录 `/opt/vohive/data`、日志目录 `/opt/vohive/logs` 在 `ReadWritePaths` 中放行。

常用运维：

```bash
sudo journalctl -u vohive -f
sudo systemctl restart vohive
```

## OpenWrt

仓库提供 OpenWrt 软件包源码 `packaging/openwrt/vohive`。

在 OpenWrt 构建环境中：

```bash
# 将包目录链入 package feed
ln -s /path/to/vohive/packaging/openwrt/vohive package/vohive

make menuconfig        # Network -> Telephony -> vohive
make package/vohive/compile V=s
```

产物为 `vohive_*.ipk`，安装后：

- 二进制：`/usr/bin/vohive`
- 配置：`/etc/vohive/config.yaml`（`conffiles`，升级时保留）
- UCI 配置：`/etc/config/vohive`
- 启动脚本：`/etc/init.d/vohive`（procd 托管，自动重启）
- 数据/日志：`/var/lib/vohive/data`、`/var/lib/vohive/logs`

```bash
/etc/init.d/vohive start
/etc/init.d/vohive enable
logread -f | grep vohive
```

### 关于 Web 管理后台

`internal/web/fs.go` 通过 `//go:embed all:dist` 内嵌前端资源，编译时该目录不能为空。软件包的 `Build/Prepare` 会按如下规则处理：

- 源码树中已存在 `web/dist`（先执行 `make frontend-dist`）→ 复制为 `internal/web/dist`，产物包含完整 UI；
- 否则写入一个占位 `index.html`，产物仍可编译，但只适合以 `vohive -backend-only` 运行纯后端。

### VoWiFi 内核依赖

启用 VoWiFi 需要内核 XFRM/IPsec 支持，请从固件自带的 feed 安装匹配版本的内核模块（不要强制安装其他内核版本的 kmod）：

```text
kmod-ipsec  kmod-ipsec4  kmod-ipsec6
kmod-crypto-authenc  kmod-crypto-cbc  kmod-crypto-sha1
ip-full
```

## 更新

- **二进制 / systemd**：Web 界面「设置 → 系统」提供更新检查与应用，或在 [Releases](https://github.com/1239t/vohive/releases) 下载新版本替换后 `systemctl restart vohive`。
  自更新会下载与当前架构匹配的产物，通过 `minio/selfupdate` 原子替换可执行文件，失败自动回滚。
- **Docker**：容器内**不要**执行二进制热替换，请拉取新镜像后重建容器：

  ```bash
  docker compose pull
  docker compose up -d
  ```

## 目录与权限建议

| 路径 | 用途 | 建议权限 |
| --- | --- | --- |
| `/etc/vohive/config.yaml` | 主配置（含通知渠道密钥） | `0600`，属主 root |
| `/opt/vohive/data` | SQLite 数据库 | 仅服务账号可写 |
| `/opt/vohive/logs` | 轮转日志 | 仅服务账号可写 |
