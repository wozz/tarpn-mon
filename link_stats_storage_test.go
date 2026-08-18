package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// newTestStorage creates a temporary LinkStatsStorage backed by a file in t.TempDir().
func newTestStorage(t *testing.T) *LinkStatsStorage {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "test.db")
	s, err := NewLinkStatsStorage(dbPath)
	if err != nil {
		t.Fatalf("NewLinkStatsStorage: %v", err)
	}
	t.Cleanup(func() {
		s.Close()
		os.Remove(dbPath)
	})
	return s
}

func TestGet15MinSummaryRange(t *testing.T) {
	s := newTestStorage(t)

	// Insert raw data points across several 15-minute buckets for port 1.
	// We'll insert counter snapshots that increase monotonically.
	base := time.Date(2025, 1, 15, 0, 0, 0, 0, time.UTC)
	port := 1

	// Helper to insert a raw row with given absolute counters.
	insertRaw := func(ts time.Time, rxed, sent, timeouts, rej, crc, abandoned int64, txPct, busyPct int) {
		t.Helper()
		_, err := s.db.Exec(`
			INSERT INTO link_stats_raw
			(timestamp, port_num, l2_rxed, l2_sent, l2_timeouts, rej_rxed,
			 rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			ts.UTC().Format(time.RFC3339), port,
			rxed, sent, timeouts, rej, crc, abandoned, txPct, busyPct)
		if err != nil {
			t.Fatalf("insert raw: %v", err)
		}
	}

	// Bucket 00:00–00:15: 3 points at 00:01, 00:05, 00:10
	insertRaw(base.Add(1*time.Minute), 100, 200, 10, 1, 0, 0, 5, 10)
	insertRaw(base.Add(5*time.Minute), 120, 230, 12, 2, 1, 0, 6, 12)
	insertRaw(base.Add(10*time.Minute), 150, 260, 15, 3, 1, 0, 7, 14)

	// Bucket 00:15–00:30: 2 points at 00:16, 00:20
	insertRaw(base.Add(16*time.Minute), 160, 280, 16, 3, 1, 0, 8, 15)
	insertRaw(base.Add(20*time.Minute), 200, 320, 20, 5, 2, 1, 10, 20)

	// Bucket 00:30–00:45: 1 point (should appear with zero deltas)
	insertRaw(base.Add(32*time.Minute), 210, 330, 21, 5, 2, 1, 11, 21)

	since := base
	until := base.Add(1 * time.Hour)

	summaries, err := s.Get15MinSummaryRange(port, since, until)
	if err != nil {
		t.Fatalf("Get15MinSummaryRange: %v", err)
	}

	if len(summaries) != 3 {
		t.Fatalf("expected 3 buckets, got %d", len(summaries))
	}

	// Bucket 0 (00:00): delta from first(100,200,10) to last(150,260,15)
	b0 := summaries[0]
	if b0.BucketStart != base {
		t.Errorf("bucket 0 start: got %v, want %v", b0.BucketStart, base)
	}
	if b0.DeltaL2Rxed != 50 {
		t.Errorf("bucket 0 DeltaL2Rxed: got %d, want 50", b0.DeltaL2Rxed)
	}
	if b0.DeltaL2Sent != 60 {
		t.Errorf("bucket 0 DeltaL2Sent: got %d, want 60", b0.DeltaL2Sent)
	}
	if b0.DeltaL2Timeouts != 5 {
		t.Errorf("bucket 0 DeltaL2Timeouts: got %d, want 5", b0.DeltaL2Timeouts)
	}
	if b0.SampleCount != 3 {
		t.Errorf("bucket 0 SampleCount: got %d, want 3", b0.SampleCount)
	}

	// Bucket 1 (00:15): delta from first(160,280,16) to last(200,320,20)
	b1 := summaries[1]
	if b1.BucketStart != base.Add(15*time.Minute) {
		t.Errorf("bucket 1 start: got %v, want %v", b1.BucketStart, base.Add(15*time.Minute))
	}
	if b1.DeltaL2Rxed != 40 {
		t.Errorf("bucket 1 DeltaL2Rxed: got %d, want 40", b1.DeltaL2Rxed)
	}
	if b1.DeltaL2Sent != 40 {
		t.Errorf("bucket 1 DeltaL2Sent: got %d, want 40", b1.DeltaL2Sent)
	}
	if b1.SampleCount != 2 {
		t.Errorf("bucket 1 SampleCount: got %d, want 2", b1.SampleCount)
	}

	// Bucket 2 (00:30): single point → zero deltas
	b2 := summaries[2]
	if b2.BucketStart != base.Add(30*time.Minute) {
		t.Errorf("bucket 2 start: got %v, want %v", b2.BucketStart, base.Add(30*time.Minute))
	}
	if b2.DeltaL2Rxed != 0 {
		t.Errorf("bucket 2 DeltaL2Rxed: got %d, want 0", b2.DeltaL2Rxed)
	}
	if b2.SampleCount != 1 {
		t.Errorf("bucket 2 SampleCount: got %d, want 1", b2.SampleCount)
	}
}

func TestGetNeighborCallsigns(t *testing.T) {
	s := newTestStorage(t)

	// Insert neighbor CQ data: multiple entries per port, different timestamps.
	insertNeighbor := func(ts time.Time, call string, reportedPort, rxPort int) {
		t.Helper()
		_, err := s.db.Exec(`
			INSERT INTO link_stats_neighbor
			(timestamp, callsign, reported_port, rx_port,
			 l2_rxed, l2_sent, l2_timeouts, rej_rxed,
			 rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct)
			VALUES (?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0)`,
			ts.UTC().Format(time.RFC3339), call, reportedPort, rxPort)
		if err != nil {
			t.Fatalf("insert neighbor: %v", err)
		}
	}

	base := time.Date(2025, 1, 15, 12, 0, 0, 0, time.UTC)

	// Port 1: older entry from WA2M-2, newer entry from WA2M-2 (same call, updated)
	insertNeighbor(base, "WA2M-2", 3, 1)
	insertNeighbor(base.Add(10*time.Minute), "WA2M-2", 3, 1)

	// Port 2: older entry from K3ABC, newer entry from K3ABC-5
	insertNeighbor(base, "K3ABC", 1, 2)
	insertNeighbor(base.Add(20*time.Minute), "K3ABC-5", 1, 2)

	// Port 3: single entry
	insertNeighbor(base.Add(5*time.Minute), "N0CALL", 2, 3)

	result, err := s.GetNeighborCallsigns("TESTNODE")
	if err != nil {
		t.Fatalf("GetNeighborCallsigns: %v", err)
	}

	if len(result) != 3 {
		t.Fatalf("expected 3 ports, got %d: %v", len(result), result)
	}

	// Port 1: most recent is WA2M-2
	if result[1] != "WA2M-2" {
		t.Errorf("port 1: got %q, want %q", result[1], "WA2M-2")
	}

	// Port 2: most recent is K3ABC-5
	if result[2] != "K3ABC-5" {
		t.Errorf("port 2: got %q, want %q", result[2], "K3ABC-5")
	}

	// Port 3: N0CALL
	if result[3] != "N0CALL" {
		t.Errorf("port 3: got %q, want %q", result[3], "N0CALL")
	}
}

func TestGetNeighborCallsignsExcludesLocal(t *testing.T) {
	s := newTestStorage(t)

	insertNeighbor := func(ts time.Time, call string, reportedPort, rxPort int) {
		t.Helper()
		_, err := s.db.Exec(`
			INSERT INTO link_stats_neighbor
			(timestamp, callsign, reported_port, rx_port,
			 l2_rxed, l2_sent, l2_timeouts, rej_rxed,
			 rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct)
			VALUES (?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0)`,
			ts.UTC().Format(time.RFC3339), call, reportedPort, rxPort)
		if err != nil {
			t.Fatalf("insert neighbor: %v", err)
		}
	}

	base := time.Date(2025, 1, 15, 12, 0, 0, 0, time.UTC)

	// Port 1: neighbor entry, then our own CQ (most recent)
	insertNeighbor(base, "N3LLO-2", 1, 1)
	insertNeighbor(base.Add(10*time.Minute), "WA2M-2", 3, 1)

	// Port 2: only our own CQ — should not appear
	insertNeighbor(base, "WA2M-2", 1, 2)

	result, err := s.GetNeighborCallsigns("WA2M-2")
	if err != nil {
		t.Fatalf("GetNeighborCallsigns: %v", err)
	}

	// Port 1: should return N3LLO-2 (most recent non-local)
	if result[1] != "N3LLO-2" {
		t.Errorf("port 1: got %q, want %q", result[1], "N3LLO-2")
	}

	// Port 2: should not exist (only local CQ)
	if _, ok := result[2]; ok {
		t.Errorf("port 2: should not be present, got %q", result[2])
	}
}

func TestGetNeighborCallsignsEmpty(t *testing.T) {
	s := newTestStorage(t)

	result, err := s.GetNeighborCallsigns("N0CALL")
	if err != nil {
		t.Fatalf("GetNeighborCallsigns: %v", err)
	}

	if len(result) != 0 {
		t.Errorf("expected empty map, got %v", result)
	}
}
