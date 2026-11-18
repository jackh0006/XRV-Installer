package socks

import "sync/atomic"

// Payload counters for the Android UI. These count bytes actually handed to
// or received from SOCKS clients, not raw TUN packets, so the displayed
// traffic is real tunnel traffic rather than interface bookkeeping.
var (
	upBytes      atomic.Uint64
	downBytes    atomic.Uint64
	sessionCount atomic.Uint64
)

func RecordUp(n int) {
	if n > 0 {
		upBytes.Add(uint64(n))
	}
}

func RecordDown(n int) {
	if n > 0 {
		downBytes.Add(uint64(n))
	}
}

func RecordSession() { sessionCount.Add(1) }

func ResetStats() {
	upBytes.Store(0)
	downBytes.Store(0)
	sessionCount.Store(0)
}

func Stats() (up, down, sessions uint64) {
	return upBytes.Load(), downBytes.Load(), sessionCount.Load()
}
