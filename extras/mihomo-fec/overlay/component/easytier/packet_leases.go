package easytier

import (
	"net"
	"sync"
)

// PacketLeases closes application sockets from a retired overlay generation.
// Otherwise a tunnel NAT entry can keep writing to the retired SDK instance.
type PacketLeases struct {
	mu         sync.Mutex
	generation uint64
	active     map[*leasedPacket]struct{}
}

func (s *PacketLeases) Generation() uint64 { s.mu.Lock(); defer s.mu.Unlock(); return s.generation }
func (s *PacketLeases) Track(pc net.PacketConn, generation uint64) (net.PacketConn, bool) {
	s.mu.Lock()
	if generation != s.generation {
		s.mu.Unlock()
		_ = pc.Close()
		return nil, false
	}
	if s.active == nil {
		s.active = make(map[*leasedPacket]struct{})
	}
	p := &leasedPacket{PacketConn: pc, owner: s}
	s.active[p] = struct{}{}
	s.mu.Unlock()
	return p, true
}
func (s *PacketLeases) CloseAll() {
	s.mu.Lock()
	s.generation++
	old := s.active
	s.active = nil
	s.mu.Unlock()
	for p := range old {
		_ = p.Close()
	}
}

type leasedPacket struct {
	net.PacketConn
	owner *PacketLeases
	once  sync.Once
	err   error
}

func (p *leasedPacket) Close() error {
	p.once.Do(func() {
		p.owner.mu.Lock()
		delete(p.owner.active, p)
		p.owner.mu.Unlock()
		p.err = p.PacketConn.Close()
	})
	return p.err
}
