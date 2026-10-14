package easytier

import "testing"

func TestStableRecoverySignature(t *testing.T) {
	s := StableChange{}
	for _, x := range []struct {
		value   string
		changed bool
	}{{"wifi-a", false}, {"", false}, {"wifi-b", false}, {"wifi-a", false}, {"wifi-b", false}, {"wifi-b", true}, {"wifi-b", false}, {"new-gateway", false}, {"new-gateway", true}} {
		if got := s.Observe(x.value); got != x.changed {
			t.Fatalf("%s: %v", x.value, got)
		}
	}
	if s.Accepted != "new-gateway" {
		t.Fatal(s.Accepted)
	}
}
