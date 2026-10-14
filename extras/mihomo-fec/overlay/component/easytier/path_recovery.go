package easytier

import (
	"errors"
	"syscall"
	"time"
)

// PathRecovery is owned by the outbound's instance mutex. A running SDK can
// lose its overlay data path while its peer connector continues reconnecting.
// Only explicit overlay route errors count; slow destinations and cancelled
// probes must not tear down a working instance.
type PathRecovery struct {
	started, firstFailure time.Time
	failures              uint64
}

func (p *PathRecovery) Reset(now time.Time) { *p = PathRecovery{started: now} }
func (p *PathRecovery) Observe(now time.Time, err error) {
	if err == nil {
		p.firstFailure = time.Time{}
		p.failures = 0
		return
	}
	if !errors.Is(err, syscall.ENETUNREACH) && !errors.Is(err, syscall.ENETRESET) {
		return
	}
	if p.firstFailure.IsZero() {
		p.firstFailure = now
	}
	p.failures++
}

func (p *PathRecovery) Due(now time.Time) bool {
	return p.failures >= 2 && !p.firstFailure.IsZero() &&
		now.Sub(p.firstFailure) >= 10*time.Second && now.Sub(p.started) >= 30*time.Second
}

func (p *PathRecovery) Failures() uint64 { return p.failures }
