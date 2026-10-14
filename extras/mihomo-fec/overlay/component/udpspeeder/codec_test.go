package udpspeeder

import (
	"bytes"
	"encoding/binary"
	"net"
	"os"
	"testing"
	"time"
)

func TestRizzoParityKnownVector(t *testing.T) {
	c, err := codec(2, 2)
	if err != nil {
		t.Fatal(err)
	}
	shards := [][]byte{{1, 2, 3}, {4, 5, 6}, make([]byte, 3), make([]byte, 3)}
	if err = c.Encode(shards); err != nil {
		t.Fatal(err)
	}
	// Original systematic Vandermonde: parity row points alpha=2 and alpha^2=4.
	for i, want := range [][]byte{{11, 12, 9}, {21, 30, 23}} {
		if !bytes.Equal(shards[i+2], want) {
			t.Fatalf("row %d: %v", i, shards[i+2])
		}
	}
}
func TestRecoverFromParityOnly(t *testing.T) {
	conv := []byte{1, 2, 3, 4}
	want := append(conv, bytes.Repeat([]byte{7}, 1198)...)
	frames, err := encodeGroup(7, [][]byte{want}, 2, 30, 1250)
	if err != nil {
		t.Fatal(err)
	}
	_, k, p, _, shard, err := parseGroup(frames[9])
	if err != nil {
		t.Fatal(err)
	}
	g := decodeGroup{k: k, p: p, length: len(shard), shards: make([][]byte, k+p)}
	result, err := g.add(9, shard)
	if err != nil || result != nil {
		t.Fatalf("premature decode %v", err)
	}
	_, _, _, index, shard, _ := parseGroup(frames[31])
	result, err = g.add(index, shard)
	if err != nil || len(result) != 1 || !bytes.Equal(result[0], want) {
		t.Fatalf("parity reconstruction failed %v", err)
	}
}
func TestWireIntegrityAndMalformedGroups(t *testing.T) {
	src := bytes.Repeat([]byte{9}, 650)
	key := []byte("fixture-secret")
	wire, err := cook(src, key)
	if err != nil {
		t.Fatal(err)
	}
	restored, err := uncook(wire, key)
	if err != nil || !bytes.Equal(src, restored) {
		t.Fatal("wire decode failed")
	}
	if _, err = uncook(wire, []byte("wrong-secret")); err == nil {
		t.Fatal("wrong key accepted")
	}
	wire[3] ^= 1
	if _, err = uncook(wire, key); err == nil {
		t.Fatal("corrupted packet accepted")
	}
	for i := 0; i < 9; i++ {
		if _, err = uncook(make([]byte, i), key); err == nil {
			t.Fatal("short packet accepted")
		}
	}
	bad := make([]byte, 12)
	binary.BigEndian.PutUint32(bad, 1)
	bad[5] = 200
	bad[6] = 30
	if _, _, _, _, _, err = parseGroup(bad); err == nil {
		t.Fatal("unbounded dimension accepted")
	}
}
func TestDeadlinesAndCloseWakeReader(t *testing.T) {
	raw, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	c, err := NewPacketConn(raw, Option{Key: "test", Ports: []int{11022}})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetWriteDeadline(time.Now().Add(-time.Second))
	if _, e := c.WriteTo([]byte("deadline"), &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 11022}); !os.IsTimeout(e) {
		t.Fatalf("expired write deadline accepted: %v", e)
	}
	c.SetWriteDeadline(time.Time{})
	c.SetReadDeadline(time.Now().Add(20 * time.Millisecond))
	_, _, err = c.ReadFrom(make([]byte, 64))
	if !os.IsTimeout(err) {
		t.Fatalf("expected deadline: %v", err)
	}
	c.SetReadDeadline(time.Time{})
	done := make(chan error, 1)
	go func() { _, _, e := c.ReadFrom(make([]byte, 64)); done <- e }()
	c.Close()
	select {
	case e := <-done:
		if e == nil {
			t.Fatal("closed reader succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("reader did not wake")
	}
}
