#!/bin/sh
set -eu
base="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
entry="${1:-$base/openwrt/root/etc/hotplug.d/iface/99-codex-game-endpoints.hotplug}"
stage=$(mktemp -d)
cleanup() {
 rm -f "$stage/wake" "$stage/entry.sh" "$stage/bin/uci"
 rmdir "$stage/bin" "$stage"
}
trap cleanup EXIT
mkdir "$stage/bin"
# Redirect only the notification file; leave all event logic unchanged.
sed "s@/var/run/codex-game-endpoint-wake@$stage/wake@g" "$entry" >"$stage/entry.sh"
cat >"$stage/bin/uci" <<'SH'
#!/bin/sh
case "$3" in
 easytier_home_game.main.wan) printf 'uplink4\n';;
 easytier_home_game.main.wan6) printf 'uplink6\n';;
 *) exit 1;;
esac
SH
chmod 755 "$stage/bin/uci"
count=0
check() {
 action="$1"; interface="$2"; device="$3"; expected="$4"
 rm -f "$stage/wake"
 ACTION="$action" INTERFACE="$interface" DEVICE="$device" PATH="$stage/bin:$PATH" sh "$stage/entry.sh"
 if [ "$expected" = yes ]; then
  [ -s "$stage/wake" ] || { printf 'FAIL: missed %s %s %s\n' "$action" "$interface" "$device"; exit 1; }
 else
  [ ! -e "$stage/wake" ] || { printf 'FAIL: unexpected wake %s %s %s\n' "$action" "$interface" "$device"; exit 1; }
 fi
 count=$((count+1))
}
check ifup wan eth1 yes
check ifupdate wan6 eth1 yes
check ifdown zerotier ztfixture yes
check ifup custom_overlay ztfixture yes
check ifupdate custom_overlay ztfixture yes
check ifdown custom_overlay ztfixture yes
check ifup uplink4 eth1 yes
check ifupdate uplink6 eth1 yes
check ifup lan br-lan no
check ifup native etnative no
check unsupported wan eth1 no
check unsupported custom_overlay ztfixture no
printf 'PASS: %s hotplug events, custom WAN/ZeroTier names and unrelated-interface isolation\n' "$count"
