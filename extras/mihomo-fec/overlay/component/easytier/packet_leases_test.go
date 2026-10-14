package easytier

import (
	"net"
	"testing"
	"time"
)

func TestRetiredOverlayUnblocksPacketReadAndRejectsLateSocket(t *testing.T) {
	var leases PacketLeases
	old := leases.Generation()
	raw, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	pc, ok := leases.Track(raw, old)
	if !ok {
		t.Fatal("new generation refused")
	}
	done := make(chan error, 1)
	go func() { _, _, err := pc.ReadFrom(make([]byte, 32)); done <- err }()
	leases.CloseAll()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("retired read succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("retired application read stayed blocked")
	}
	late, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := leases.Track(late, old); ok {
		t.Fatal("stale dial survived shutdown")
	}
	if _, err := late.WriteTo([]byte("x"), raw.LocalAddr()); err == nil {
		t.Fatal("late socket was not closed")
	}
	fresh, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	current, ok := leases.Track(fresh, leases.Generation())
	if !ok {
		t.Fatal("fresh generation refused")
	}
	defer current.Close()
	if _, err := current.WriteTo([]byte("x"), fresh.LocalAddr()); err != nil {
		t.Fatal(err)
	}
}
