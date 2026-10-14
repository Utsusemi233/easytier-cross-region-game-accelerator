//go:build windows

package easytier

import (
	"fmt"
	"golang.org/x/sys/windows"
	"strings"
	"unsafe"
)

type physicalAdapter struct {
	name, description            string
	kind                         uint32
	gateway4, gateway6, address6 bool
	metric4, metric6             uint32
}

func eligiblePhysical(a physicalAdapter) bool {
	if a.kind != 6 && a.kind != 71 && a.kind != 243 && a.kind != 244 {
		return false
	}
	value := strings.ToLower(a.name + " " + a.description)
	for _, word := range []string{"zerotier", "easytier", "meta tunnel", "clash", "virtual", "vpn", "tap-windows", "hyper-v", "vmware", "docker"} {
		if strings.Contains(value, word) {
			return false
		}
	}
	return true
}
func choosePhysical(rows []physicalAdapter, ipv6 bool) (string, error) {
	chosen := ""
	metric := uint32(^uint32(0))
	for _, row := range rows {
		if !eligiblePhysical(row) {
			continue
		}
		value := row.metric4
		if ipv6 {
			if !row.gateway6 || !row.address6 {
				continue
			}
			value = row.metric6
		} else if !row.gateway4 {
			continue
		}
		if chosen == "" || value < metric || (value == metric && row.name < chosen) {
			chosen = row.name
			metric = value
		}
	}
	if chosen == "" {
		return "", fmt.Errorf("easytier: no eligible physical uplink for FEC peer")
	}
	return chosen, nil
}

// The binding exists only at runtime, and is recomputed after roaming.
func PhysicalUnderlayInterface(ipv6 bool) (string, error) {
	size := uint32(15000)
	for attempt := 0; attempt < 3; attempt++ {
		buf := make([]byte, size)
		head := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))
		err := windows.GetAdaptersAddresses(windows.AF_UNSPEC, windows.GAA_FLAG_INCLUDE_GATEWAYS, 0, head, &size)
		if err == windows.ERROR_BUFFER_OVERFLOW {
			continue
		}
		if err != nil {
			return "", err
		}
		rows := []physicalAdapter{}
		for a := head; a != nil; a = a.Next {
			if a.OperStatus != windows.IfOperStatusUp {
				continue
			}
			row := physicalAdapter{name: windows.UTF16PtrToString(a.FriendlyName), description: windows.UTF16PtrToString(a.Description), kind: a.IfType, metric4: a.Ipv4Metric, metric6: a.Ipv6Metric}
			if !eligiblePhysical(row) {
				continue
			}
			for u := a.FirstUnicastAddress; u != nil; u = u.Next {
				if ip := u.Address.IP(); ip != nil && ip.IsGlobalUnicast() && ip.To4() == nil && u.PreferredLifetime > 0 && u.DadState == 4 {
					row.address6 = true
				}
			}
			for g := a.FirstGatewayAddress; g != nil; g = g.Next {
				if ip := g.Address.IP(); ip != nil {
					if ip.To4() == nil {
						row.gateway6 = true
					} else {
						row.gateway4 = true
					}
				}
			}
			rows = append(rows, row)
		}
		return choosePhysical(rows, ipv6)
	}
	return "", fmt.Errorf("easytier: interface snapshot changed repeatedly")
}
