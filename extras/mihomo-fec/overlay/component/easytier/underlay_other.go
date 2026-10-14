//go:build !windows

package easytier

import (
	"fmt"
	"net"
	"sort"
	"strings"
)

func PhysicalUnderlayInterface(ipv6 bool) (string, error) { return "", nil }

func PhysicalUnderlaySignature() (string, error) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	rows := []string{}
	for _, in := range ifaces {
		name := strings.ToLower(in.Name)
		if in.Flags&net.FlagUp == 0 || in.Flags&net.FlagLoopback != 0 || strings.Contains(name, "tun") || strings.HasPrefix(name, "wg") || strings.HasPrefix(name, "zt") || strings.Contains(name, "clash") || strings.HasPrefix(name, "et") {
			continue
		}
		addrs, err := in.Addrs()
		if err != nil {
			continue
		}
		row := fmt.Sprintf("%d/%s", in.Index, in.Name)
		parts := []string{}
		for _, addr := range addrs {
			parts = append(parts, addr.String())
		}
		sort.Strings(parts)
		rows = append(rows, row+":"+strings.Join(parts, ","))
	}
	sort.Strings(rows)
	return strings.Join(rows, ";"), nil
}
