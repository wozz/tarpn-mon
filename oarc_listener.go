package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"

	"go.uber.org/zap"
)

// OARC event type constants as they appear in the @type JSON field from LinBPQ
const (
	OARCTypeL2Trace     = "L2Trace"
	OARCTypeLinkUp      = "LinkUpEvent"
	OARCTypeLinkDown    = "LinkDownEvent"
	OARCTypeCircuitUp   = "CircuitUpEvent"
	OARCTypeCircuitDown = "CircuitDownEvent"
)

// L2TraceEvent represents a structured AX.25 frame event from the OARC API.
// LinBPQ sends "port" as a JSON string (e.g. "2") and uses abbreviated l2Type
// values: "C" for connect (SABM), "D" for disconnect (DISC).
type L2TraceEvent struct {
	Type   string `json:"@type"`
	Serial int64  `json:"serial"`
	// Epoch seconds. LinBPQ sends this fractional (1787067409.412) even though
	// the OARC spec shows an integer, so it must be a float: with int64 the
	// number fails to unmarshal and takes the whole event with it, silently
	// discarding every frame report.
	Time       float64 `json:"time"`
	Direction  string  `json:"dirn"` // "sent" or "rcvd"
	IsRF       bool    `json:"isRF"`
	ReportFrom string  `json:"reportFrom"`
	Port       string  `json:"port"` // String in LinBPQ (e.g. "2")
	Source     string  `json:"srce"`
	Dest       string  `json:"dest"`
	Ctrl       int     `json:"ctrl"`
	L2Type     string  `json:"l2Type"` // "I", "UI", "C" (SABM), "D" (DISC), "UA", "DM", "RR", "RNR", "REJ", "FRMR", "SABME", "SREJ", "TEST", "XID"
	Modulo     int     `json:"modulo"` // 8=normal AX.25, 128=extended
	CR         string  `json:"cr"`     // "C", "R", or "V1"
	PF         string  `json:"pf"`     // "P" or "F" (optional)
	PID        int     `json:"pid"`    // 0xCF=NetROM, 0xF0=Text
	Protocol   string  `json:"ptcl"`
	ILen       int     `json:"ilen"`
	RSeq       int     `json:"rseq"`
	TSeq       int     `json:"tseq"`
	// NetROM L3/L4 fields (present when pid=0xCF)
	L3Type  string `json:"l3Type"`
	L3Src   string `json:"l3src"`
	L3Dst   string `json:"l3dst"`
	TTL     int    `json:"ttl"`
	L4Type  string `json:"l4Type"` // "CONN REQ", "CONN ACK", "INFO", "INFO ACK", "DISC REQ", "DISC ACK"
	FromCct int    `json:"fromCct"`
	ToCct   int    `json:"toCct"`
	Window  int    `json:"window"`
	TxSeq   int    `json:"txSeq"`  // L4 transmit sequence (INFO frames)
	RxSeq   int    `json:"rxSeq"`  // L4 receive sequence (INFO/INFO ACK)
	PayLen  int    `json:"paylen"` // L4 payload length (INFO frames)
}

// LinkUpEvent represents an AX.25 L2 link establishment
type LinkUpEvent struct {
	Type      string  `json:"@type"`
	Time      float64 `json:"time,omitempty"` // fractional epoch seconds; absent on LinkUp
	Node      string  `json:"node"`           // Reporting node callsign
	ID        int     `json:"id"`
	Direction string  `json:"direction"` // "incoming" or "outgoing"
	Port      string  `json:"port"`
	Remote    string  `json:"remote"`
	Local     string  `json:"local"`
	IsRF      bool    `json:"isRF"` // LinBPQ extension (not in spec)
}

// LinkDownEvent represents an AX.25 L2 link teardown
type LinkDownEvent struct {
	Type       string  `json:"@type"`
	Time       float64 `json:"time"` // fractional epoch seconds
	Node       string  `json:"node"` // Reporting node callsign
	ID         int     `json:"id"`
	Direction  string  `json:"direction"`
	Port       string  `json:"port"`
	Remote     string  `json:"remote"`
	Local      string  `json:"local"`
	UpForSecs  int     `json:"upForSecs"`
	FrmsSent   int64   `json:"frmsSent"`
	FrmsRcvd   int64   `json:"frmsRcvd"`
	FrmsResent int64   `json:"frmsResent"`
	FrmsQueued int64   `json:"frmsQueued"`
	FrmsQdPeak int64   `json:"frmsQdPeak"`
	BytesSent  int64   `json:"bytesSent"`
	BytesRcvd  int64   `json:"bytesRcvd"`
	Reason     string  `json:"reason"`
	IsRF       bool    `json:"isRF"` // LinBPQ extension (not in spec)
}

// CircuitUpEvent represents a NetROM L4 circuit establishment.
// Remote/Local use NetROM address format: "user@node:cct" or "call:cct".
type CircuitUpEvent struct {
	Type      string `json:"@type"`
	Node      string `json:"node"` // Reporting node callsign
	ID        int    `json:"id"`
	Direction string `json:"direction"`
	Service   int    `json:"service,omitempty"` // NetRomX service number
	Remote    string `json:"remote"`            // e.g. "G8PZT@G8PZT:14c0"
	Local     string `json:"local"`             // e.g. "G8PZT-4:0001"
}

// CircuitDownEvent represents a NetROM L4 circuit teardown
type CircuitDownEvent struct {
	Type       string `json:"@type"`
	Node       string `json:"node"` // Reporting node callsign
	ID         int    `json:"id"`
	Direction  string `json:"direction"`
	Service    int    `json:"service,omitempty"`
	Remote     string `json:"remote"`
	Local      string `json:"local"`
	SegsSent   int64  `json:"segsSent"`
	SegsRcvd   int64  `json:"segsRcvd"`
	SegsResent int64  `json:"segsResent"`
	SegsQueued int64  `json:"segsQueued"`
	Reason     string `json:"reason"`
}

// SessionEventHandler is the interface for processing OARC events.
// SessionTracker implements this interface.
type SessionEventHandler interface {
	HandleLinkUp(event *LinkUpEvent)
	HandleLinkDown(event *LinkDownEvent)
	HandleL2Trace(event *L2TraceEvent)
	HandleCircuitUp(event *CircuitUpEvent)
	HandleCircuitDown(event *CircuitDownEvent)
}

// OARCListener listens for JSON events from LinBPQ's OARC API on a UDP port.
type OARCListener struct {
	conn    *net.UDPConn
	port    int
	handler SessionEventHandler
	logger  *zap.SugaredLogger
}

// NewOARCListener creates a new OARC UDP listener on the given port.
func NewOARCListener(port int, handler SessionEventHandler, logger *zap.SugaredLogger) *OARCListener {
	return &OARCListener{
		port:    port,
		handler: handler,
		logger:  logger,
	}
}

// Start binds the UDP socket and processes incoming OARC events until the
// context is cancelled.
func (o *OARCListener) Start(ctx context.Context) error {
	addr := &net.UDPAddr{Port: o.port}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		return fmt.Errorf("failed to bind UDP port %d: %w", o.port, err)
	}
	o.conn = conn
	o.logger.Infow("OARC listener started", "port", o.port)

	go func() {
		<-ctx.Done()
		conn.Close()
	}()

	buf := make([]byte, 65535)
	for {
		n, _, err := conn.ReadFromUDP(buf)
		if err != nil {
			// Check if we were shut down via context cancellation
			select {
			case <-ctx.Done():
				o.logger.Infow("OARC listener stopped")
				return nil
			default:
				o.logger.Warnw("UDP read error", "error", err)
				continue
			}
		}
		if n == 0 {
			continue
		}

		data := make([]byte, n)
		copy(data, buf[:n])

		o.parseOARCEvent(data)
	}
}

// parseOARCEvent parses a single OARC JSON datagram and routes it to the
// appropriate handler method. Exported for testing.
func (o *OARCListener) parseOARCEvent(data []byte) {
	// First pass: extract the @type field to determine event type
	var envelope struct {
		Type string `json:"@type"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		o.logger.Debugw("Failed to parse OARC event envelope", "error", err, "data", string(data))
		return
	}

	switch envelope.Type {
	case OARCTypeL2Trace:
		var event L2TraceEvent
		if err := json.Unmarshal(data, &event); err != nil {
			o.logger.Warnw("Failed to parse l2_trace event", "error", err)
			return
		}
		o.logger.Debugw("OARC l2_trace", "serial", event.Serial, "l2Type", event.L2Type,
			"src", event.Source, "dst", event.Dest, "port", event.Port)
		o.handler.HandleL2Trace(&event)

	case OARCTypeLinkUp:
		var event LinkUpEvent
		if err := json.Unmarshal(data, &event); err != nil {
			o.logger.Warnw("Failed to parse link_up event", "error", err)
			return
		}
		o.logger.Debugw("OARC link_up", "id", event.ID, "remote", event.Remote,
			"local", event.Local, "port", event.Port)
		o.handler.HandleLinkUp(&event)

	case OARCTypeLinkDown:
		var event LinkDownEvent
		if err := json.Unmarshal(data, &event); err != nil {
			o.logger.Warnw("Failed to parse link_down event", "error", err)
			return
		}
		o.logger.Debugw("OARC link_down", "id", event.ID, "remote", event.Remote,
			"local", event.Local, "reason", event.Reason)
		o.handler.HandleLinkDown(&event)

	case OARCTypeCircuitUp:
		var event CircuitUpEvent
		if err := json.Unmarshal(data, &event); err != nil {
			o.logger.Warnw("Failed to parse circuit_up event", "error", err)
			return
		}
		o.logger.Debugw("OARC circuit_up", "id", event.ID, "remote", event.Remote,
			"local", event.Local)
		o.handler.HandleCircuitUp(&event)

	case OARCTypeCircuitDown:
		var event CircuitDownEvent
		if err := json.Unmarshal(data, &event); err != nil {
			o.logger.Warnw("Failed to parse circuit_down event", "error", err)
			return
		}
		o.logger.Debugw("OARC circuit_down", "id", event.ID, "reason", event.Reason)
		o.handler.HandleCircuitDown(&event)

	default:
		o.logger.Debugw("Unknown OARC event type", "type", envelope.Type)
	}
}
