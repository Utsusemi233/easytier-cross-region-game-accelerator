#!/bin/sh
set -eu
peer="$(wg show wg_game peers)"
port="$(jsonfilter -i /etc/codex-game/endpoint-config.json -e '@.local_port')"
case "$port" in ''|*[!0-9]*) exit 1;; esac
[ "$(printf '%s\n' "$peer" | wc -l)" -eq 1 ] && [ "${#peer}" -eq 44 ] || exit 1
wg set wg_game peer "$peer" remove
wg set wg_game peer "$peer" endpoint "127.0.0.1:$port" allowed-ips 0.0.0.0/0 persistent-keepalive 15
