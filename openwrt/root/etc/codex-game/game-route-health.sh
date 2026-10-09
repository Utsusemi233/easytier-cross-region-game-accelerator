#!/bin/sh
set -u
config=/etc/codex-game/endpoint-config.json
source="$(jsonfilter -i "$config" -e '@.wg_source')"
target="$(jsonfilter -i "$config" -e '@.home_probe')"
scope="$(jsonfilter -i "$config" -e '@.game_cidr')"
max_loss="$(jsonfilter -i "$config" -e '@.max_loss')"
max_rtt="$(jsonfilter -i "$config" -e '@.max_rtt')"
good=0
bad=0
endpoint_ready() { lua /usr/libexec/codex-game/endpoint-common.lua ready; }
apply_mode() {
 mode="$1"
 if [ "$mode" = home ]; then
  endpoint_ready || return 1
  ip route replace default dev wg_game table 2848 || return 1
 else
  route="$(ip -4 route get 8.8.8.8 | head -n 1)"
  gateway="$(printf '%s\n' "$route" | awk '{for(i=1;i<=NF;i++)if($i=="via")print $(i+1)}')"
  device="$(printf '%s\n' "$route" | awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}')"
  [ -n "$gateway" ] && [ -n "$device" ] || return 1
  ip route replace default via "$gateway" dev "$device" table 2848 || return 1
 fi
 previous="$(cat /var/run/codex-game-route.state 2>/dev/null)"
 if [ "$previous" != "$mode" ]; then
  printf '%s\n' "$mode" >/var/run/codex-game-route.state
  if [ -n "$previous" ]; then
   for proto in tcp udp; do conntrack -D -p "$proto" -s "$scope" --mark 0x80000000/0x80000000 >/dev/null 2>&1 || true; done
   if [ "$mode" = direct ]; then conntrack -D -p udp -s "$scope" --reply-dst "$source" >/dev/null 2>&1 || true; fi
   if [ -x /etc/init.d/codex-app-dns ]; then /etc/init.d/codex-app-dns restart >/dev/null 2>&1 || true; fi
  fi
  logger -t codex-game-route "Selected route is $mode"
 fi
}
case "${1:-}" in --force-direct) apply_mode direct; exit $?;; --validated-home) apply_mode home; exit $?;; esac
while :; do
 if ! endpoint_ready; then good=0; bad=0; apply_mode direct; sleep 2; continue; fi
 result="$(ping -I "$source" -c 5 -W 1 -s 128 "$target" 2>/dev/null)"
 loss="$(printf '%s\n' "$result" | sed -n 's/.* \([0-9]*\)% packet loss.*/\1/p')"
 average="$(printf '%s\n' "$result" | awk -F'[/=]' '/round-trip/{gsub(/ /,"",$5);print $5}')"
 if [ -n "$loss" ] && [ -n "$average" ] && awk -v l="$loss" -v a="$average" -v ml="$max_loss" -v ma="$max_rtt" 'BEGIN{exit !(l<=ml && a<=ma)}'; then
  good=$((good+1)); bad=0
  if [ "$good" -ge 2 ] && endpoint_ready; then apply_mode home; fi
 else
  good=0; bad=$((bad+1))
  if [ "$loss" = 100 ] || [ "$bad" -ge 2 ]; then apply_mode direct; fi
 fi
 sleep 20
done
