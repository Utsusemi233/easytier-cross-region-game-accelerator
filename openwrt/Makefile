include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-easytier-home-game
PKG_VERSION:=0.1.1
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
LUCI_TITLE:=EasyTier home game gateway extension
LUCI_DEPENDS:=+luci-app-easytier +luci-compat +luci-lib-jsonc +luci-lib-nixio +curl +wireguard-tools +ip-full +conntrack +zerotier
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/easytier_home_game
/etc/codex-game/
/etc/init.d/codex-game-endpoints
/etc/init.d/codex-game-fec
/etc/init.d/codex-game-home
/etc/init.d/codex-game-route
/etc/codex-game-home-nat.sh
endef

include $(TOPDIR)/feeds/luci/luci.mk
