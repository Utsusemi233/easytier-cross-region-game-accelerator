#!/bin/sh
set -eu
base="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
action="${1:---plan}"
case "$action" in --plan|--install) ;; *) printf 'Use --plan or --install\n'; exit 2;; esac
[ -d "$base/openwrt/root" ] && [ -d "$base/openwrt/luasrc" ] || exit 1
if [ "$action" = --install ]; then
 [ "$(id -u)" = 0 ] || exit 1
 [ -f /etc/config/easytier ] || { printf 'Install upstream luci-app-easytier first\n'; exit 1; }
 backup="/etc/codex-game/backups/install-$(date +%Y%m%d-%H%M%S)-$$"
 mkdir -p "$backup"; chmod 700 "$backup"
fi
copy_file() {
 source="$1"; target="$2"
 case "$target" in /etc/init.d/*|/etc/config/*|/etc/codex-game/game-route-health.sh|/etc/codex-game-home-nat.sh)
  if [ -e "$target" ]; then printf 'Preserve existing %s\n' "$target"; return; fi
 ;; esac
 printf '%s %s\n' "$action" "$target"
 [ "$action" = --install ] || return 0
 if [ -e "$target" ]; then mkdir -p "$backup$(dirname "$target")"; cp -p "$target" "$backup$target"; fi
 mkdir -p "$(dirname "$target")"; cp "$source" "$target.et-game-new"
 case "$target" in /etc/init.d/*|/usr/sbin/*|*.sh|/etc/hotplug.d/*|/etc/uci-defaults/*) chmod 755 "$target.et-game-new";; /etc/config/*) chmod 600 "$target.et-game-new";; *) chmod 644 "$target.et-game-new";; esac
 mv "$target.et-game-new" "$target"
}
find "$base/openwrt/root" -type f | while IFS= read -r file; do copy_file "$file" "${file#"$base/openwrt/root"}"; done
find "$base/openwrt/luasrc" -type f | while IFS= read -r file; do copy_file "$file" "/usr/lib/lua/luci/${file#"$base/openwrt/luasrc/"}"; done
if [ "$action" = --install ]; then
 sh /etc/uci-defaults/99-easytier-home-game
 printf 'Installed additive extension. Run et-game adopt or fill config, then doctor/plan/verify. Backup: %s\n' "$backup"
fi
