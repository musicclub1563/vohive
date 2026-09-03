#!/usr/bin/env bash
#
# VoHive 一键安装脚本
#
# 用法:
#   1) 远程一键安装(自动检测架构,从 GitHub Release 下载对应 tar.xz 并安装为 systemd 服务):
#        curl -fsSL https://raw.githubusercontent.com/musicclub1563/vohive/main/scripts/install.sh | sudo bash
#      指定版本:  VOHIVE_VERSION=v0.1.1 sudo bash <(curl -fsSL https://raw.githubusercontent.com/musicclub1563/vohive/main/scripts/install.sh)
#      限速/私有部署: 可附带令牌,GITHUB_TOKEN=ghp_xxx VOHIVE_VERSION=v0.1.1 sudo bash <(curl ...)
#
#   2) 本地安装(在已解压的发布包目录内执行,无需联网,适合手动分发 / 私有环境):
#        sudo ./install.sh
#
set -euo pipefail

REPO="${VOHIVE_REPO:-musicclub1563/vohive}"
VERSION="${VOHIVE_VERSION:-latest}"

BIN_DIR="/opt/vohive/bin"
CFG_DIR="/etc/vohive"
DATA_DIR="/opt/vohive/data"
LOG_DIR="/opt/vohive/logs"
SVC_NAME="vohive.service"

log()  { echo -e "\033[1;32m[vohive]\033[0m $*"; }
warn() { echo -e "\033[1;33m[vohive]\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m[vohive]\033[0m $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少必要命令: $1"; }

# ---------------------------------------------------------------------------
# 本地安装(当前目录已包含 vohive 二进制)
# ---------------------------------------------------------------------------
run_local_install() {
  [ "$(id -u)" -eq 0 ] || die "请使用 root 运行: sudo bash install.sh"

  need_cmd systemctl || die "未检测到 systemd,请改用手动部署(见 docs/DEPLOYMENT.md)"
  [ -x "./vohive" ] || die "当前目录缺少 vohive 可执行文件"

  log "创建目录: $BIN_DIR $DATA_DIR $LOG_DIR $CFG_DIR"
  install -d -m 0755 "$BIN_DIR" "$DATA_DIR" "$LOG_DIR" "$CFG_DIR"

  log "安装二进制 -> $BIN_DIR/vohive"
  install -m 0755 "./vohive" "$BIN_DIR/vohive"

  if [ ! -f "$CFG_DIR/config.yaml" ]; then
    log "生成默认配置 -> $CFG_DIR/config.yaml"
    if [ -f "./config.example.yaml" ]; then
      install -m 0600 "./config.example.yaml" "$CFG_DIR/config.yaml"
    else
      warn "发布包内未携带 config.example.yaml,请手动创建 $CFG_DIR/config.yaml"
    fi
  else
    warn "$CFG_DIR/config.yaml 已存在,跳过覆盖(如需更新请手动合并 config.example.yaml)"
  fi

  log "安装 systemd 单元 -> /etc/systemd/system/$SVC_NAME"
  if [ -f "./vohive.service" ]; then
    install -m 0644 "./vohive.service" "/etc/systemd/system/$SVC_NAME"
  else
    cat > "/etc/systemd/system/$SVC_NAME" <<'UNIT'
[Unit]
Description=VoHive cellular modem management and proxy service
Documentation=https://github.com/musicclub1563/vohive
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/vohive
ExecStart=/opt/vohive/bin/vohive -c /etc/vohive/config.yaml
Restart=on-failure
RestartSec=3s
TimeoutStartSec=30s
TimeoutStopSec=30s
Environment=CONFIG_PATH=/etc/vohive/config.yaml
Environment=TZ=Asia/Shanghai
EnvironmentFile=-/etc/vohive/vohive.env
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=false
ReadWritePaths=/opt/vohive/data /opt/vohive/logs

[Install]
WantedBy=multi-user.target
UNIT
  fi

  log "重载 systemd 并启动服务"
  systemctl daemon-reload
  systemctl enable --now "$SVC_NAME"
  sleep 2
  systemctl status "$SVC_NAME" --no-pager || true

  local port
  port="$(grep -oE 'port:[[:space:]]*[0-9]+' "$CFG_DIR/config.yaml" 2>/dev/null | head -1 | grep -oE '[0-9]+')" || true
  port="${port:-7575}"

  echo
  log "安装完成! 访问 http://<本机IP>:$port"
  warn "默认账号 admin / admin123,请尽快在「设置」中修改密码。"
}

# ---------------------------------------------------------------------------
# 远程安装(下载匹配架构的 tar.xz 后进入本地安装)
# ---------------------------------------------------------------------------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)     echo "amd64" ;;
    aarch64|arm64)    echo "arm64" ;;
    armv7l|armhf)     echo "armv7" ;;
    *) die "不支持的架构: $(uname -m)(仅支持 amd64 / arm64 / armv7)" ;;
  esac
}

resolve_tag() {
  [ "$VERSION" != "latest" ] && { echo "$VERSION"; return; }
  need_cmd curl
  local tag auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  tag="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$tag" ] || die "无法从 GitHub 解析最新版本号(可手动指定 VOHIVE_VERSION;私有仓库请设置 GITHUB_TOKEN)"
  echo "$tag"
}

run_remote_install() {
  need_cmd curl
  need_cmd tar

  local arch tag url tmp pkg_dir
  arch="$(detect_arch)"
  tag="$(resolve_tag)"
  url="https://github.com/$REPO/releases/download/$tag/vohive-linux-$arch.tar.xz"

  log "架构: $arch | 版本: $tag"
  log "下载: $url"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fSL "${auth[@]}" "$url" -o "$tmp/vohive-linux-$arch.tar.xz" \
    || die "下载失败,请检查网络 / 仓库是否公开 / 手动指定 VOHIVE_VERSION: $url"

  tar -xJf "$tmp/vohive-linux-$arch.tar.xz" -C "$tmp"
  pkg_dir="$(find "$tmp" -maxdepth 3 -type f -name vohive | head -1 | xargs -r dirname)"
  [ -n "$pkg_dir" ] || die "解压后未找到 vohive 二进制"

  log "进入发布包目录并执行本地安装..."
  ( cd "$pkg_dir" && bash ./install.sh )
}

# ---------------------------------------------------------------------------
main() {
  # 本地模式:脚本所在目录(或当前目录)已存在 vohive 二进制
  if [ -x "./vohive" ]; then
    log "检测到本地发布包,进入本地安装模式..."
    run_local_install
    exit 0
  fi
  run_remote_install
}

main "$@"
