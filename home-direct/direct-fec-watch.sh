#!/bin/sh
set -eu
while :; do
 current=$(/usr/libexec/easytier-direct/direct-fec-addresses.sh 2>/dev/null || true)
 previous=$(cat /var/run/easytier-direct-fec-addresses 2>/dev/null || true)
 if [ "$current" != "$previous" ]; then
  /etc/init.d/easytier-direct-fec restart >/dev/null 2>&1
 fi
 sleep 2
done
