package main

import (
	"database/sql"
	"fmt"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

// LinkStatsStorage handles persistence of link statistics in SQLite
type LinkStatsStorage struct {
	db *sql.DB
	mu sync.RWMutex
}

// NewLinkStatsStorage creates a new SQLite-backed link stats storage
func NewLinkStatsStorage(dbPath string) (*LinkStatsStorage, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open link stats database: %w", err)
	}

	// Enable WAL mode for better concurrent read/write performance
	if _, err := db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to enable WAL: %w", err)
	}

	s := &LinkStatsStorage{db: db}
	if err := s.createTables(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *LinkStatsStorage) createTables() error {
	schema := `
	CREATE TABLE IF NOT EXISTS link_stats_raw (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME NOT NULL,
		port_num INTEGER NOT NULL,
		l2_digied INTEGER DEFAULT 0,
		l2_heard INTEGER DEFAULT 0,
		l2_rxed INTEGER DEFAULT 0,
		l2_sent INTEGER DEFAULT 0,
		l2_timeouts INTEGER DEFAULT 0,
		rej_rxed INTEGER DEFAULT 0,
		rx_out_of_seq INTEGER DEFAULT 0,
		l2_resequenced INTEGER DEFAULT 0,
		undrun_poll_to INTEGER DEFAULT 0,
		rx_overruns INTEGER DEFAULT 0,
		rx_crc_errors INTEGER DEFAULT 0,
		frmrs_sent INTEGER DEFAULT 0,
		frmrs_received INTEGER DEFAULT 0,
		frames_abandoned INTEGER DEFAULT 0,
		active_tx_pct INTEGER DEFAULT 0,
		active_busy_pct INTEGER DEFAULT 0
	);
	CREATE INDEX IF NOT EXISTS idx_raw_timestamp ON link_stats_raw(timestamp);
	CREATE INDEX IF NOT EXISTS idx_raw_port_timestamp ON link_stats_raw(port_num, timestamp);

	-- Legacy [TARPNstat V2] broadcasts, as seen on the monitor stream.
	--
	-- This is the network-wide interoperable link report: every TARPN node
	-- broadcasts it, including stock ones, so it is the only bilateral link
	-- data available for neighbours that are not running this software.
	-- It is route-level (from LinBPQ's "R R" table), which is a different
	-- view from the per-port L2 counters in link_stats_raw.
	--
	-- direction is 'T' for our own outgoing broadcast and 'R' for one heard
	-- from a neighbour, which is what makes the bilateral comparison possible.
	CREATE TABLE IF NOT EXISTS link_stats_tarpnstat (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME NOT NULL,
		direction TEXT NOT NULL,
		port_num INTEGER NOT NULL,
		callsign TEXT NOT NULL,
		link_up INTEGER DEFAULT 0,
		tx INTEGER DEFAULT 0,
		ret INTEGER DEFAULT 0,
		buf INTEGER DEFAULT 0
	);
	CREATE INDEX IF NOT EXISTS idx_tarpnstat_port_dir_ts
		ON link_stats_tarpnstat(port_num, direction, timestamp);

	CREATE TABLE IF NOT EXISTS link_stats_system (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME NOT NULL,
		uptime_mins INTEGER DEFAULT 0,
		sem_gets INTEGER DEFAULT 0,
		sem_clashes INTEGER DEFAULT 0,
		buffers_max INTEGER DEFAULT 0,
		buffers_cur INTEGER DEFAULT 0,
		buffers_min INTEGER DEFAULT 0,
		buffers_out INTEGER DEFAULT 0,
		buffers_wait INTEGER DEFAULT 0,
		known_nodes INTEGER DEFAULT 0,
		max_nodes INTEGER DEFAULT 0,
		l4_conn_sent INTEGER DEFAULT 0,
		l4_conn_rxed INTEGER DEFAULT 0,
		l4_frames_tx INTEGER DEFAULT 0,
		l4_frames_rx INTEGER DEFAULT 0,
		l4_resent INTEGER DEFAULT 0,
		l4_reseq INTEGER DEFAULT 0,
		l3_relayed INTEGER DEFAULT 0
	);
	CREATE INDEX IF NOT EXISTS idx_system_timestamp ON link_stats_system(timestamp);

	CREATE TABLE IF NOT EXISTS link_stats_hourly (
		hour_start DATETIME NOT NULL,
		port_num INTEGER NOT NULL,
		d_l2_rxed INTEGER DEFAULT 0,
		d_l2_sent INTEGER DEFAULT 0,
		d_l2_timeouts INTEGER DEFAULT 0,
		d_rej_rxed INTEGER DEFAULT 0,
		d_rx_crc_errors INTEGER DEFAULT 0,
		d_frames_abandoned INTEGER DEFAULT 0,
		avg_active_tx_pct REAL DEFAULT 0,
		avg_active_busy_pct REAL DEFAULT 0,
		end_l2_rxed INTEGER DEFAULT 0,
		end_l2_sent INTEGER DEFAULT 0,
		end_l2_timeouts INTEGER DEFAULT 0,
		sample_count INTEGER DEFAULT 0,
		PRIMARY KEY(hour_start, port_num)
	);

	CREATE TABLE IF NOT EXISTS link_stats_daily (
		day_start DATE NOT NULL,
		port_num INTEGER NOT NULL,
		d_l2_rxed INTEGER DEFAULT 0,
		d_l2_sent INTEGER DEFAULT 0,
		d_l2_timeouts INTEGER DEFAULT 0,
		d_rej_rxed INTEGER DEFAULT 0,
		d_rx_crc_errors INTEGER DEFAULT 0,
		d_frames_abandoned INTEGER DEFAULT 0,
		avg_active_tx_pct REAL DEFAULT 0,
		avg_active_busy_pct REAL DEFAULT 0,
		sample_count INTEGER DEFAULT 0,
		PRIMARY KEY(day_start, port_num)
	);

	CREATE TABLE IF NOT EXISTS link_stats_neighbor (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		timestamp DATETIME NOT NULL,
		callsign TEXT NOT NULL,
		reported_port INTEGER NOT NULL,
		rx_port INTEGER NOT NULL,
		l2_rxed INTEGER DEFAULT 0,
		l2_sent INTEGER DEFAULT 0,
		l2_timeouts INTEGER DEFAULT 0,
		rej_rxed INTEGER DEFAULT 0,
		rx_crc_errors INTEGER DEFAULT 0,
		frames_abandoned INTEGER DEFAULT 0,
		active_tx_pct INTEGER DEFAULT 0,
		active_busy_pct INTEGER DEFAULT 0
	);
	CREATE INDEX IF NOT EXISTS idx_neighbor_timestamp ON link_stats_neighbor(timestamp);
	CREATE INDEX IF NOT EXISTS idx_neighbor_call_port ON link_stats_neighbor(callsign, reported_port);
	`
	_, err := s.db.Exec(schema)
	if err != nil {
		return fmt.Errorf("failed to create link stats tables: %w", err)
	}
	return nil
}

// SaveSnapshot stores a complete stats snapshot (system + per-port)
func (s *LinkStatsStorage) SaveSnapshot(snap *LinkStatsSnapshot) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	tx, err := s.db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	ts := snap.Timestamp.UTC().Format(time.RFC3339)

	// Save system stats
	uptimeMins := snap.System.UptimeDays*24*60 + snap.System.UptimeHours*60 + snap.System.UptimeMins
	_, err = tx.Exec(`
		INSERT INTO link_stats_system
		(timestamp, uptime_mins, sem_gets, sem_clashes,
		 buffers_max, buffers_cur, buffers_min, buffers_out, buffers_wait,
		 known_nodes, max_nodes,
		 l4_conn_sent, l4_conn_rxed,
		 l4_frames_tx, l4_frames_rx, l4_resent, l4_reseq,
		 l3_relayed)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		ts, uptimeMins, snap.System.SemGets, snap.System.SemClashes,
		snap.System.BuffersMax, snap.System.BuffersCur, snap.System.BuffersMin,
		snap.System.BuffersOut, snap.System.BuffersWait,
		snap.System.KnownNodes, snap.System.MaxNodes,
		snap.System.L4ConnSent, snap.System.L4ConnRxed,
		snap.System.L4FramesTx, snap.System.L4FramesRx,
		snap.System.L4Resent, snap.System.L4Reseq,
		snap.System.L3Relayed)
	if err != nil {
		return fmt.Errorf("failed to save system stats: %w", err)
	}

	// Save per-port stats
	stmt, err := tx.Prepare(`
		INSERT INTO link_stats_raw
		(timestamp, port_num, l2_digied, l2_heard, l2_rxed, l2_sent,
		 l2_timeouts, rej_rxed, rx_out_of_seq,
		 l2_resequenced, undrun_poll_to,
		 rx_overruns, rx_crc_errors,
		 frmrs_sent, frmrs_received,
		 frames_abandoned, active_tx_pct, active_busy_pct)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
	if err != nil {
		return fmt.Errorf("failed to prepare port stats insert: %w", err)
	}
	defer stmt.Close()

	for _, ps := range snap.Ports {
		_, err = stmt.Exec(ts, ps.PortNum,
			ps.L2Digied, ps.L2Heard, ps.L2Rxed, ps.L2Sent,
			ps.L2Timeouts, ps.REJRxed, ps.RXOutOfSeq,
			ps.L2Resequenced, ps.UndrunPollTo,
			ps.RXOverruns, ps.RXCRCErrors,
			ps.FRMRsSent, ps.FRMRsReceived,
			ps.FramesAbandoned, ps.ActiveTxPct, ps.ActiveBusyPct)
		if err != nil {
			return fmt.Errorf("failed to save port %d stats: %w", ps.PortNum, err)
		}
	}

	return tx.Commit()
}

// GetLatestSnapshot returns the most recent snapshot from the database
func (s *LinkStatsStorage) GetLatestSnapshot() (*LinkStatsSnapshot, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// Get latest system stats
	var snap LinkStatsSnapshot
	var ts string
	var uptimeMins int
	row := s.db.QueryRow(`
		SELECT timestamp, uptime_mins, sem_gets, sem_clashes,
		       buffers_max, buffers_cur, buffers_min, buffers_out, buffers_wait,
		       known_nodes, max_nodes,
		       l4_conn_sent, l4_conn_rxed,
		       l4_frames_tx, l4_frames_rx, l4_resent, l4_reseq,
		       l3_relayed
		FROM link_stats_system ORDER BY timestamp DESC LIMIT 1`)
	err := row.Scan(&ts, &uptimeMins,
		&snap.System.SemGets, &snap.System.SemClashes,
		&snap.System.BuffersMax, &snap.System.BuffersCur, &snap.System.BuffersMin,
		&snap.System.BuffersOut, &snap.System.BuffersWait,
		&snap.System.KnownNodes, &snap.System.MaxNodes,
		&snap.System.L4ConnSent, &snap.System.L4ConnRxed,
		&snap.System.L4FramesTx, &snap.System.L4FramesRx,
		&snap.System.L4Resent, &snap.System.L4Reseq,
		&snap.System.L3Relayed)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to query latest system stats: %w", err)
	}

	snap.Timestamp, _ = time.Parse(time.RFC3339, ts)
	snap.System.UptimeDays = uptimeMins / (24 * 60)
	snap.System.UptimeHours = (uptimeMins % (24 * 60)) / 60
	snap.System.UptimeMins = uptimeMins % 60

	// Get port stats from the same timestamp
	snap.Ports = make(map[int]*PortStats)
	rows, err := s.db.Query(`
		SELECT port_num, l2_digied, l2_heard, l2_rxed, l2_sent,
		       l2_timeouts, rej_rxed, rx_out_of_seq,
		       l2_resequenced, undrun_poll_to,
		       rx_overruns, rx_crc_errors,
		       frmrs_sent, frmrs_received,
		       frames_abandoned, active_tx_pct, active_busy_pct
		FROM link_stats_raw WHERE timestamp = ?`, ts)
	if err != nil {
		return nil, fmt.Errorf("failed to query latest port stats: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var ps PortStats
		err := rows.Scan(&ps.PortNum,
			&ps.L2Digied, &ps.L2Heard, &ps.L2Rxed, &ps.L2Sent,
			&ps.L2Timeouts, &ps.REJRxed, &ps.RXOutOfSeq,
			&ps.L2Resequenced, &ps.UndrunPollTo,
			&ps.RXOverruns, &ps.RXCRCErrors,
			&ps.FRMRsSent, &ps.FRMRsReceived,
			&ps.FramesAbandoned, &ps.ActiveTxPct, &ps.ActiveBusyPct)
		if err != nil {
			return nil, fmt.Errorf("failed to scan port stats: %w", err)
		}
		snap.Ports[ps.PortNum] = &ps
	}

	return &snap, nil
}

// PortHistoryPoint represents a single data point in port history
type PortHistoryPoint struct {
	Timestamp       time.Time `json:"timestamp"`
	L2Rxed          int64     `json:"l2Rxed"`
	L2Sent          int64     `json:"l2Sent"`
	L2Timeouts      int64     `json:"l2Timeouts"`
	REJRxed         int64     `json:"rejRxed"`
	RXCRCErrors     int64     `json:"rxCrcErrors"`
	FramesAbandoned int64     `json:"framesAbandoned"`
	ActiveTxPct     int       `json:"activeTxPct"`
	ActiveBusyPct   int       `json:"activeBusyPct"`
}

// GetPortHistory returns raw stats for a specific port since the given time
func (s *LinkStatsStorage) GetPortHistory(portNum int, since time.Time) ([]PortHistoryPoint, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT timestamp, l2_rxed, l2_sent, l2_timeouts, rej_rxed,
		       rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct
		FROM link_stats_raw
		WHERE port_num = ? AND timestamp >= ?
		ORDER BY timestamp ASC`,
		portNum, since.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query port history: %w", err)
	}
	defer rows.Close()

	var points []PortHistoryPoint
	for rows.Next() {
		var p PortHistoryPoint
		var ts string
		err := rows.Scan(&ts, &p.L2Rxed, &p.L2Sent, &p.L2Timeouts, &p.REJRxed,
			&p.RXCRCErrors, &p.FramesAbandoned, &p.ActiveTxPct, &p.ActiveBusyPct)
		if err != nil {
			return nil, fmt.Errorf("failed to scan port history point: %w", err)
		}
		p.Timestamp, _ = time.Parse(time.RFC3339, ts)
		points = append(points, p)
	}
	return points, nil
}

// HourlySummary represents an hourly compacted data point
type HourlySummary struct {
	HourStart       time.Time `json:"hourStart"`
	PortNum         int       `json:"portNum"`
	DeltaL2Rxed     int64     `json:"dL2Rxed"`
	DeltaL2Sent     int64     `json:"dL2Sent"`
	DeltaL2Timeouts int64     `json:"dL2Timeouts"`
	DeltaREJRxed    int64     `json:"dRejRxed"`
	DeltaCRCErrors  int64     `json:"dRxCrcErrors"`
	DeltaAbandoned  int64     `json:"dFramesAbandoned"`
	AvgTxPct        float64   `json:"avgActiveTxPct"`
	AvgBusyPct      float64   `json:"avgActiveBusyPct"`
	SampleCount     int       `json:"sampleCount"`
}

// GetHourlySummary returns hourly compacted stats for a port
func (s *LinkStatsStorage) GetHourlySummary(portNum int, since time.Time) ([]HourlySummary, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT hour_start, port_num, d_l2_rxed, d_l2_sent, d_l2_timeouts,
		       d_rej_rxed, d_rx_crc_errors, d_frames_abandoned,
		       avg_active_tx_pct, avg_active_busy_pct, sample_count
		FROM link_stats_hourly
		WHERE port_num = ? AND hour_start >= ?
		ORDER BY hour_start ASC`,
		portNum, since.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query hourly summary: %w", err)
	}
	defer rows.Close()

	var summaries []HourlySummary
	for rows.Next() {
		var h HourlySummary
		var ts string
		err := rows.Scan(&ts, &h.PortNum, &h.DeltaL2Rxed, &h.DeltaL2Sent, &h.DeltaL2Timeouts,
			&h.DeltaREJRxed, &h.DeltaCRCErrors, &h.DeltaAbandoned,
			&h.AvgTxPct, &h.AvgBusyPct, &h.SampleCount)
		if err != nil {
			return nil, fmt.Errorf("failed to scan hourly summary: %w", err)
		}
		h.HourStart, _ = time.Parse(time.RFC3339, ts)
		summaries = append(summaries, h)
	}
	return summaries, nil
}

// GetHourlyPortNumbers returns distinct port numbers that have hourly data since the given time
func (s *LinkStatsStorage) GetHourlyPortNumbers(since time.Time) ([]int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT DISTINCT port_num FROM link_stats_hourly
		WHERE hour_start >= ? ORDER BY port_num ASC`,
		since.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query hourly port numbers: %w", err)
	}
	defer rows.Close()

	var ports []int
	for rows.Next() {
		var pn int
		if err := rows.Scan(&pn); err != nil {
			return nil, fmt.Errorf("failed to scan port number: %w", err)
		}
		ports = append(ports, pn)
	}
	return ports, nil
}

// GetHourlySummaryRange returns hourly compacted stats for a port within a time range [since, until)
func (s *LinkStatsStorage) GetHourlySummaryRange(portNum int, since, until time.Time) ([]HourlySummary, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT hour_start, port_num, d_l2_rxed, d_l2_sent, d_l2_timeouts,
		       d_rej_rxed, d_rx_crc_errors, d_frames_abandoned,
		       avg_active_tx_pct, avg_active_busy_pct, sample_count
		FROM link_stats_hourly
		WHERE port_num = ? AND hour_start >= ? AND hour_start < ?
		ORDER BY hour_start ASC`,
		portNum, since.UTC().Format(time.RFC3339), until.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query hourly summary range: %w", err)
	}
	defer rows.Close()

	var summaries []HourlySummary
	for rows.Next() {
		var h HourlySummary
		var ts string
		err := rows.Scan(&ts, &h.PortNum, &h.DeltaL2Rxed, &h.DeltaL2Sent, &h.DeltaL2Timeouts,
			&h.DeltaREJRxed, &h.DeltaCRCErrors, &h.DeltaAbandoned,
			&h.AvgTxPct, &h.AvgBusyPct, &h.SampleCount)
		if err != nil {
			return nil, fmt.Errorf("failed to scan hourly summary: %w", err)
		}
		h.HourStart, _ = time.Parse(time.RFC3339, ts)
		summaries = append(summaries, h)
	}
	return summaries, nil
}

// GetHourlyPortNumbersRange returns distinct port numbers that have hourly data in [since, until)
func (s *LinkStatsStorage) GetHourlyPortNumbersRange(since, until time.Time) ([]int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT DISTINCT port_num FROM link_stats_hourly
		WHERE hour_start >= ? AND hour_start < ? ORDER BY port_num ASC`,
		since.UTC().Format(time.RFC3339), until.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query hourly port numbers range: %w", err)
	}
	defer rows.Close()

	var ports []int
	for rows.Next() {
		var pn int
		if err := rows.Scan(&pn); err != nil {
			return nil, fmt.Errorf("failed to scan port number: %w", err)
		}
		ports = append(ports, pn)
	}
	return ports, nil
}

// GetRawPortNumbers returns distinct port numbers that have raw data since the given time
func (s *LinkStatsStorage) GetRawPortNumbers(since time.Time) ([]int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT DISTINCT port_num FROM link_stats_raw
		WHERE timestamp >= ? ORDER BY port_num ASC`,
		since.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query raw port numbers: %w", err)
	}
	defer rows.Close()

	var ports []int
	for rows.Next() {
		var pn int
		if err := rows.Scan(&pn); err != nil {
			return nil, fmt.Errorf("failed to scan port number: %w", err)
		}
		ports = append(ports, pn)
	}
	return ports, nil
}

// GetRawPortNumbersRange returns distinct port numbers that have raw data in [since, until)
func (s *LinkStatsStorage) GetRawPortNumbersRange(since, until time.Time) ([]int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT DISTINCT port_num FROM link_stats_raw
		WHERE timestamp >= ? AND timestamp < ? ORDER BY port_num ASC`,
		since.UTC().Format(time.RFC3339), until.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query raw port numbers range: %w", err)
	}
	defer rows.Close()

	var ports []int
	for rows.Next() {
		var pn int
		if err := rows.Scan(&pn); err != nil {
			return nil, fmt.Errorf("failed to scan port number: %w", err)
		}
		ports = append(ports, pn)
	}
	return ports, nil
}

// FiveMinSummary represents a 5-minute aggregated interval from raw data
type FiveMinSummary struct {
	BucketStart     time.Time
	PortNum         int
	DeltaL2Rxed     int64
	DeltaL2Sent     int64
	DeltaL2Timeouts int64
	DeltaREJRxed    int64
	DeltaCRCErrors  int64
	DeltaAbandoned  int64
	AvgTxPct        float64
	AvgBusyPct      float64
	SampleCount     int
}

// Get5MinSummary computes 5-minute interval summaries from raw data for a port.
// Unlike hourly compaction (stored), these are computed on-the-fly from raw snapshots.
func (s *LinkStatsStorage) Get5MinSummary(portNum int, since time.Time) ([]FiveMinSummary, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT timestamp, l2_rxed, l2_sent, l2_timeouts, rej_rxed,
		       rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct
		FROM link_stats_raw
		WHERE port_num = ? AND timestamp >= ?
		ORDER BY timestamp ASC`,
		portNum, since.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query raw data for 5-min summary: %w", err)
	}
	defer rows.Close()

	// Collect raw points grouped into 5-minute buckets
	type rawPoint struct {
		rxed, sent, timeouts, rej, crc, abandoned int64
		txPct, busyPct                            int
	}

	buckets := make(map[time.Time][]rawPoint)
	var bucketOrder []time.Time

	for rows.Next() {
		var ts string
		var p rawPoint
		err := rows.Scan(&ts, &p.rxed, &p.sent, &p.timeouts, &p.rej,
			&p.crc, &p.abandoned, &p.txPct, &p.busyPct)
		if err != nil {
			return nil, fmt.Errorf("failed to scan raw data: %w", err)
		}
		t, _ := time.Parse(time.RFC3339, ts)
		// Truncate to 5-minute bucket
		bucket := t.Truncate(5 * time.Minute)
		if _, exists := buckets[bucket]; !exists {
			bucketOrder = append(bucketOrder, bucket)
		}
		buckets[bucket] = append(buckets[bucket], p)
	}

	// Compute deltas for each bucket
	var summaries []FiveMinSummary
	for _, bucket := range bucketOrder {
		points := buckets[bucket]
		if len(points) < 2 {
			// Need at least 2 points to compute a delta
			// Use single point with zero deltas but include pct averages
			if len(points) == 1 {
				summaries = append(summaries, FiveMinSummary{
					BucketStart: bucket,
					PortNum:     portNum,
					AvgTxPct:    float64(points[0].txPct),
					AvgBusyPct:  float64(points[0].busyPct),
					SampleCount: 1,
				})
			}
			continue
		}

		first := points[0]
		last := points[len(points)-1]

		var txPctSum, busyPctSum float64
		for _, p := range points {
			txPctSum += float64(p.txPct)
			busyPctSum += float64(p.busyPct)
		}

		summaries = append(summaries, FiveMinSummary{
			BucketStart:     bucket,
			PortNum:         portNum,
			DeltaL2Rxed:     safeDelta(first.rxed, last.rxed),
			DeltaL2Sent:     safeDelta(first.sent, last.sent),
			DeltaL2Timeouts: safeDelta(first.timeouts, last.timeouts),
			DeltaREJRxed:    safeDelta(first.rej, last.rej),
			DeltaCRCErrors:  safeDelta(first.crc, last.crc),
			DeltaAbandoned:  safeDelta(first.abandoned, last.abandoned),
			AvgTxPct:        txPctSum / float64(len(points)),
			AvgBusyPct:      busyPctSum / float64(len(points)),
			SampleCount:     len(points),
		})
	}

	return summaries, nil
}

// Get5MinSummaryRange computes 5-minute interval summaries from raw data in [since, until).
func (s *LinkStatsStorage) Get5MinSummaryRange(portNum int, since, until time.Time) ([]FiveMinSummary, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT timestamp, l2_rxed, l2_sent, l2_timeouts, rej_rxed,
		       rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct
		FROM link_stats_raw
		WHERE port_num = ? AND timestamp >= ? AND timestamp < ?
		ORDER BY timestamp ASC`,
		portNum, since.UTC().Format(time.RFC3339), until.UTC().Format(time.RFC3339))
	if err != nil {
		return nil, fmt.Errorf("failed to query raw data for 5-min summary range: %w", err)
	}
	defer rows.Close()

	type rawPoint struct {
		rxed, sent, timeouts, rej, crc, abandoned int64
		txPct, busyPct                            int
	}

	buckets := make(map[time.Time][]rawPoint)
	var bucketOrder []time.Time

	for rows.Next() {
		var ts string
		var p rawPoint
		err := rows.Scan(&ts, &p.rxed, &p.sent, &p.timeouts, &p.rej,
			&p.crc, &p.abandoned, &p.txPct, &p.busyPct)
		if err != nil {
			return nil, fmt.Errorf("failed to scan raw data: %w", err)
		}
		t, _ := time.Parse(time.RFC3339, ts)
		bucket := t.Truncate(5 * time.Minute)
		if _, exists := buckets[bucket]; !exists {
			bucketOrder = append(bucketOrder, bucket)
		}
		buckets[bucket] = append(buckets[bucket], p)
	}

	var summaries []FiveMinSummary
	for _, bucket := range bucketOrder {
		points := buckets[bucket]
		if len(points) < 2 {
			if len(points) == 1 {
				summaries = append(summaries, FiveMinSummary{
					BucketStart: bucket,
					PortNum:     portNum,
					AvgTxPct:    float64(points[0].txPct),
					AvgBusyPct:  float64(points[0].busyPct),
					SampleCount: 1,
				})
			}
			continue
		}

		first := points[0]
		last := points[len(points)-1]

		var txPctSum, busyPctSum float64
		for _, p := range points {
			txPctSum += float64(p.txPct)
			busyPctSum += float64(p.busyPct)
		}

		summaries = append(summaries, FiveMinSummary{
			BucketStart:     bucket,
			PortNum:         portNum,
			DeltaL2Rxed:     safeDelta(first.rxed, last.rxed),
			DeltaL2Sent:     safeDelta(first.sent, last.sent),
			DeltaL2Timeouts: safeDelta(first.timeouts, last.timeouts),
			DeltaREJRxed:    safeDelta(first.rej, last.rej),
			DeltaCRCErrors:  safeDelta(first.crc, last.crc),
			DeltaAbandoned:  safeDelta(first.abandoned, last.abandoned),
			AvgTxPct:        txPctSum / float64(len(points)),
			AvgBusyPct:      busyPctSum / float64(len(points)),
			SampleCount:     len(points),
		})
	}

	return summaries, nil
}

// CompactHourly compacts raw data into hourly summaries.
// Calculates deltas (max - min within hour), handles counter resets.
func (s *LinkStatsStorage) CompactHourly() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Find the latest hour we've compacted
	var lastCompacted sql.NullString
	s.db.QueryRow(`SELECT MAX(hour_start) FROM link_stats_hourly`).Scan(&lastCompacted)

	// Start from 2 hours ago (ensure the hour is complete) or from beginning
	cutoff := time.Now().UTC().Truncate(time.Hour).Add(-time.Hour)
	startFrom := time.Time{}
	if lastCompacted.Valid {
		startFrom, _ = time.Parse(time.RFC3339, lastCompacted.String)
		// Re-compact the last hour in case it was incomplete
	}

	// Get distinct hours and ports that need compaction
	rows, err := s.db.Query(`
		SELECT DISTINCT
			strftime('%Y-%m-%dT%H:00:00Z', timestamp) as hour_start,
			port_num
		FROM link_stats_raw
		WHERE timestamp >= ? AND timestamp < ?
		ORDER BY hour_start`, startFrom.UTC().Format(time.RFC3339), cutoff.UTC().Format(time.RFC3339))
	if err != nil {
		return fmt.Errorf("failed to find hours to compact: %w", err)
	}
	defer rows.Close()

	type hourPort struct {
		hour    string
		portNum int
	}
	var toCompact []hourPort
	for rows.Next() {
		var hp hourPort
		if err := rows.Scan(&hp.hour, &hp.portNum); err != nil {
			continue
		}
		toCompact = append(toCompact, hp)
	}
	rows.Close()

	for _, hp := range toCompact {
		hourEnd, _ := time.Parse(time.RFC3339, hp.hour)
		hourEnd = hourEnd.Add(time.Hour)

		// Fetch ordered raw points for this hour+port to compute sequential deltas.
		// Using safeDelta() between consecutive points correctly handles counter
		// rollovers from LinBPQ reboots (where counters reset to 0 mid-hour).
		// The previous MAX-MIN approach gave incorrect results in that case.
		pointRows, err := s.db.Query(`
			SELECT l2_rxed, l2_sent, l2_timeouts, rej_rxed,
			       rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct
			FROM link_stats_raw
			WHERE port_num = ? AND timestamp >= ? AND timestamp < ?
			ORDER BY timestamp ASC`,
			hp.portNum, hp.hour, hourEnd.UTC().Format(time.RFC3339))
		if err != nil {
			statsLog.Warnw("Failed to compact hour", "hour", hp.hour, "port", hp.portNum, "error", err)
			continue
		}

		type compactPoint struct {
			rxed, sent, timeouts, rej, crc, abandoned int64
			txPct, busyPct                            int
		}
		var points []compactPoint
		for pointRows.Next() {
			var p compactPoint
			if err := pointRows.Scan(&p.rxed, &p.sent, &p.timeouts, &p.rej,
				&p.crc, &p.abandoned, &p.txPct, &p.busyPct); err != nil {
				continue
			}
			points = append(points, p)
		}
		pointRows.Close()

		if len(points) == 0 {
			continue
		}

		// Sum sequential deltas using safeDelta to handle counter rollovers
		var deltaRxed, deltaSent, deltaTimeouts, deltaRej, deltaCRC, deltaAbandoned int64
		var txPctSum, busyPctSum float64
		for i, p := range points {
			txPctSum += float64(p.txPct)
			busyPctSum += float64(p.busyPct)
			if i > 0 {
				prev := points[i-1]
				deltaRxed += safeDelta(prev.rxed, p.rxed)
				deltaSent += safeDelta(prev.sent, p.sent)
				deltaTimeouts += safeDelta(prev.timeouts, p.timeouts)
				deltaRej += safeDelta(prev.rej, p.rej)
				deltaCRC += safeDelta(prev.crc, p.crc)
				deltaAbandoned += safeDelta(prev.abandoned, p.abandoned)
			}
		}

		sampleCount := len(points)
		avgTx := txPctSum / float64(sampleCount)
		avgBusy := busyPctSum / float64(sampleCount)

		// End-of-hour snapshot values (last point in the hour)
		last := points[len(points)-1]
		endRxed := last.rxed
		endSent := last.sent
		endTimeouts := last.timeouts

		_, err = s.db.Exec(`
			INSERT OR REPLACE INTO link_stats_hourly
			(hour_start, port_num, d_l2_rxed, d_l2_sent, d_l2_timeouts,
			 d_rej_rxed, d_rx_crc_errors, d_frames_abandoned,
			 avg_active_tx_pct, avg_active_busy_pct,
			 end_l2_rxed, end_l2_sent, end_l2_timeouts,
			 sample_count)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			hp.hour, hp.portNum,
			deltaRxed, deltaSent, deltaTimeouts,
			deltaRej, deltaCRC, deltaAbandoned,
			avgTx, avgBusy,
			endRxed, endSent, endTimeouts,
			sampleCount)
		if err != nil {
			statsLog.Warnw("Failed to insert hourly summary", "hour", hp.hour, "port", hp.portNum, "error", err)
		}
	}

	return nil
}

// CompactDaily compacts hourly data into daily summaries
func (s *LinkStatsStorage) CompactDaily() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Find the latest day we've compacted
	var lastCompacted sql.NullString
	s.db.QueryRow(`SELECT MAX(day_start) FROM link_stats_daily`).Scan(&lastCompacted)

	// Only compact complete days (up to yesterday)
	cutoff := time.Now().UTC().Truncate(24 * time.Hour)
	startFrom := time.Time{}
	if lastCompacted.Valid {
		startFrom, _ = time.Parse("2006-01-02", lastCompacted.String)
	}

	rows, err := s.db.Query(`
		SELECT DISTINCT
			strftime('%Y-%m-%d', hour_start) as day_start,
			port_num
		FROM link_stats_hourly
		WHERE hour_start >= ? AND hour_start < ?
		ORDER BY day_start`, startFrom.Format(time.RFC3339), cutoff.Format(time.RFC3339))
	if err != nil {
		return fmt.Errorf("failed to find days to compact: %w", err)
	}
	defer rows.Close()

	type dayPort struct {
		day     string
		portNum int
	}
	var toCompact []dayPort
	for rows.Next() {
		var dp dayPort
		if err := rows.Scan(&dp.day, &dp.portNum); err != nil {
			continue
		}
		toCompact = append(toCompact, dp)
	}
	rows.Close()

	for _, dp := range toCompact {
		dayEnd, _ := time.Parse("2006-01-02", dp.day)
		dayEnd = dayEnd.Add(24 * time.Hour)

		var sumRxed, sumSent, sumTimeouts, sumRej, sumCRC, sumAbandoned int64
		var avgTx, avgBusy float64
		var sampleCount int

		err := s.db.QueryRow(`
			SELECT
				SUM(d_l2_rxed), SUM(d_l2_sent), SUM(d_l2_timeouts),
				SUM(d_rej_rxed), SUM(d_rx_crc_errors), SUM(d_frames_abandoned),
				AVG(avg_active_tx_pct), AVG(avg_active_busy_pct),
				SUM(sample_count)
			FROM link_stats_hourly
			WHERE port_num = ? AND hour_start >= ? AND hour_start < ?`,
			dp.portNum, dp.day, dayEnd.UTC().Format(time.RFC3339)).Scan(
			&sumRxed, &sumSent, &sumTimeouts,
			&sumRej, &sumCRC, &sumAbandoned,
			&avgTx, &avgBusy, &sampleCount)
		if err != nil {
			statsLog.Warnw("Failed to compact day", "day", dp.day, "port", dp.portNum, "error", err)
			continue
		}

		_, err = s.db.Exec(`
			INSERT OR REPLACE INTO link_stats_daily
			(day_start, port_num, d_l2_rxed, d_l2_sent, d_l2_timeouts,
			 d_rej_rxed, d_rx_crc_errors, d_frames_abandoned,
			 avg_active_tx_pct, avg_active_busy_pct, sample_count)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			dp.day, dp.portNum,
			sumRxed, sumSent, sumTimeouts,
			sumRej, sumCRC, sumAbandoned,
			avgTx, avgBusy, sampleCount)
		if err != nil {
			statsLog.Warnw("Failed to insert daily summary", "day", dp.day, "port", dp.portNum, "error", err)
		}
	}

	return nil
}

// PurgeOldRaw deletes raw data older than the specified duration
func (s *LinkStatsStorage) PurgeOldRaw(retention time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	cutoff := time.Now().UTC().Add(-retention).Format(time.RFC3339)

	result, err := s.db.Exec(`DELETE FROM link_stats_raw WHERE timestamp < ?`, cutoff)
	if err != nil {
		return fmt.Errorf("failed to purge old raw stats: %w", err)
	}

	affected, _ := result.RowsAffected()
	if affected > 0 {
		statsLog.Infow("Purged old raw stats", "deleted", affected)
	}

	// Also purge old system stats
	result, err = s.db.Exec(`DELETE FROM link_stats_system WHERE timestamp < ?`, cutoff)
	if err != nil {
		return fmt.Errorf("failed to purge old system stats: %w", err)
	}

	affected, _ = result.RowsAffected()
	if affected > 0 {
		statsLog.Infow("Purged old system stats", "deleted", affected)
	}

	return nil
}

// SaveNeighborCQ stores a decoded CQ link stats broadcast from a neighbor node.
// rxPort is the local port that received the CQ frame.
// The CQ message contains absolute counters; delta computation happens at query time.
func (s *LinkStatsStorage) SaveNeighborCQ(rxPort int, msg *LinkStatCQMessage) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	ts := time.Now().UTC().Format(time.RFC3339)
	_, err := s.db.Exec(`
		INSERT INTO link_stats_neighbor
		(timestamp, callsign, reported_port, rx_port,
		 l2_rxed, l2_sent, l2_timeouts, rej_rxed,
		 rx_crc_errors, frames_abandoned, active_tx_pct, active_busy_pct)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		ts, msg.Callsign, msg.PortNum, rxPort,
		msg.L2Rxed, msg.L2Sent, msg.L2Timeouts, msg.REJRxed,
		msg.RXCRCErrors, msg.Abandoned, msg.ActiveTxPct, msg.ActiveBusyPct)
	if err != nil {
		return fmt.Errorf("failed to save neighbor CQ: %w", err)
	}
	return nil
}

// SaveTARPNStat stores a [TARPNstat V2] broadcast seen on the monitor stream.
//
// direction is the monitor's R/T flag: 'T' is our own broadcast going out,
// 'R' is one heard from a neighbour. Storing both is what lets a consumer show
// each link from both ends, which is the whole point of TARPNstat and what the
// legacy rx_tarpnstatapp wrote to tarpn_home_linkquality.dat.
func (s *LinkStatsStorage) SaveTARPNStat(direction string, portNum int, stat *TARPNStat) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	linkUp := 0
	if stat.LinkUp {
		linkUp = 1
	}

	ts := time.Now().UTC().Format(time.RFC3339)
	_, err := s.db.Exec(`
		INSERT INTO link_stats_tarpnstat
		(timestamp, direction, port_num, callsign, link_up, tx, ret, buf)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		ts, direction, portNum, stat.Callsign, linkUp, stat.Tx, stat.Ret, stat.Buf)
	if err != nil {
		return fmt.Errorf("failed to save TARPNstat: %w", err)
	}
	return nil
}

// PurgeOldTARPNStat drops TARPNstat rows older than retention. Broadcasts
// arrive every 15 minutes per port, so this table grows steadily and only the
// recent window is of any use.
func (s *LinkStatsStorage) PurgeOldTARPNStat(retention time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	cutoff := time.Now().UTC().Add(-retention).Format(time.RFC3339)
	_, err := s.db.Exec(`DELETE FROM link_stats_tarpnstat WHERE timestamp < ?`, cutoff)
	if err != nil {
		return fmt.Errorf("failed to purge old TARPNstat rows: %w", err)
	}
	return nil
}

// Close closes the database connection
func (s *LinkStatsStorage) Close() error {
	return s.db.Close()
}
