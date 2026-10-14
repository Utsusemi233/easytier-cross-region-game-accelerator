package easytier

import (
	"context"
	"fmt"
	"net"
	"syscall"
	"testing"
	"time"
)

func TestPathRecoveryWaitsForPersistentRouteFailure(t *testing.T) {
	now := time.Unix(1000, 0)
	var p PathRecovery
	p.Reset(now)
	p.Observe(now, &net.OpError{Op: "dial", Err: syscall.ENETUNREACH})
	p.Observe(now.Add(time.Second), fmt.Errorf("overlay: %w", syscall.ENETRESET))
	if p.Due(now.Add(29 * time.Second)) {
		t.Fatal("cold connection restarted before grace")
	}
	if !p.Due(now.Add(30 * time.Second)) {
		t.Fatal("persistent broken path not recovered")
	}
	p.Reset(now.Add(30 * time.Second))
	if p.Due(now.Add(31*time.Second)) || p.Failures() != 0 {
		t.Fatal("retired failures leaked into new instance")
	}
}

func TestPathRecoveryIgnoresUnrelatedErrorsAndClearsOnSuccess(t *testing.T) {
	now := time.Unix(1000, 0)
	var p PathRecovery
	p.Reset(now)
	for _, err := range []error{context.Canceled, context.DeadlineExceeded, syscall.ECONNREFUSED, net.ErrClosed} {
		p.Observe(now.Add(time.Minute), err)
	}
	if p.Failures() != 0 || p.Due(now.Add(2*time.Minute)) {
		t.Fatal("destination or caller failure restarted overlay")
	}
	p.Observe(now.Add(time.Minute), syscall.ENETUNREACH)
	if p.Due(now.Add(2 * time.Minute)) {
		t.Fatal("one route error caused restart")
	}
	p.Observe(now.Add(time.Minute+time.Second), syscall.ENETUNREACH)
	if p.Due(now.Add(time.Minute + 9*time.Second)) {
		t.Fatal("transient route gap caused restart")
	}
	p.Observe(now.Add(time.Minute+9*time.Second), nil)
	if p.Due(now.Add(2*time.Minute)) || p.Failures() != 0 {
		t.Fatal("successful data path did not cancel recovery")
	}
}
