package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"
)

// LinkStatsCollectorConfig holds configuration for the stats collector
type LinkStatsCollectorConfig struct {
	Hostname     string
	Port         int
	Callsign     string
	Password     string
	PollInterval time.Duration
}

// LinkStatsCollector manages a telnet connection to LinBPQ for periodic S command polling
type LinkStatsCollector struct {
	config  LinkStatsCollectorConfig
	storage *LinkStatsStorage

	// Latest snapshot for WebSocket clients to request on connect
	latestMu   sync.RWMutex
	latestSnap *LinkStatsSnapshot

	// Broadcast function — set after WebSocket server is initialized
	broadcastFn func(snap *LinkStatsSnapshot)

	// Metrics update function
	metricsUpdateFn func(snap *LinkStatsSnapshot)
}

// NewLinkStatsCollector creates a new stats collector
func NewLinkStatsCollector(config LinkStatsCollectorConfig, storage *LinkStatsStorage) *LinkStatsCollector {
	return &LinkStatsCollector{
		config:  config,
		storage: storage,
	}
}

// SetBroadcastFunc sets the function called to broadcast stats to WebSocket clients
func (c *LinkStatsCollector) SetBroadcastFunc(fn func(snap *LinkStatsSnapshot)) {
	c.broadcastFn = fn
}

// SetMetricsUpdateFunc sets the function called to update Prometheus metrics
func (c *LinkStatsCollector) SetMetricsUpdateFunc(fn func(snap *LinkStatsSnapshot)) {
	c.metricsUpdateFn = fn
}

// GetLatestSnapshot returns the most recent stats snapshot
func (c *LinkStatsCollector) GetLatestSnapshot() *LinkStatsSnapshot {
	c.latestMu.RLock()
	defer c.latestMu.RUnlock()
	return c.latestSnap
}

// Run starts the collector loop. It connects to LinBPQ, authenticates, and
// periodically runs the S command. Reconnects on failure with exponential backoff.
func (c *LinkStatsCollector) Run(ctx context.Context) {
	statsLog.Infow("Starting link stats collector",
		"host", c.config.Hostname,
		"port", c.config.Port,
		"interval", c.config.PollInterval)

	// Start compaction goroutine
	go c.runCompaction(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		err := c.connectAndPoll(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return // Context cancelled, exit cleanly
			}
			statsLog.Warnw("Stats connection lost, will reconnect", "error", err)
		}

		// Backoff before reconnecting
		select {
		case <-ctx.Done():
			return
		case <-time.After(5 * time.Second):
		}
	}
}

// connectAndPoll establishes a connection and polls until an error occurs
func (c *LinkStatsCollector) connectAndPoll(ctx context.Context) error {
	// Connect with retry
	conn, err := c.connectWithRetry(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()

	// Create telnet wrapper
	tc, err := NewTelnetConn(conn, 2*time.Second, statsLog)
	if err != nil {
		return fmt.Errorf("telnet negotiation failed: %w", err)
	}

	// Authenticate using standard telnet auth (port 8010 uses prompted auth)
	_, err = tc.Authenticate(c.config.Callsign, c.config.Password, 10*time.Second)
	if err != nil {
		return fmt.Errorf("authentication failed: %w", err)
	}

	statsLog.Infow("Stats collector connected and authenticated")

	// No CR or drain needed here — the S command itself produces output
	// ending with the node prompt. Sending a CR would create a stale prompt
	// that interferes with the first S poll.

	// Poll loop
	ticker := time.NewTicker(c.config.PollInterval)
	defer ticker.Stop()

	// CQ broadcast ticker (every 10 minutes)
	cqTicker := time.NewTicker(10 * time.Minute)
	defer cqTicker.Stop()

	// Daily bulletin ticker (check every hour, send once per day).
	// Posts within ~1 hour after local midnight when the previous day's
	// data bucket is complete. Initialize to today so we don't immediately
	// post on startup — the bulletin fires on the first tick after midnight.
	bulletinTicker := time.NewTicker(1 * time.Hour)
	defer bulletinTicker.Stop()
	lastBulletinDay := time.Now().YearDay()

	// Do an immediate first poll
	if err := c.poll(tc); err != nil {
		return fmt.Errorf("initial poll failed: %w", err)
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := c.poll(tc); err != nil {
				return fmt.Errorf("poll failed: %w", err)
			}
		case <-cqTicker.C:
			c.sendCQBroadcasts()
		case <-bulletinTicker.C:
			today := time.Now().YearDay()
			if today != lastBulletinDay {
				c.sendDailyBulletin()
				lastBulletinDay = today
			}
		}
	}
}

// connectWithRetry connects to LinBPQ with exponential backoff
func (c *LinkStatsCollector) connectWithRetry(ctx context.Context) (net.Conn, error) {
	backoff := initialBackoff
	addr := fmt.Sprintf("%s:%d", c.config.Hostname, c.config.Port)

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
		if err == nil {
			statsLog.Infow("Connected to stats port", "addr", addr)
			return conn, nil
		}

		statsLog.Warnw("Stats connection failed, retrying", "error", err, "backoff", backoff)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(backoff):
		}

		backoff *= 2
		if backoff > maxBackoff {
			backoff = maxBackoff
		}
	}
}

// promptPredicate detects the LinBPQ node prompt.
// The prompt format is either "CALLSIGN>" or "ALIAS:CALLSIGN}" where
// ALIAS can be up to 6 chars and CALLSIGN up to 9 chars (e.g. "MIKE:WA2M-2}").
// Max realistic length is ~18 chars (6 + 1 + 9 + 1 suffix + SSID).
func promptPredicate(line string) bool {
	trimmed := strings.TrimSpace(line)
	if strings.HasSuffix(trimmed, ">") || strings.HasSuffix(trimmed, "}") {
		parts := strings.Fields(trimmed)
		if len(parts) > 0 {
			last := parts[len(parts)-1]
			return len(last) <= 20 && (strings.HasSuffix(last, ">") || strings.HasSuffix(last, "}"))
		}
	}
	return false
}

// poll sends the S command and parses the response
func (c *LinkStatsCollector) poll(tc *TelnetConn) error {
	// Send S command
	statsLog.Debugw("Sending S command")
	if err := tc.WriteString("S"); err != nil {
		return fmt.Errorf("failed to send S command: %w", err)
	}

	// Read response until we see the node prompt (callsign followed by > or })
	pollStart := time.Now()
	lines, found, err := tc.ReadUntil(promptPredicate, 30*time.Second)

	statsLog.Debugw("S command response",
		"lines", lines,
		"found", found,
		"error", err,
		"lineCount", len(lines),
		"elapsed", time.Since(pollStart).Round(time.Millisecond))

	if err != nil {
		return fmt.Errorf("error reading S command response: %w", err)
	}
	if !found {
		return fmt.Errorf("timeout waiting for S command response")
	}

	// Parse the response (exclude the prompt line)
	if len(lines) > 1 {
		lines = lines[:len(lines)-1]
	}

	snap, err := ParseSCommandOutput(lines)
	if err != nil {
		return fmt.Errorf("failed to parse S command output: %w", err)
	}

	statsLog.Debugw("Parsed stats snapshot",
		"ports", len(snap.Ports),
		"uptime", fmt.Sprintf("%dd%dh%dm", snap.System.UptimeDays, snap.System.UptimeHours, snap.System.UptimeMins),
		"buffers", fmt.Sprintf("%d/%d", snap.System.BuffersCur, snap.System.BuffersMax))

	// Store in database
	if c.storage != nil {
		if err := c.storage.SaveSnapshot(snap); err != nil {
			statsLog.Errorw("Failed to save snapshot", "error", err)
		}
	}

	// Update latest snapshot
	c.latestMu.Lock()
	c.latestSnap = snap
	c.latestMu.Unlock()

	// Broadcast to WebSocket clients
	if c.broadcastFn != nil {
		c.broadcastFn(snap)
	}

	// Update Prometheus metrics
	if c.metricsUpdateFn != nil {
		c.metricsUpdateFn(snap)
	}

	return nil
}

// sendCQBroadcasts opens a short-lived telnet connection and sends CQ link stats
// for each RF port, targeting each port with "listen <port>" before the CQ command.
// This matches the behavior of TARPN's send-routes-via-cq.c.
func (c *LinkStatsCollector) sendCQBroadcasts() {
	c.latestMu.RLock()
	snap := c.latestSnap
	c.latestMu.RUnlock()

	if snap == nil {
		statsLog.Debugw("No stats snapshot yet, skipping CQ broadcast")
		return
	}

	// Collect RF ports (skip port 32 = NetROM virtual port)
	var rfPorts []*PortStats
	for _, ps := range snap.Ports {
		if ps.PortNum != 32 {
			rfPorts = append(rfPorts, ps)
		}
	}
	if len(rfPorts) == 0 {
		return
	}

	// Open a separate short-lived telnet connection for CQ sending
	addr := fmt.Sprintf("%s:%d", c.config.Hostname, c.config.Port)
	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		statsLog.Warnw("CQ broadcast: failed to connect", "error", err)
		return
	}
	defer conn.Close()

	tc, err := NewTelnetConn(conn, 2*time.Second, statsLog)
	if err != nil {
		statsLog.Warnw("CQ broadcast: telnet negotiation failed", "error", err)
		return
	}

	_, err = tc.Authenticate(c.config.Callsign, c.config.Password, 10*time.Second)
	if err != nil {
		statsLog.Warnw("CQ broadcast: auth failed", "error", err)
		return
	}

	// For each RF port: listen <port>, then CQ <message>
	for _, ps := range rfPorts {
		// Target this specific port
		listenCmd := fmt.Sprintf("listen %d", ps.PortNum)
		if err := tc.WriteString(listenCmd); err != nil {
			statsLog.Warnw("CQ broadcast: failed to send listen", "port", ps.PortNum, "error", err)
			return
		}
		// Drain listen response
		tc.ReadUntil(promptPredicate, 5*time.Second)

		// Send CQ with encoded stats
		msg := EncodeCQ(c.config.Callsign, ps)
		if err := tc.WriteString("CQ " + msg); err != nil {
			statsLog.Warnw("CQ broadcast: failed to send CQ", "port", ps.PortNum, "error", err)
			return
		}
		// Drain CQ response
		tc.ReadUntil(promptPredicate, 5*time.Second)

		statsLog.Debugw("Sent CQ broadcast", "port", ps.PortNum, "len", len(msg))
	}

	statsLog.Infow("CQ broadcasts complete", "ports", len(rfPorts))
}

// clampU16 clamps an int64 to uint16 range
func clampU16(v int64) uint16 {
	if v > 65535 {
		return 65535
	}
	if v < 0 {
		return 0
	}
	return uint16(v)
}

// clampU8 clamps an int64 to uint8 range
func clampU8(v int64) uint8 {
	if v > 255 {
		return 255
	}
	if v < 0 {
		return 0
	}
	return uint8(v)
}

// getSystemStats returns BulletinSystemStats from the latest snapshot
func (c *LinkStatsCollector) getSystemStats() BulletinSystemStats {
	snap := c.GetLatestSnapshot()
	if snap == nil {
		return BulletinSystemStats{}
	}
	s := snap.System
	return BulletinSystemStats{
		UptimeMins: int64(s.UptimeDays*24*60 + s.UptimeHours*60 + s.UptimeMins),
		BuffersCur: int64(s.BuffersCur),
		KnownNodes: int64(s.KnownNodes),
		L4FramesTx: s.L4FramesTx,
		L4FramesRx: s.L4FramesRx,
		L4Resent:   s.L4Resent,
		L3Relayed:  s.L3Relayed,
	}
}

// sendDailyBulletin assembles stats for the previous calendar day (00:00-23:59 UTC)
// and posts two BBS bulletins: hourly (compact) and 5-minute (detailed).
func (c *LinkStatsCollector) sendDailyBulletin() {
	if c.storage == nil {
		return
	}

	// Previous calendar day in LOCAL time: midnight to midnight.
	// Using local time ensures the bulletin covers "yesterday" as the
	// operator experiences it, not UTC yesterday (which may have no data
	// for US-based operators who started their node in the evening).
	now := time.Now()
	dayStart := time.Date(now.Year(), now.Month(), now.Day()-1, 0, 0, 0, 0, now.Location())
	dayEnd := dayStart.Add(24 * time.Hour)
	sys := c.getSystemStats()

	statsLog.Infow("Preparing daily bulletin",
		"dayStart", dayStart.Format(time.RFC3339),
		"dayEnd", dayEnd.Format(time.RFC3339))

	// Bulletin 1: Hourly intervals from compacted data (LS1H)
	c.sendHourlyBulletin(dayStart, dayEnd, sys)

	// Delay between bulletins to avoid LinBPQ rejecting rapid connections
	time.Sleep(5 * time.Second)

	// Bulletin 2: 15-minute intervals from raw data (LS15M)
	c.send15MinBulletin(dayStart, dayEnd, sys)

	time.Sleep(5 * time.Second)

	// Bulletin 3: 5-minute intervals from raw data (LS5M)
	c.send5MinBulletin(dayStart, dayEnd, sys)

	time.Sleep(5 * time.Second)

	// Bulletin 4: Per-link 5-minute intervals (LLS5M × N ports)
	c.sendPerLinkBulletins(dayStart, dayEnd, sys)
}

// sendHourlyBulletin sends a bulletin with hourly interval summaries for [dayStart, dayEnd).
func (c *LinkStatsCollector) sendHourlyBulletin(dayStart, dayEnd time.Time, sys BulletinSystemStats) {
	portNums, err := c.storage.GetHourlyPortNumbersRange(dayStart, dayEnd)
	if err != nil || len(portNums) == 0 {
		statsLog.Warnw("Hourly bulletin: no data available", "error", err)
		return
	}

	ports := make(map[int][]BulletinInterval)
	for _, pn := range portNums {
		summaries, err := c.storage.GetHourlySummaryRange(pn, dayStart, dayEnd)
		if err != nil {
			statsLog.Warnw("Hourly bulletin: failed to get summary", "port", pn, "error", err)
			continue
		}
		intervals := make([]BulletinInterval, len(summaries))
		for i, h := range summaries {
			intervals[i] = BulletinInterval{
				DeltaRxed:      clampU16(h.DeltaL2Rxed),
				DeltaSent:      clampU16(h.DeltaL2Sent),
				DeltaTimeouts:  clampU16(h.DeltaL2Timeouts),
				DeltaRej:       clampU8(h.DeltaREJRxed),
				DeltaCRC:       clampU8(h.DeltaCRCErrors),
				DeltaAbandoned: clampU8(h.DeltaAbandoned),
				AvgTxPct:       uint8(h.AvgTxPct),
				AvgBusyPct:     uint8(h.AvgBusyPct),
			}
		}
		ports[pn] = intervals
	}

	if len(ports) == 0 {
		statsLog.Warnw("Hourly bulletin: no port data to send")
		return
	}

	encoded := EncodeBulletin(sys, ports, 60)
	subject := fmt.Sprintf("LS1H %s %s %s",
		c.config.Callsign,
		dayStart.Format("2006-01-02"),
		dayStart.Format("15:04"))

	statsLog.Infow("Hourly bulletin encoded",
		"ports", len(ports),
		"encodedLen", len(encoded))

	c.sendBBSBulletin("LS1H", subject, encoded)
}

// send15MinBulletin sends a bulletin with 15-minute interval summaries for [dayStart, dayEnd).
func (c *LinkStatsCollector) send15MinBulletin(dayStart, dayEnd time.Time, sys BulletinSystemStats) {
	portNums, err := c.storage.GetRawPortNumbersRange(dayStart, dayEnd)
	if err != nil || len(portNums) == 0 {
		statsLog.Warnw("15-min bulletin: no raw data available", "error", err)
		return
	}

	ports := make(map[int][]BulletinInterval)
	for _, pn := range portNums {
		summaries, err := c.storage.Get15MinSummaryRange(pn, dayStart, dayEnd)
		if err != nil {
			statsLog.Warnw("15-min bulletin: failed to get summary", "port", pn, "error", err)
			continue
		}
		intervals := make([]BulletinInterval, len(summaries))
		for i, h := range summaries {
			intervals[i] = BulletinInterval{
				DeltaRxed:      clampU16(h.DeltaL2Rxed),
				DeltaSent:      clampU16(h.DeltaL2Sent),
				DeltaTimeouts:  clampU16(h.DeltaL2Timeouts),
				DeltaRej:       clampU8(h.DeltaREJRxed),
				DeltaCRC:       clampU8(h.DeltaCRCErrors),
				DeltaAbandoned: clampU8(h.DeltaAbandoned),
				AvgTxPct:       uint8(h.AvgTxPct),
				AvgBusyPct:     uint8(h.AvgBusyPct),
			}
		}
		ports[pn] = intervals
	}

	if len(ports) == 0 {
		statsLog.Warnw("15-min bulletin: no port data to send")
		return
	}

	encoded := EncodeBulletin(sys, ports, 15)
	subject := fmt.Sprintf("LS15M %s %s %s",
		c.config.Callsign,
		dayStart.Format("2006-01-02"),
		dayStart.Format("15:04"))

	statsLog.Infow("15-min bulletin encoded",
		"ports", len(ports),
		"encodedLen", len(encoded))

	c.sendBBSBulletin("LS15M", subject, encoded)
}

// send5MinBulletin sends a bulletin with 5-minute interval summaries for [dayStart, dayEnd).
func (c *LinkStatsCollector) send5MinBulletin(dayStart, dayEnd time.Time, sys BulletinSystemStats) {
	portNums, err := c.storage.GetRawPortNumbersRange(dayStart, dayEnd)
	if err != nil || len(portNums) == 0 {
		statsLog.Warnw("5-min bulletin: no raw data available", "error", err)
		return
	}

	ports := make(map[int][]BulletinInterval)
	for _, pn := range portNums {
		summaries, err := c.storage.Get5MinSummaryRange(pn, dayStart, dayEnd)
		if err != nil {
			statsLog.Warnw("5-min bulletin: failed to get summary", "port", pn, "error", err)
			continue
		}
		intervals := make([]BulletinInterval, len(summaries))
		for i, h := range summaries {
			intervals[i] = BulletinInterval{
				DeltaRxed:      clampU16(h.DeltaL2Rxed),
				DeltaSent:      clampU16(h.DeltaL2Sent),
				DeltaTimeouts:  clampU16(h.DeltaL2Timeouts),
				DeltaRej:       clampU8(h.DeltaREJRxed),
				DeltaCRC:       clampU8(h.DeltaCRCErrors),
				DeltaAbandoned: clampU8(h.DeltaAbandoned),
				AvgTxPct:       uint8(h.AvgTxPct),
				AvgBusyPct:     uint8(h.AvgBusyPct),
			}
		}
		ports[pn] = intervals
	}

	if len(ports) == 0 {
		statsLog.Warnw("5-min bulletin: no port data to send")
		return
	}

	encoded := EncodeBulletin(sys, ports, 5)
	subject := fmt.Sprintf("LS5M %s %s %s",
		c.config.Callsign,
		dayStart.Format("2006-01-02"),
		dayStart.Format("15:04"))

	statsLog.Infow("5-min bulletin encoded",
		"ports", len(ports),
		"encodedLen", len(encoded))

	c.sendBBSBulletin("LS5M", subject, encoded)
}

// sendPerLinkBulletins sends individual per-port 5-minute bulletins for each RF port.
func (c *LinkStatsCollector) sendPerLinkBulletins(dayStart, dayEnd time.Time, sys BulletinSystemStats) {
	portNums, err := c.storage.GetRawPortNumbersRange(dayStart, dayEnd)
	if err != nil || len(portNums) == 0 {
		statsLog.Warnw("Per-link bulletin: no raw data available", "error", err)
		return
	}

	neighbors, err := c.storage.GetNeighborCallsigns()
	if err != nil {
		statsLog.Warnw("Per-link bulletin: failed to get neighbor callsigns", "error", err)
		neighbors = make(map[int]string)
	}

	for _, pn := range portNums {
		// Skip NetROM virtual port
		if pn == 32 {
			continue
		}

		summaries, err := c.storage.Get5MinSummaryRange(pn, dayStart, dayEnd)
		if err != nil {
			statsLog.Warnw("Per-link bulletin: failed to get summary", "port", pn, "error", err)
			continue
		}
		if len(summaries) == 0 {
			continue
		}

		intervals := make([]BulletinInterval, len(summaries))
		for i, h := range summaries {
			intervals[i] = BulletinInterval{
				DeltaRxed:      clampU16(h.DeltaL2Rxed),
				DeltaSent:      clampU16(h.DeltaL2Sent),
				DeltaTimeouts:  clampU16(h.DeltaL2Timeouts),
				DeltaRej:       clampU8(h.DeltaREJRxed),
				DeltaCRC:       clampU8(h.DeltaCRCErrors),
				DeltaAbandoned: clampU8(h.DeltaAbandoned),
				AvgTxPct:       uint8(h.AvgTxPct),
				AvgBusyPct:     uint8(h.AvgBusyPct),
			}
		}

		singlePort := map[int][]BulletinInterval{pn: intervals}
		encoded := EncodeBulletin(sys, singlePort, 5)

		var subject string
		if neighborCall, ok := neighbors[pn]; ok {
			subject = fmt.Sprintf("LLS5M %s %s P%d %s %s",
				c.config.Callsign, neighborCall, pn,
				dayStart.Format("2006-01-02"),
				dayStart.Format("15:04"))
		} else {
			subject = fmt.Sprintf("LLS5M %s P%d %s %s",
				c.config.Callsign, pn,
				dayStart.Format("2006-01-02"),
				dayStart.Format("15:04"))
		}

		statsLog.Infow("Per-link bulletin encoded",
			"port", pn,
			"neighbor", neighbors[pn],
			"encodedLen", len(encoded))

		c.sendBBSBulletin("LLS5M", subject, encoded)

		// Delay between per-port bulletins
		time.Sleep(5 * time.Second)
	}
}

// sendBBSBulletin opens a short-lived telnet connection, enters BBS mode,
// and sends the encoded bulletin via SB <toAddr> @. Retries up to 3 times
// with increasing delays if the connection fails.
func (c *LinkStatsCollector) sendBBSBulletin(toAddr, subject, encoded string) {
	const maxRetries = 3

	for attempt := 1; attempt <= maxRetries; attempt++ {
		if attempt > 1 {
			delay := time.Duration(attempt*5) * time.Second
			statsLog.Infow("Bulletin: retrying", "attempt", attempt, "delay", delay)
			time.Sleep(delay)
		}

		err := c.trySendBBSBulletin(toAddr, subject, encoded)
		if err == nil {
			return
		}
		statsLog.Warnw("Bulletin: attempt failed",
			"attempt", attempt,
			"maxRetries", maxRetries,
			"error", err)
	}

	statsLog.Errorw("Bulletin: all attempts failed", "subject", subject)
}

// trySendBBSBulletin makes a single attempt to send a BBS bulletin.
// Returns nil on success, error on failure.
func (c *LinkStatsCollector) trySendBBSBulletin(toAddr, subject, encoded string) error {
	addr := fmt.Sprintf("%s:%d", c.config.Hostname, c.config.Port)
	conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		return fmt.Errorf("connect failed: %w", err)
	}
	defer conn.Close()

	tc, err := NewTelnetConn(conn, 2*time.Second, statsLog)
	if err != nil {
		return fmt.Errorf("telnet negotiation failed: %w", err)
	}

	_, err = tc.Authenticate(c.config.Callsign, c.config.Password, 10*time.Second)
	if err != nil {
		return fmt.Errorf("auth failed: %w", err)
	}

	// Enter BBS mode
	if err := tc.WriteString("BBS"); err != nil {
		return fmt.Errorf("failed to enter BBS: %w", err)
	}
	// Wait for BBS SID (e.g. "[LinBPQ-6.0.24.1-B2FHIM$]")
	_, found, err := tc.ReadUntil(func(line string) bool {
		return strings.Contains(line, "[") && strings.Contains(line, "]")
	}, 10*time.Second)
	if err != nil || !found {
		return fmt.Errorf("BBS SID not received: %w", err)
	}

	// Build and send the complete bulletin in one burst
	var buf strings.Builder
	buf.WriteString(fmt.Sprintf("SB %s @\r\n", toAddr))
	buf.WriteString(subject)
	buf.WriteString("\r\n")
	buf.WriteString(encoded)
	buf.WriteString("\r\n")
	buf.WriteString("/EX\r\n")

	if _, err := conn.Write([]byte(buf.String())); err != nil {
		return fmt.Errorf("failed to send: %w", err)
	}

	// Wait for confirmation "Message #N Saved"
	lines, found, _ := tc.ReadUntil(func(line string) bool {
		lower := strings.ToLower(line)
		return strings.Contains(lower, "saved") || strings.Contains(lower, "accepted")
	}, 10*time.Second)
	if found {
		statsLog.Infow("Bulletin sent", "subject", subject, "response", lines[len(lines)-1])
	} else {
		statsLog.Warnw("Bulletin: sent but no confirmation received", "subject", subject)
	}
	return nil
}

// runCompaction runs hourly compaction and daily purge
func (c *LinkStatsCollector) runCompaction(ctx context.Context) {
	if c.storage == nil {
		return
	}

	// Run compaction hourly
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := c.storage.CompactHourly(); err != nil {
				statsLog.Errorw("Hourly compaction failed", "error", err)
			}
			if err := c.storage.CompactDaily(); err != nil {
				statsLog.Errorw("Daily compaction failed", "error", err)
			}
			// Purge raw data older than 30 days
			if err := c.storage.PurgeOldRaw(30 * 24 * time.Hour); err != nil {
				statsLog.Errorw("Raw data purge failed", "error", err)
			}
		}
	}
}

// BroadcastLinkStats broadcasts a link stats snapshot to all WebSocket clients
// This is called from the collector and sends directly (not through the circular buffer)
func BroadcastLinkStats(snap *LinkStatsSnapshot) {
	msg := struct {
		Type      string             `json:"type"`
		Timestamp string             `json:"timestamp"`
		System    SystemStats        `json:"system"`
		Ports     map[int]*PortStats `json:"ports"`
	}{
		Type:      "link_stats",
		Timestamp: snap.Timestamp.Format(time.RFC3339),
		System:    snap.System,
		Ports:     snap.Ports,
	}

	data, err := json.Marshal(msg)
	if err != nil {
		statsLog.Errorw("Failed to marshal link stats for broadcast", "error", err)
		return
	}

	broadcastDirect(string(data))
}
