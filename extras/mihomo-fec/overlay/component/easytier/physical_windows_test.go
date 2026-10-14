//go:build windows

package easytier

import "testing"

func TestPhysicalSelectionIgnoresVirtualGateway(t *testing.T) {
	rows := []physicalAdapter{{name: "ZeroTier One", kind: 6, gateway6: true, address6: true, metric6: 1}, {name: "ethernet-old", kind: 6, gateway4: true, metric4: 1}, {name: "wifi-current", description: "Intel Wi-Fi", kind: 71, gateway4: true, gateway6: true, address6: true, metric6: 40}, {name: "ClashFECGame", description: "Meta Tunnel", kind: 6, gateway6: true, address6: true}}
	got, err := choosePhysical(rows, true)
	if err != nil || got != "wifi-current" {
		t.Fatal(got, err)
	}
	rows[2].name = "hotspot-new"
	got, err = choosePhysical(rows, true)
	if err != nil || got != "hotspot-new" {
		t.Fatal("must not retain previous interface name", got, err)
	}
	rows[2].address6 = false
	if _, err = choosePhysical(rows, true); err == nil {
		t.Fatal("must not pick virtual or IPv4-only uplink for IPv6 peer")
	}
}
