package udpspeeder

import (
	"container/heap"
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"net"
	"net/netip"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

type Option struct {
	Type         string "proxy:\"type\" json:\"type\""
	Key          string "proxy:\"key\" json:\"-\""
	DataShards   int    "proxy:\"data-shards\" json:\"data_shards\""
	ParityShards int    "proxy:\"parity-shards\" json:\"parity_shards\""
	Timeout      int    "proxy:\"timeout\" json:\"timeout_ms\""
	Interval     int    "proxy:\"interval\" json:\"interval_ms\""
	MTU          int    "proxy:\"mtu\" json:\"mtu\""
	Ports        []int  "proxy:\"ports\" json:\"ports\""
}

func (o *Option) Validate() error {
	if o.Type == "" {
		o.Type = "udpspeeder-v2"
	}
	if o.Type != "udpspeeder-v2" {
		return errors.New("udpspeeder: only V2 mode0 is supported")
	}
	if o.DataShards == 0 {
		o.DataShards = 2
	}
	if o.ParityShards == 0 {
		o.ParityShards = 30
	}
	if o.Timeout == 0 {
		o.Timeout = 1
	}
	if o.MTU == 0 {
		o.MTU = 1250
	}
	if o.DataShards < 1 || o.DataShards > 32 || o.ParityShards < 1 || o.ParityShards > 64 || o.DataShards+o.ParityShards >= 255 || o.Timeout < 1 || o.Timeout > 100 || o.Interval < 0 || o.Interval > 100 || o.MTU < 512 || o.MTU > 1250 {
		return errors.New("udpspeeder: FEC parameters out of supported bounds")
	}
	if len(o.Key) == 0 || len(o.Key) > 128 {
		return errors.New("udpspeeder: a nonempty compatibility key is required")
	}
	for _, p := range o.Ports {
		if p < 1 || p > 65535 {
			return errors.New("udpspeeder: invalid peer port")
		}
	}
	if len(o.Ports) == 0 {
		return errors.New("udpspeeder: explicitly list FEC peer ports")
	}
	return nil
}

type Dialer interface {
	DialContext(context.Context, string, string) (net.Conn, error)
	ListenPacket(context.Context, string, string, netip.AddrPort) (net.PacketConn, error)
}
type FECdialer struct {
	Dialer
	Option  Option
	Tracker *Tracker
}

func (d FECdialer) ListenPacket(ctx context.Context, network, address string, remote netip.AddrPort) (net.PacketConn, error) {
	pc, err := d.Dialer.ListenPacket(ctx, network, address, remote)
	if err != nil {
		return nil, err
	}
	conn, err := newPacketConn(pc, d.Option, d.Tracker)
	if err != nil {
		pc.Close()
		return nil, err
	}
	return conn, nil
}

type packet struct {
	data []byte
	addr net.Addr
}
type group struct {
	data [][]byte
	addr net.Addr
}
type scheduled struct {
	at time.Time
	packet
}
type schedule []scheduled

func (h schedule) Len() int           { return len(h) }
func (h schedule) Less(i, j int) bool { return h[i].at.Before(h[j].at) }
func (h schedule) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *schedule) Push(x any)        { *h = append(*h, x.(scheduled)) }
func (h *schedule) Pop() any          { a := *h; x := a[len(a)-1]; *h = a[:len(a)-1]; return x }

type retainedGroup struct {
	decodeGroup
	at time.Time
}
type Stats struct {
	WireSent          uint64 "json:\"wire_sent\""
	WireReceived      uint64 "json:\"wire_received\""
	WireBytesSent     uint64 "json:\"wire_bytes_sent\""
	WireBytesReceived uint64 "json:\"wire_bytes_received\""
	PayloadSent       uint64 "json:\"payload_sent\""
	PayloadReceived   uint64 "json:\"payload_received\""
	RecoveredShards   uint64 "json:\"recovered_shards\""
	InvalidPackets    uint64 "json:\"invalid_packets\""
}
type PacketConn struct {
	writeDeadline                                                                                              time.Time
	tracker                                                                                                    *Tracker
	raw                                                                                                        net.PacketConn
	option                                                                                                     Option
	ports                                                                                                      map[int]bool
	conv                                                                                                       uint32
	sequence                                                                                                   uint32
	done                                                                                                       chan struct{}
	writes                                                                                                     chan packet
	groups                                                                                                     chan group
	reads                                                                                                      chan packet
	closeOnce                                                                                                  sync.Once
	deadlineMu                                                                                                 sync.Mutex
	readDeadline                                                                                               time.Time
	deadlineChange                                                                                             chan struct{}
	wireSent, wireReceived, wireBytesSent, wireBytesReceived, payloadSent, payloadReceived, recovered, invalid atomic.Uint64
}

func NewPacketConn(raw net.PacketConn, o Option) (*PacketConn, error) {
	return newPacketConn(raw, o, nil)
}
func newPacketConn(raw net.PacketConn, o Option, tracker *Tracker) (*PacketConn, error) {
	if err := o.Validate(); err != nil {
		return nil, err
	}
	var seed [8]byte
	if _, err := rand.Read(seed[:]); err != nil {
		return nil, err
	}
	c := &PacketConn{raw: raw, option: o, ports: map[int]bool{}, conv: binary.BigEndian.Uint32(seed[:4]), sequence: binary.BigEndian.Uint32(seed[4:]), done: make(chan struct{}), writes: make(chan packet, 512), groups: make(chan group, 64), reads: make(chan packet, 512), deadlineChange: make(chan struct{})}
	for _, p := range o.Ports {
		c.ports[p] = true
	}
	c.tracker = tracker
	if tracker != nil {
		tracker.add(c)
	}
	go c.encodeLoop()
	go c.sendLoop()
	go c.readLoop()
	return c, nil
}
func port(a net.Addr) int {
	if u, ok := a.(*net.UDPAddr); ok {
		return u.Port
	}
	_, p, err := net.SplitHostPort(a.String())
	if err != nil {
		return 0
	}
	i, _ := strconv.Atoi(p)
	return i
}
func cloneAddr(a net.Addr) net.Addr {
	if u, ok := a.(*net.UDPAddr); ok {
		v := *u
		v.IP = append(net.IP(nil), u.IP...)
		return &v
	}
	return a
}
func (c *PacketConn) WriteTo(b []byte, a net.Addr) (int, error) {
	if a == nil {
		return 0, errors.New("udpspeeder: missing destination")
	}
	select {
	case <-c.done:
		return 0, net.ErrClosed
	default:
	}
	if !c.ports[port(a)] {
		return c.raw.WriteTo(b, a)
	}
	if len(b)+10 > c.option.DataShards*c.option.MTU {
		return 0, errors.New("udpspeeder: payload exceeds configured FEC capacity")
	}
	p := make([]byte, len(b)+4)
	binary.BigEndian.PutUint32(p, c.conv)
	copy(p[4:], b)
	c.deadlineMu.Lock()
	at := c.writeDeadline
	c.deadlineMu.Unlock()
	var timer *time.Timer
	var timeout <-chan time.Time
	if !at.IsZero() {
		left := time.Until(at)
		if left <= 0 {
			return 0, os.ErrDeadlineExceeded
		}
		timer = time.NewTimer(left)
		defer timer.Stop()
		timeout = timer.C
	}
	select {
	case c.writes <- packet{p, cloneAddr(a)}:
		c.payloadSent.Add(1)
		return len(b), nil
	case <-c.done:
		return 0, net.ErrClosed
	case <-timeout:
		return 0, os.ErrDeadlineExceeded
	}
}
func (c *PacketConn) encodeLoop() {
	var pending [][]byte
	var dest net.Addr
	size := 4
	timer := time.NewTimer(time.Hour)
	timer.Stop()
	defer timer.Stop()
	var tick <-chan time.Time
	flush := func() bool {
		if len(pending) == 0 {
			return true
		}
		frames, err := encodeGroup(c.sequence, pending, c.option.DataShards, c.option.ParityShards, c.option.MTU)
		if err != nil {
			c.invalid.Add(1)
			c.Close()
			return false
		}
		c.sequence++
		g := group{frames, dest}
		pending = nil
		size = 4
		timer.Stop()
		tick = nil
		select {
		case c.groups <- g:
			return true
		case <-c.done:
			return false
		}
	}
	for {
		select {
		case <-c.done:
			return
		case <-tick:
			if !flush() {
				return
			}
		case p := <-c.writes:
			if len(pending) > 0 && (dest.String() != p.addr.String() || size+2+len(p.data) > c.option.DataShards*c.option.MTU || len(pending) >= 200) {
				if !flush() {
					return
				}
			}
			if len(pending) == 0 {
				dest = p.addr
				timer.Reset(time.Duration(c.option.Timeout) * time.Millisecond)
				tick = timer.C
			}
			pending = append(pending, p.data)
			size += 2 + len(p.data)
		}
	}
}
func (c *PacketConn) sendLoop() {
	var q schedule
	heap.Init(&q)
	timer := time.NewTimer(time.Hour)
	timer.Stop()
	defer timer.Stop()
	for {
		for len(q) > 0 && !q[0].at.After(time.Now()) {
			p := heap.Pop(&q).(scheduled)
			wire, err := cook(p.data, []byte(c.option.Key))
			if err != nil {
				c.Close()
				return
			}
			n, err := c.raw.WriteTo(wire, p.addr)
			if err != nil {
				c.Close()
				return
			}
			c.wireSent.Add(1)
			c.wireBytesSent.Add(uint64(n))
		}
		var tick <-chan time.Time
		ch := c.groups
		if len(q) >= 4096 {
			ch = nil
		}
		if len(q) > 0 {
			timer.Reset(time.Until(q[0].at))
			tick = timer.C
		}
		select {
		case <-c.done:
			return
		case <-tick:
		case g := <-ch:
			start := time.Now()
			for i, data := range g.data {
				delay := time.Duration(0)
				if len(g.data) > 1 {
					delay = time.Duration(c.option.Interval) * time.Millisecond * time.Duration(i) / time.Duration(len(g.data)-1)
				}
				heap.Push(&q, scheduled{start.Add(delay), packet{data, g.addr}})
			}
		}
		timer.Stop()
	}
}
func (c *PacketConn) deliver(p packet) bool {
	select {
	case c.reads <- p:
		return true
	case <-c.done:
		return false
	}
}
func (c *PacketConn) readLoop() {
	groups := map[string]*retainedGroup{}
	completed := map[string]time.Time{}
	buf := make([]byte, 65535)
	lastSweep := time.Now()
	for {
		n, a, err := c.raw.ReadFrom(buf)
		if err != nil {
			c.Close()
			return
		}
		if !c.ports[port(a)] {
			if !c.deliver(packet{append([]byte(nil), buf[:n]...), cloneAddr(a)}) {
				return
			}
			continue
		}
		c.wireReceived.Add(1)
		c.wireBytesReceived.Add(uint64(n))
		data, err := uncook(buf[:n], []byte(c.option.Key))
		if err != nil {
			c.invalid.Add(1)
			continue
		}
		seq, k, p, index, shard, err := parseGroup(data)
		if err != nil {
			c.invalid.Add(1)
			continue
		}
		key := a.String() + "/" + strconv.FormatUint(uint64(seq), 10)
		now := time.Now()
		if now.Sub(lastSweep) > time.Second {
			for id, g := range groups {
				if now.Sub(g.at) > 10*time.Second {
					delete(groups, id)
				}
			}
			for id, at := range completed {
				if now.Sub(at) > 120*time.Second {
					delete(completed, id)
				}
			}
			lastSweep = now
		}
		if _, ok := completed[key]; ok {
			continue
		}
		g := groups[key]
		if g == nil {
			if len(groups) >= 128 {
				old := ""
				for id, v := range groups {
					if old == "" || v.at.Before(groups[old].at) {
						old = id
					}
				}
				delete(groups, old)
			}
			g = &retainedGroup{decodeGroup{k: k, p: p, length: len(shard), shards: make([][]byte, k+p)}, now}
			groups[key] = g
		}
		if g.k != k || g.p != p || g.length != len(shard) {
			c.invalid.Add(1)
			continue
		}
		missing := 0
		for _, b := range g.shards[:k] {
			if b == nil {
				missing++
			}
		}
		if index < k && g.shards[index] == nil {
			missing--
		}
		packets, err := g.add(index, shard)
		if err != nil {
			c.invalid.Add(1)
			delete(groups, key)
			completed[key] = now
			continue
		}
		if packets == nil {
			continue
		}
		c.recovered.Add(uint64(missing))
		delete(groups, key)
		if len(completed) >= 8192 {
			for id := range completed {
				delete(completed, id)
				break
			}
		}
		completed[key] = now
		for _, b := range packets {
			if len(b) < 4 || binary.BigEndian.Uint32(b) != c.conv {
				continue
			}
			c.payloadReceived.Add(1)
			if !c.deliver(packet{b[4:], cloneAddr(a)}) {
				return
			}
		}
	}
}
func (c *PacketConn) ReadFrom(b []byte) (int, net.Addr, error) {
	for {
		c.deadlineMu.Lock()
		at, change := c.readDeadline, c.deadlineChange
		c.deadlineMu.Unlock()
		var timer *time.Timer
		var timeout <-chan time.Time
		if !at.IsZero() {
			remaining := time.Until(at)
			if remaining <= 0 {
				return 0, nil, os.ErrDeadlineExceeded
			}
			timer = time.NewTimer(remaining)
			timeout = timer.C
		}
		select {
		case p := <-c.reads:
			if timer != nil {
				timer.Stop()
			}
			return copy(b, p.data), p.addr, nil
		case <-timeout:
			return 0, nil, os.ErrDeadlineExceeded
		case <-change:
			if timer != nil {
				timer.Stop()
			}
			continue
		case <-c.done:
			if timer != nil {
				timer.Stop()
			}
			return 0, nil, net.ErrClosed
		}
	}
}
func (c *PacketConn) Close() error {
	var err error
	c.closeOnce.Do(func() {
		close(c.done)
		err = c.raw.Close()
		if c.tracker != nil {
			c.tracker.remove(c)
		}
	})
	return err
}
func (c *PacketConn) LocalAddr() net.Addr { return c.raw.LocalAddr() }
func (c *PacketConn) SetReadDeadline(t time.Time) error {
	c.deadlineMu.Lock()
	c.readDeadline = t
	close(c.deadlineChange)
	c.deadlineChange = make(chan struct{})
	c.deadlineMu.Unlock()
	return nil
}
func (c *PacketConn) SetWriteDeadline(t time.Time) error {
	c.deadlineMu.Lock()
	c.writeDeadline = t
	c.deadlineMu.Unlock()
	return c.raw.SetWriteDeadline(t)
}
func (c *PacketConn) SetDeadline(t time.Time) error {
	c.SetReadDeadline(t)
	return c.SetWriteDeadline(t)
}
func (c *PacketConn) Stats() Stats {
	return Stats{c.wireSent.Load(), c.wireReceived.Load(), c.wireBytesSent.Load(), c.wireBytesReceived.Load(), c.payloadSent.Load(), c.payloadReceived.Load(), c.recovered.Load(), c.invalid.Load()}
}
