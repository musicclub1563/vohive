#!/usr/bin/env bash
#
# VoHive 一键卸载脚本
#
# 与 scripts/install.sh 对应,完整清理通过 install.sh 安装的内容:
#   - 停止并禁用 systemd 服务 (vohive.service)
#   - 杀掉残留的 vohive 进程
#   - 删除程序目录   /opt/vohive
#   - 删除配置目录   /etc/vohive
#   - 删除 systemd 单元 /etc/systemd/system/vohive.service
#   - 若存在 vohive 专用用户/组则一并删除
#
# 用法:
#   本地执行:            sudo bash uninstall_vohive.sh
#   静默(无需确认):     sudo bash uninstall_vohive.sh -y
#   远程一键卸载:
#     curl -fsSL https://raw.githubusercontent.com/musicclub1563/vohive/main/scripts/uninstall_vohive.sh | sudo bash -s -- -y
#
set -euo pipefail

BIN_DIR="/opt/vohive"
CFG_DIR="/etc/vohive"
SVC_NAME="vohive.service"
SVC_PATH="/etc/systemd/system/$SVC_NAME"
RUN_USER="vohive"

log()  { echo -e "\033[1;32m[vohive]\033[0m $*"; }
warn() { echo -e "\033[1;33m[vohive]\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m[vohive]\033[0m $*" >&2; exit 1; }

# 是否跳过确认
ASSUME_YES=0
for a in "$@"; do
  [ "$a" = "-y" ] || [ "$a" = "--yes" ] && ASSUME_YES=1
done

[ "$(id -u)" -eq 0 ] || die "请使用 root 运行: sudo bash uninstall_vohive.sh"

if [ "$ASSUME_YES" -ne 1 ]; then
  echo -e "\033[1;31m即将卸载 VoHive,以下将被删除:\033[0m"
  echo "  - 服务:   $SVC_NAME"
  echo "  - 程序:   $BIN_DIR"
  echo "  - 配置:   $CFG_DIR"
  echo
  read -r -p "确认卸载? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) log "已取消卸载。"; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------------------
# 1) 停止并禁用 systemd 服务
# ---------------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files 2>/dev/null | grep -q "^$SVC_NAME"; then
    log "停止并禁用服务 $SVC_NAME ..."
    systemctl disable --now "$SVC_NAME" 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 2) 杀掉任何残留的 vohive 进程(服务已被禁用,重复保险)
# ---------------------------------------------------------------------------
if pgrep -f "$BIN_DIR/bin/vohive" >/dev/null 2>&1; then
  log "终止残留 vohive 进程 ..."
  pkill -f "$BIN_DIR/bin/vohive" 2>/dev/null || true
  sleep 1
  pkill -9 -f "$BIN_DIR/bin/vohive" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 3) 删除 systemd 单元并刷新
# ---------------------------------------------------------------------------
if [ -f "$SVC_PATH" ]; then
  log "删除 systemd 单元 $SVC_PATH ..."
  rm -f "$SVC_PATH"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 4) 删除程序与配置目录
# ---------------------------------------------------------------------------
if [ -d "$BIN_DIR" ]; then
  log "删除程序目录 $BIN_DIR ..."
  rm -rf "$BIN_DIR"
fi
if [ -d "$CFG_DIR" ]; then
  log "删除配置目录 $CFG_DIR ..."
  rm -rf "$CFG_DIR"
fi

# ---------------------------------------------------------------------------
# 5) 若存在专用用户/组则一并清理(默认安装使用 root,此步为兼容保留)
# ---------------------------------------------------------------------------
if id "$RUN_USER" >/dev/null 2>&1; then
  log "删除专用用户 $RUN_USER ..."
  userdel "$RUN_USER" 2>/dev/null || true
fi
if getent group "$RUN_USER" >/dev/null 2>&1; then
  groupdel "$RUN_USER" 2>/dev/null || true
fi

echo
log "VoHive 已卸载完成。"
warn "本机网络/拨号配置(如 /etc/network、ModemManager 等)不受影响,如需一并清理请手动处理。"
