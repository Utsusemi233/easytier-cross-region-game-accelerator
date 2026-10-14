package dns

import (
	"context"
	"errors"
	D "github.com/miekg/dns"
	"net"
	"testing"
	"time"
)

type changingPeerDNS struct {
	address string
	fail    bool
	calls   int
}

func (c *changingPeerDNS) Address() string  { return "fixture" }
func (c *changingPeerDNS) ResetConnection() {}
func (c *changingPeerDNS) ExchangeContext(ctx context.Context, m *D.Msg) (*D.Msg, error) {
	c.calls++
	if c.fail {
		return nil, errors.New("fixture upstream unavailable")
	}
	out := new(D.Msg)
	out.SetReply(m)
	out.Answer = []D.RR{&D.AAAA{Hdr: D.RR_Header{Name: m.Question[0].Name, Rrtype: D.TypeAAAA, Class: D.ClassINET, Ttl: 3600}, AAAA: net.ParseIP(c.address)}}
	return out, nil
}
func TestPeerRecoveryRefreshDoesNotFlushApplicationCache(t *testing.T) {
	c := &changingPeerDNS{address: "2001:db8::1"}
	r := &Resolver{ipv6: true, main: []dnsClient{c}, cache: (Config{}).newCache()}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	first, err := r.LookupIPv6(ctx, "peer.example")
	if err != nil || first[0].String() != c.address {
		t.Fatal(first, err)
	}
	_, err = r.LookupIPv6(ctx, "app.example")
	if err != nil {
		t.Fatal(err)
	}
	c.address = "2001:db8::2"
	old, _ := r.LookupIPv6(ctx, "peer.example")
	if old[0].String() != "2001:db8::1" {
		t.Fatal("fixture must retain its 1h old cache")
	}
	fresh, err := r.LookupFreshIP(ctx, "peer.example", true)
	if err != nil || fresh[0].String() != c.address {
		t.Fatal(fresh, err)
	}
	cached, _ := r.LookupIPv6(ctx, "peer.example")
	if cached[0].String() != c.address {
		t.Fatal("dialer's peer cache was not updated")
	}
	before := c.calls
	app, _ := r.LookupIPv6(ctx, "app.example")
	if app[0].String() != "2001:db8::1" || c.calls != before {
		t.Fatal("unrelated application cache changed")
	}
}
