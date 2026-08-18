package main

import (
	"regexp"
	"strconv"
	"strings"
)

// ParsedFrame holds fields extracted from monitor text for enrichment
type ParsedFrame struct {
	FrameType string // "I", "UI", "SABM", "DISC", "UA", "DM", "RR", "RNR", "REJ", "FRMR"
	NS        int    // N(S) sequence number, -1 if absent
	NR        int    // N(R) sequence number, -1 if absent
	PID       string // hex string like "CF", "F0"
	IsCommand bool   // true if Command frame
	InfoLen   int    // info field length, 0 if absent
}

var (
	controlFieldRe = regexp.MustCompile(`<([A-Z]+)\s+([^>]*)>`)
	nrRe           = regexp.MustCompile(`R(\d+)`)
	nsRe           = regexp.MustCompile(`S(\d+)`)
	pidRe          = regexp.MustCompile(`pid=([0-9A-Fa-f]+)`)
	lenRe          = regexp.MustCompile(`Len=(\d+)`)
)

// ParseFrameControl extracts frame type information from a monitor text line.
// The monitor text from LinBPQ contains control field info in angle brackets like:
//
//	<I C P R1 S2>     - I-frame, Command, Poll, N(R)=1, N(S)=2
//	<RR C P R3>       - RR supervisory, Command, Poll, N(R)=3
//	<SABM C P>        - SABM unnumbered, Command, Poll
//	<UA R F>           - UA unnumbered, Response, Final
//	<UI C>             - UI frame, Command
//
// Returns nil if no control field found.
func ParseFrameControl(message string) *ParsedFrame {
	matches := controlFieldRe.FindStringSubmatch(message)
	if matches == nil {
		return nil
	}

	frameType := matches[1]
	params := matches[2]

	frame := &ParsedFrame{
		FrameType: frameType,
		NS:        -1,
		NR:        -1,
	}

	// Parse command/response
	if strings.Contains(params, "C") {
		frame.IsCommand = true
	}

	// Parse N(R) - e.g. "R3"
	if nrMatch := nrRe.FindStringSubmatch(params); nrMatch != nil {
		frame.NR, _ = strconv.Atoi(nrMatch[1])
	}

	// Parse N(S) - e.g. "S2"
	if nsMatch := nsRe.FindStringSubmatch(params); nsMatch != nil {
		frame.NS, _ = strconv.Atoi(nsMatch[1])
	}

	// Parse PID from the full message (may appear after the control field)
	if pidMatch := pidRe.FindStringSubmatch(message); pidMatch != nil {
		frame.PID = strings.ToUpper(pidMatch[1])
	}

	// Parse info length
	if lenMatch := lenRe.FindStringSubmatch(message); lenMatch != nil {
		frame.InfoLen, _ = strconv.Atoi(lenMatch[1])
	}

	return frame
}
