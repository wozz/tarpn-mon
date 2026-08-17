package main

import (
	"encoding/json"
	"path/filepath"
	"testing"
	"time"
)

// insertRaw writes a raw sample directly, bypassing SaveSnapshot so the test can
// control the timestamp.
func insertRaw(t *testing.T, s *LinkStatsStorage, ts time.Time, port int, rxed, sent int64) {
	t.Helper()
	_, err := s.db.Exec(`
		INSERT INTO link_stats_raw
			(timestamp, port_num, l2_rxed, l2_sent, l2_timeouts, rej_rxed,
			 rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct)
		VALUES (?, ?, ?, ?, 0, 0, 0, 0, 10, 20)`,
		ts.UTC().Format(time.RFC3339), port, rxed, sent)
	if err != nil {
		t.Fatalf("insert raw: %v", err)
	}
}

func newTestStorage(t *testing.T) *LinkStatsStorage {
	t.Helper()
	s, err := NewLinkStatsStorage(filepath.Join(t.TempDir(), "linkstats.db"))
	if err != nil {
		t.Fatalf("open storage: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

// Raw samples from completed hours must turn into hourly rows the moment
// compaction runs. Before the startup call was added, compaction only happened
// on a one-hour ticker, so a service restarted more often than that never
// compacted and the stats page had nothing to plot.
func TestCompactHourlyProducesHistory(t *testing.T) {
	s := newTestStorage(t)

	// Three hours of samples ending an hour ago, so they are all in completed
	// hours that compaction is willing to touch.
	base := time.Now().UTC().Truncate(time.Hour).Add(-3 * time.Hour)
	var n int64
	for h := 0; h < 2; h++ {
		for m := 0; m < 60; m += 10 {
			n += 100
			insertRaw(t, s, base.Add(time.Duration(h)*time.Hour+time.Duration(m)*time.Minute), 2, n, n*2)
		}
	}

	if got, err := s.GetHourlySummary(2, base.Add(-time.Hour)); err != nil {
		t.Fatalf("GetHourlySummary: %v", err)
	} else if len(got) != 0 {
		t.Fatalf("expected no hourly rows before compaction, got %d", len(got))
	}

	if err := s.CompactHourly(); err != nil {
		t.Fatalf("CompactHourly: %v", err)
	}

	got, err := s.GetHourlySummary(2, base.Add(-time.Hour))
	if err != nil {
		t.Fatalf("GetHourlySummary after compaction: %v", err)
	}
	if len(got) == 0 {
		t.Fatal("no hourly summaries after compaction; the stats graph would be empty")
	}
	for _, h := range got {
		if h.PortNum != 2 {
			t.Errorf("port = %d, want 2", h.PortNum)
		}
		if h.SampleCount == 0 {
			t.Errorf("hour %s has no samples", h.HourStart)
		}
	}
}

// The client keys off hourStart/dL2Rxed/dL2Sent. Five-minute buckets are only
// useful as a fallback if they serialise under exactly those names, since the
// client is not told which resolution it received.
func TestHourlyFrom5MinMatchesClientFields(t *testing.T) {
	in := []FiveMinSummary{{
		BucketStart: time.Date(2026, 8, 17, 10, 5, 0, 0, time.UTC),
		PortNum:     3,
		DeltaL2Rxed: 42,
		DeltaL2Sent: 43,
		AvgTxPct:    1.5,
		SampleCount: 5,
	}}

	out := hourlyFrom5Min(in)
	if len(out) != 1 {
		t.Fatalf("expected 1 summary, got %d", len(out))
	}

	var m map[string]any
	b, err := json.Marshal(out[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"hourStart", "dL2Rxed", "dL2Sent", "dL2Timeouts", "portNum"} {
		if _, ok := m[key]; !ok {
			t.Errorf("serialised summary is missing %q, which the chart reads: %s", key, b)
		}
	}
	if m["dL2Rxed"] != float64(42) {
		t.Errorf("dL2Rxed = %v, want 42", m["dL2Rxed"])
	}
	if m["hourStart"] != "2026-08-17T10:05:00Z" {
		t.Errorf("hourStart = %v, want the bucket start", m["hourStart"])
	}
}

// A node that has only just started has raw samples but nothing compacted.
// GetHourlySummary is legitimately empty there, and Get5MinSummary is what
// makes the graph appear before the first hour boundary.
func TestFiveMinFallbackHasDataWhenHourlyDoesNot(t *testing.T) {
	s := newTestStorage(t)

	now := time.Now().UTC()
	var n int64
	for m := 25; m >= 0; m -= 5 {
		n += 50
		insertRaw(t, s, now.Add(-time.Duration(m)*time.Minute), 1, n, n*2)
	}

	if err := s.CompactHourly(); err != nil {
		t.Fatalf("CompactHourly: %v", err)
	}
	hourly, err := s.GetHourlySummary(1, now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("GetHourlySummary: %v", err)
	}
	if len(hourly) != 0 {
		t.Skip("samples happened to straddle an hour boundary; nothing to assert")
	}

	fine, err := s.Get5MinSummary(1, now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("Get5MinSummary: %v", err)
	}
	if len(fine) == 0 {
		t.Fatal("no five-minute buckets either; a freshly started node would show an empty graph")
	}
}
