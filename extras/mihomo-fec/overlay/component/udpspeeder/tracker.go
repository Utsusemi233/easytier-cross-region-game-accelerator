package udpspeeder

import "sync"

// Tracker exposes per-outbound evidence without logging compatibility keys.
type Tracker struct {
	mu     sync.Mutex
	active map[*PacketConn]struct{}
	closed Stats
}

func addStats(dst *Stats, s Stats) {
	dst.WireSent += s.WireSent
	dst.WireReceived += s.WireReceived
	dst.WireBytesSent += s.WireBytesSent
	dst.WireBytesReceived += s.WireBytesReceived
	dst.PayloadSent += s.PayloadSent
	dst.PayloadReceived += s.PayloadReceived
	dst.RecoveredShards += s.RecoveredShards
	dst.InvalidPackets += s.InvalidPackets
}
func (t *Tracker) add(c *PacketConn) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.active == nil {
		t.active = make(map[*PacketConn]struct{})
	}
	t.active[c] = struct{}{}
}
func (t *Tracker) remove(c *PacketConn) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if _, ok := t.active[c]; ok {
		addStats(&t.closed, c.Stats())
		delete(t.active, c)
	}
}
func (t *Tracker) Snapshot() Stats {
	t.mu.Lock()
	defer t.mu.Unlock()
	s := t.closed
	for c := range t.active {
		addStats(&s, c.Stats())
	}
	return s
}
