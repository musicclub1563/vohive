include $(TOPDIR)/rules.mk

PKG_NAME:=vohive
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=PolyForm-Noncommercial-1.0.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=musicclub1563 <https://github.com/musicclub1563/vohive>
PKG_DESCR:=面向高通 4G/LTE/5G 模组的综合管理与代理服务平台

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/musicclub1563/vohive.git
PKG_SOURCE_VERSION:=master
PKG_MIRROR_HASH:=skip

# 需要一个 Go 工具链来交叉编译，Node 工具链用于构建内嵌的 Web 管理后台。
PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

GO_PKG:=github.com/1239t/vohive
GO_PKG_BUILD_PKG:=github.com/1239t/vohive/cmd/vohive
GO_PKG_TAGS:=with_utls,nomsgpack
GO_PKG_LDFLAGS_X:= \
	github.com/1239t/vohive/internal/global.Version=$(PKG_VERSION) \
	github.com/1239t/vohive/internal/global.BuildTime=$(shell date -u '+%Y-%m-%d %H:%M:%S')

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/vohive
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Telephony
  TITLE:=VoHive modem management and proxy service
  URL:=https://github.com/musicclub1563/vohive
  DEPENDS:=$(GO_ARCH_DEPENDS) +kmod-usb-serial-option +kmod-usb-net-qmi-wwan \
           +usbutils +ip-full +ca-certificates +zoneinfo-asia
  USERID:=vohive:vohive
endef

define Package/vohive/description
  VoHive 管理高通 4G/LTE/5G 模组（Quectel EC20/EC25/EC21/EG25/EM20 等），
  提供 SOCKS5/HTTP 代理编排、短信收发、VoWiFi/IMS 通话与 eSIM 全生命周期管理，
  并附带一套内嵌的响应式 Web 管理后台。
  启用 VoWiFi 时还需内核 XFRM/IPsec 支持: kmod-ipsec, kmod-ipsec4, kmod-ipsec6,
  kmod-crypto-authenc, kmod-crypto-cbc, kmod-crypto-sha1。
endef

# internal/web/fs.go 通过 //go:embed all:dist 内嵌前端资源，目录为空会导致编译失败。
# 完整 UI:先在源码树执行 `make frontend-dist`（或 cd web && npm ci && npm run build）
# 后再编译本包。仅需要后端能力时可不构建前端，产物以 `vohive -backend-only` 运行。
define Build/Prepare
	$(call Build/Prepare/Default)
	if [ -d "$(PKG_BUILD_DIR)/web/dist" ]; then \
		mkdir -p "$(PKG_BUILD_DIR)/internal/web"; \
		cp -R "$(PKG_BUILD_DIR)/web/dist" "$(PKG_BUILD_DIR)/internal/web/dist"; \
	else \
		mkdir -p "$(PKG_BUILD_DIR)/internal/web/dist"; \
		printf '%s\n' '<!doctype html><title>VoHive backend-only</title>' \
			> "$(PKG_BUILD_DIR)/internal/web/dist/index.html"; \
	fi
endef

define Package/vohive/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/vohive $(1)/usr/bin/vohive

	$(INSTALL_DIR) $(1)/etc/vohive
	$(INSTALL_CONF) ./files/config.yaml $(1)/etc/vohive/config.yaml

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/vohive.init $(1)/etc/init.d/vohive

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/vohive.config $(1)/etc/config/vohive

	$(INSTALL_DIR) $(1)/var/lib/vohive/data
	$(INSTALL_DIR) $(1)/var/lib/vohive/logs
endef

define Package/vohive/postinst
#!/bin/sh
[ -z "$${IPKG_INSTROOT}" ] || exit 0
mkdir -p /var/lib/vohive/data /var/lib/vohive/logs
chown -R vohive:vohive /var/lib/vohive 2>/dev/null || true
exit 0
endef

$(eval $(call GoBinPackage,vohive))
$(eval $(call BuildPackage,vohive))
