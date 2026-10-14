//go:build windows

package easytier

import (
	"fmt"
	"golang.org/x/sys/windows"
	"sort"
	"strings"
	"unsafe"
)

// PhysicalUnderlaySignature uses IP Helper directly, without running PowerShell.
// Only active Ethernet, Wi-Fi and WWAN interfaces are included. TUN changes do
// not cause a recovery loop.
func PhysicalUnderlaySignature() (string, error) {
	size := uint32(15000)
	for attempts := 0; attempts < 3; attempts++ {
		buf := make([]byte, size)
		head := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))
		err := windows.GetAdaptersAddresses(windows.AF_UNSPEC, windows.GAA_FLAG_INCLUDE_GATEWAYS, 0, head, &size)
		if err == windows.ERROR_BUFFER_OVERFLOW {
			continue
		}
		if err != nil {
			return "", err
		}
		rows := []string{}
		for a := head; a != nil; a = a.Next {
			if a.OperStatus != windows.IfOperStatusUp || (a.IfType != 6 && a.IfType != 71 && a.IfType != 243 && a.IfType != 244) {
				continue
			}
			name := windows.UTF16PtrToString(a.FriendlyName)
			if !eligiblePhysical(physicalAdapter{name: name, description: windows.UTF16PtrToString(a.Description), kind: a.IfType}) {
				continue
			}
			values := []string{fmt.Sprintf("%d/%d/%s", a.IfIndex, a.Ipv6IfIndex, name)}
			for u := a.FirstUnicastAddress; u != nil; u = u.Next {
				if ip := u.Address.IP(); ip != nil && ip.IsGlobalUnicast() {
					values = append(values, "ip="+ip.String())
				}
			}
			for g := a.FirstGatewayAddress; g != nil; g = g.Next {
				if ip := g.Address.IP(); ip != nil {
					values = append(values, "gw="+ip.String())
				}
			}
			sort.Strings(values)
			rows = append(rows, strings.Join(values, ","))
		}
		sort.Strings(rows)
		return strings.Join(rows, ";"), nil
	}
	return "", fmt.Errorf("easytier: interface snapshot changed repeatedly")
}
