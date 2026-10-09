#!/bin/sh
set -eu
. /etc/easytier-direct/fec.env
case "$WAN_INTERFACE" in ''|*[!a-zA-Z0-9_.:-]*) exit 1;; esac
device=$(ubus call "network.interface.$WAN_INTERFACE" status | jsonfilter -e '@.l3_device')
case "$device" in ''|*[!a-zA-Z0-9_.:-]*) exit 1;; esac
ip -6 -o addr show dev "$device" scope global | awk '{print $4}' | cut -d/ -f1 | grep -E '^[23][0-9a-fA-F]*:' | sort -u
