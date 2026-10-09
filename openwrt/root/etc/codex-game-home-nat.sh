#!/bin/sh
set -eu
config=/etc/codex-game/endpoint-config.json
wan="$(jsonfilter -i "$config" -e '@.wan4')"
scope="$(jsonfilter -i "$config" -e '@.portal_cidr')"
case "$wan" in ''|*[!a-zA-Z0-9_]*) exit 1;; esac
case "$scope" in ''|*[!0-9./]*) exit 1;; esac
device="$(ubus call "network.interface.$wan" status | jsonfilter -e '@.l3_device')"
[ -n "$device" ] || exit 1
iptables -t nat -S POSTROUTING | while IFS= read -r line; do
 case "$line" in *'--comment codex-game-wg-home -j MASQUERADE')
  old_device="$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++)if($i=="-o")print $(i+1)}')"
  old_scope="$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++)if($i=="-s")print $(i+1)}')"
  case "$old_device" in ''|*[!a-zA-Z0-9_.:-]*) continue;; esac
  case "$old_scope" in ''|*[!0-9./]*) continue;; esac
  if [ "${1:-}" = --remove ] || [ "$old_device" != "$device" ] || [ "$old_scope" != "$scope" ]; then
   iptables -t nat -D POSTROUTING -s "$old_scope" -o "$old_device" -m comment --comment codex-game-wg-home -j MASQUERADE
  fi
 ;; esac
done
[ "${1:-}" != --remove ] || exit 0
iptables -t nat -C POSTROUTING -s "$scope" -o "$device" -m comment --comment codex-game-wg-home -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING 1 -s "$scope" -o "$device" -m comment --comment codex-game-wg-home -j MASQUERADE
