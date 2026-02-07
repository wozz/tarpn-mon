package main

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// LinkStatsSnapshot represents one poll of the S command
type LinkStatsSnapshot struct {
	Timestamp time.Time          `json:"timestamp"`
	System    SystemStats        `json:"system"`
	Ports     map[int]*PortStats `json:"ports"`
}

// SystemStats holds system-wide statistics from the S command header
type SystemStats struct {
	UptimeDays  int   `json:"uptimeDays"`
	UptimeHours int   `json:"uptimeHours"`
	UptimeMins  int   `json:"uptimeMins"`
	SemGets     int64 `json:"semGets"`
	SemClashes  int64 `json:"semClashes"`
	BuffersMax  int64 `json:"buffersMax"`
	BuffersCur  int64 `json:"buffersCur"`
	BuffersMin  int64 `json:"buffersMin"`
	BuffersOut  int64 `json:"buffersOut"`
	BuffersWait int64 `json:"buffersWait"`
	KnownNodes  int64 `json:"knownNodes"`
	MaxNodes    int64 `json:"maxNodes"`
	L4ConnSent  int64 `json:"l4ConnSent"`
	L4ConnRxed  int64 `json:"l4ConnRxed"`
	L4FramesTx  int64 `json:"l4FramesTx"`
	L4FramesRx  int64 `json:"l4FramesRx"`
	L4Resent    int64 `json:"l4Resent"`
	L4Reseq     int64 `json:"l4Reseq"`
	L3Relayed   int64 `json:"l3Relayed"`
}

// PortStats holds per-port L2 statistics
type PortStats struct {
	PortNum         int   `json:"portNum"`
	L2Digied        int64 `json:"l2Digied"`
	L2Heard         int64 `json:"l2Heard"`
	L2Rxed          int64 `json:"l2Rxed"`
	L2Sent          int64 `json:"l2Sent"`
	L2Timeouts      int64 `json:"l2Timeouts"`
	REJRxed         int64 `json:"rejRxed"`
	RXOutOfSeq      int64 `json:"rxOutOfSeq"`
	L2Resequenced   int64 `json:"l2Resequenced"`
	UndrunPollTo    int64 `json:"undrunPollTo"`
	RXOverruns      int64 `json:"rxOverruns"`
	RXCRCErrors     int64 `json:"rxCrcErrors"`
	FRMRsSent       int64 `json:"frmrsSent"`
	FRMRsReceived   int64 `json:"frmrsReceived"`
	FramesAbandoned int64 `json:"framesAbandoned"`
	ActiveTxPct     int   `json:"activeTxPct"`
	ActiveBusyPct   int   `json:"activeBusyPct"`
}

// portStatRowOrder defines the order of stat rows in the S command port table.
// Each entry maps to a PortStats field setter.
var portStatRowLabels = []string{
	"L2 Frames Digied",
	"L2 Frames Heard",
	"L2 Frames Rxed",
	"L2 Frames Sent",
	"L2 Timeouts",
	"REJ Frames Rxed",
	"RX out of Seq",
	"L2 Resequenced",
	"Undrun/Poll T/o",
	"RX Overruns",
	"RX CRC Errors",
	"FRMRs Sent",
	"FRMRs Received",
	"Frames abandoned",
}

// setPortStatByRow sets the appropriate PortStats field based on the row index
func setPortStatByRow(ps *PortStats, rowIdx int, value int64) {
	switch rowIdx {
	case 0:
		ps.L2Digied = value
	case 1:
		ps.L2Heard = value
	case 2:
		ps.L2Rxed = value
	case 3:
		ps.L2Sent = value
	case 4:
		ps.L2Timeouts = value
	case 5:
		ps.REJRxed = value
	case 6:
		ps.RXOutOfSeq = value
	case 7:
		ps.L2Resequenced = value
	case 8:
		ps.UndrunPollTo = value
	case 9:
		ps.RXOverruns = value
	case 10:
		ps.RXCRCErrors = value
	case 11:
		ps.FRMRsSent = value
	case 12:
		ps.FRMRsReceived = value
	case 13:
		ps.FramesAbandoned = value
	}
}

// portHeaderRe matches "Port NN" in the port header row
var portHeaderRe = regexp.MustCompile(`Port\s+(\d+)`)

// ParseSCommandOutput parses the text output of LinBPQ's S (Stats) command
// into a structured LinkStatsSnapshot.
func ParseSCommandOutput(lines []string) (*LinkStatsSnapshot, error) {
	snap := &LinkStatsSnapshot{
		Timestamp: time.Now(),
		Ports:     make(map[int]*PortStats),
	}

	// Parse system stats from header lines
	for _, line := range lines {
		parseSystemStatsLine(&snap.System, line)
	}

	// Parse per-port stats tables
	// LinBPQ outputs up to 7 ports per page. If >7 ports, there are multiple
	// header+data sections. We scan for "Port NN" header rows and parse
	// the data rows that follow each one.
	i := 0
	for i < len(lines) {
		// Look for a port header line (contains "Port NN" patterns)
		portNums := parsePortHeaderLine(lines[i])
		if len(portNums) > 0 {
			// Ensure PortStats exist for each port
			for _, pn := range portNums {
				if _, ok := snap.Ports[pn]; !ok {
					snap.Ports[pn] = &PortStats{PortNum: pn}
				}
			}
			// Parse the stat rows that follow
			i++
			rowIdx := 0
			for i < len(lines) {
				line := lines[i]
				if strings.Contains(line, "Active") && strings.Contains(line, "%") {
					// Parse Active(TX/Busy) % line — last line of a port page
					parseActiveLine(line, portNums, snap.Ports)
					i++
					break
				}
				if rowIdx >= len(portStatRowLabels) {
					break
				}
				// Check if this line matches a known stat row label
				matchedLabel := -1
				for li, label := range portStatRowLabels {
					if li >= rowIdx && strings.Contains(line, label) {
						matchedLabel = li
						break
					}
				}
				if matchedLabel >= 0 {
					values := extractPortValues(line, len(portNums))
					for ci, val := range values {
						if ci < len(portNums) {
							setPortStatByRow(snap.Ports[portNums[ci]], matchedLabel, val)
						}
					}
					rowIdx = matchedLabel + 1
					i++
				} else {
					i++
				}
			}
		} else {
			i++
		}
	}

	return snap, nil
}

// parseSystemStatsLine extracts system stats from a single line
func parseSystemStatsLine(sys *SystemStats, line string) {
	trimmed := strings.TrimSpace(line)

	if strings.HasPrefix(trimmed, "Uptime") {
		// "Uptime (Days Hours Mins)     DD:HH:MM"
		parts := strings.Fields(trimmed)
		for _, p := range parts {
			if strings.Contains(p, ":") && len(p) >= 5 {
				timeParts := strings.Split(p, ":")
				if len(timeParts) == 3 {
					sys.UptimeDays, _ = strconv.Atoi(timeParts[0])
					sys.UptimeHours, _ = strconv.Atoi(timeParts[1])
					sys.UptimeMins, _ = strconv.Atoi(timeParts[2])
					return
				}
			}
		}
	}

	if strings.HasPrefix(trimmed, "Semaphore") {
		vals := extractTrailingInts(trimmed, 2)
		if len(vals) >= 2 {
			sys.SemGets = vals[0]
			sys.SemClashes = vals[1]
		}
	}

	if strings.HasPrefix(trimmed, "Buffers") {
		vals := extractTrailingInts(trimmed, 5)
		if len(vals) >= 5 {
			sys.BuffersMax = vals[0]
			sys.BuffersCur = vals[1]
			sys.BuffersMin = vals[2]
			sys.BuffersOut = vals[3]
			sys.BuffersWait = vals[4]
		}
	}

	if strings.HasPrefix(trimmed, "Known Nodes") {
		vals := extractTrailingInts(trimmed, 2)
		if len(vals) >= 2 {
			sys.KnownNodes = vals[0]
			sys.MaxNodes = vals[1]
		}
	}

	if strings.HasPrefix(trimmed, "L4 Connects") {
		vals := extractTrailingInts(trimmed, 2)
		if len(vals) >= 2 {
			sys.L4ConnSent = vals[0]
			sys.L4ConnRxed = vals[1]
		}
	}

	if strings.HasPrefix(trimmed, "L4 Frames") {
		vals := extractTrailingInts(trimmed, 4)
		if len(vals) >= 4 {
			sys.L4FramesTx = vals[0]
			sys.L4FramesRx = vals[1]
			sys.L4Resent = vals[2]
			sys.L4Reseq = vals[3]
		}
	}

	if strings.HasPrefix(trimmed, "L3 Frames") {
		vals := extractTrailingInts(trimmed, 1)
		if len(vals) >= 1 {
			sys.L3Relayed = vals[0]
		}
	}
}

// extractTrailingInts extracts the last N integers from a line
func extractTrailingInts(line string, count int) []int64 {
	fields := strings.Fields(line)
	var result []int64
	for i := len(fields) - 1; i >= 0 && len(result) < count; i-- {
		if v, err := strconv.ParseInt(fields[i], 10, 64); err == nil {
			result = append([]int64{v}, result...)
		}
	}
	return result
}

// parsePortHeaderLine extracts port numbers from a header line like
// "                  Port 01  Port 02  Port 03  Port 32"
func parsePortHeaderLine(line string) []int {
	matches := portHeaderRe.FindAllStringSubmatch(line, -1)
	if len(matches) == 0 {
		return nil
	}
	// Verify this looks like a header line (not a stat row that happens to contain "Port")
	// Header lines have multiple "Port NN" entries or are mostly whitespace + Port entries
	if !strings.Contains(line, "Port") {
		return nil
	}
	var ports []int
	for _, m := range matches {
		if pn, err := strconv.Atoi(m[1]); err == nil {
			ports = append(ports, pn)
		}
	}
	return ports
}

// extractPortValues extracts integer values from a stat row.
// The row format is: "Label           value1   value2   value3"
// Values are right-justified in ~9-char columns after the label.
func extractPortValues(line string, expectedCount int) []int64 {
	// Strategy: extract all integer tokens from the line, take the last expectedCount
	fields := strings.Fields(line)
	var allInts []int64
	for _, f := range fields {
		if v, err := strconv.ParseInt(f, 10, 64); err == nil {
			allInts = append(allInts, v)
		}
	}
	// Take the last expectedCount values (the label words won't parse as ints)
	if len(allInts) >= expectedCount {
		return allInts[len(allInts)-expectedCount:]
	}
	return allInts
}

// parseActiveLine parses "Active(TX/Busy) %  XX YYY  XX YYY  ..."
// Each port has two values: TX% and Busy%
func parseActiveLine(line string, portNums []int, ports map[int]*PortStats) {
	// Extract all integers from the line
	fields := strings.Fields(line)
	var allInts []int
	for _, f := range fields {
		// Skip the "%" character
		if f == "%" {
			continue
		}
		if v, err := strconv.Atoi(f); err == nil {
			allInts = append(allInts, v)
		}
	}
	// We expect pairs of (TX%, Busy%) for each port
	for i := 0; i < len(portNums) && i*2+1 < len(allInts); i++ {
		if ps, ok := ports[portNums[i]]; ok {
			ps.ActiveTxPct = allInts[i*2]
			ps.ActiveBusyPct = allInts[i*2+1]
		}
	}
}

// String returns a human-readable summary of the snapshot
func (s *LinkStatsSnapshot) String() string {
	var b strings.Builder
	fmt.Fprintf(&b, "LinkStats at %s\n", s.Timestamp.Format(time.RFC3339))
	fmt.Fprintf(&b, "  System: uptime=%dd%dh%dm, buffers=%d/%d, nodes=%d, L3=%d\n",
		s.System.UptimeDays, s.System.UptimeHours, s.System.UptimeMins,
		s.System.BuffersCur, s.System.BuffersMax,
		s.System.KnownNodes, s.System.L3Relayed)
	for pn, ps := range s.Ports {
		fmt.Fprintf(&b, "  Port %02d: rxed=%d sent=%d timeouts=%d rej=%d crc=%d tx%%=%d busy%%=%d\n",
			pn, ps.L2Rxed, ps.L2Sent, ps.L2Timeouts, ps.REJRxed,
			ps.RXCRCErrors, ps.ActiveTxPct, ps.ActiveBusyPct)
	}
	return b.String()
}
