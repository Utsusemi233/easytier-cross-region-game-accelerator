package easytier

// StableChange confirms a changed signature twice. Empty windows preserve the
// last accepted signature; they never become a permanent fixed address.
type StableChange struct {
	Accepted, Candidate string
	Count               int
}

func (s *StableChange) Observe(value string) bool {
	if value == "" {
		s.Candidate = ""
		s.Count = 0
		return false
	}
	if s.Accepted == "" {
		s.Accepted = value
		return false
	}
	if value == s.Accepted {
		s.Candidate = ""
		s.Count = 0
		return false
	}
	if value != s.Candidate {
		s.Candidate = value
		s.Count = 1
		return false
	}
	s.Count++
	if s.Count < 2 {
		return false
	}
	s.Accepted = value
	s.Candidate = ""
	s.Count = 0
	return true
}
