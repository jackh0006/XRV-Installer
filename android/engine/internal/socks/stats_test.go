package socks

import "testing"

func TestStatsCounters(t *testing.T) {
	ResetStats()
	RecordUp(10)
	RecordUp(5)
	RecordDown(20)
	RecordSession()
	up, down, sessions := Stats()
	if up != 15 || down != 20 || sessions != 1 {
		t.Fatalf("stats = %d/%d/%d, want 15/20/1", up, down, sessions)
	}
	ResetStats()
	up, down, sessions = Stats()
	if up != 0 || down != 0 || sessions != 0 {
		t.Fatalf("reset stats = %d/%d/%d, want 0/0/0", up, down, sessions)
	}
}
