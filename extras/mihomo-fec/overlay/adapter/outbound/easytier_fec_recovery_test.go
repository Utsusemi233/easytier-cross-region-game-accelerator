//go:build !no_easytier

package outbound

import (
	"syscall"
	"testing"
	"time"

	corehost "github.com/easytier/easytier/easytier-go"
	"github.com/metacubex/mihomo/component/udpspeeder"
)

func TestFECRouteFailuresBelongToCurrentSDKInstance(t *testing.T) {
	old, current := &corehost.Instance{}, &corehost.Instance{}
	e := &EasyTier{instance: current, option: EasyTierOption{UDPFEC: &udpspeeder.Option{}}}
	e.pathRecovery.Reset(time.Now().Add(-time.Minute))
	e.observePathResult(old, syscall.ENETUNREACH)
	if e.pathRecovery.Failures() != 0 {
		t.Fatal("retired instance scheduled another restart")
	}
	e.observePathResult(current, syscall.ENETUNREACH)
	e.observePathResult(old, nil)
	if e.pathRecovery.Failures() != 1 {
		t.Fatal("old instance success hid current failure")
	}
	e.observePathResult(current, nil)
	if e.pathRecovery.Failures() != 0 {
		t.Fatal("current path success did not cancel restart")
	}
	e.option.UDPFEC = nil
	e.observePathResult(current, syscall.ENETUNREACH)
	if e.pathRecovery.Failures() != 0 {
		t.Fatal("ordinary upstream EasyTier behavior changed")
	}
}
