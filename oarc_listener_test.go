package main

import (
	"testing"

	"go.uber.org/zap"
)

// mockHandler records calls to SessionEventHandler methods for test assertions.
type mockHandler struct {
	linkUps      []*LinkUpEvent
	linkDowns    []*LinkDownEvent
	l2Traces     []*L2TraceEvent
	circuitUps   []*CircuitUpEvent
	circuitDowns []*CircuitDownEvent
}

func (m *mockHandler) HandleLinkUp(event *LinkUpEvent)         { m.linkUps = append(m.linkUps, event) }
func (m *mockHandler) HandleLinkDown(event *LinkDownEvent)     { m.linkDowns = append(m.linkDowns, event) }
func (m *mockHandler) HandleL2Trace(event *L2TraceEvent)       { m.l2Traces = append(m.l2Traces, event) }
func (m *mockHandler) HandleCircuitUp(event *CircuitUpEvent)   { m.circuitUps = append(m.circuitUps, event) }
func (m *mockHandler) HandleCircuitDown(event *CircuitDownEvent) { m.circuitDowns = append(m.circuitDowns, event) }

func oarcTestLogger() *zap.SugaredLogger {
	logger, _ := zap.NewDevelopment()
	return logger.Sugar()
}

func newTestOARCListener(handler *mockHandler) *OARCListener {
	return NewOARCListener(0, handler, oarcTestLogger())
}

func TestParseL2TraceEvent(t *testing.T) {
	tests := []struct {
		name    string
		json    string
		check   func(t *testing.T, h *mockHandler)
	}{
		{
			name: "I-frame with NetROM",
			json: `{
				"@type": "L2Trace",
				"serial": 12345,
				"time": 1700000000,
				"dirn": "sent",
				"isRF": true,
				"reportFrom": "WA2M",
				"port": "1",
				"srce": "WA2M-2",
				"dest": "N3LLO-2",
				"ctrl": 48,
				"l2Type": "I",
				"modulo": 8,
				"cr": "C",
				"pid": 207,
				"ptcl": "NET/ROM",
				"ilen": 100,
				"rseq": 3,
				"tseq": 2,
				"l3Type": "NetRom",
				"l3src": "WA2M",
				"l3dst": "N3LLO",
				"ttl": 7,
				"l4Type": "INFO",
				"fromCct": 1,
				"toCct": 2,
				"window": 4,
				"txSeq": 1,
				"rxSeq": 2,
				"paylen": 50
			}`,
			check: func(t *testing.T, h *mockHandler) {
				if len(h.l2Traces) != 1 {
					t.Fatalf("Expected 1 l2_trace, got %d", len(h.l2Traces))
				}
				e := h.l2Traces[0]
				if e.Type != "L2Trace" {
					t.Errorf("Type = %q, want L2Trace", e.Type)
				}
				if e.Serial != 12345 {
					t.Errorf("Serial = %d, want 12345", e.Serial)
				}
				if e.Direction != "sent" {
					t.Errorf("Direction = %q, want sent", e.Direction)
				}
				if !e.IsRF {
					t.Error("IsRF should be true")
				}
				if e.Port != "1" {
					t.Errorf("Port = %q, want 1", e.Port)
				}
				if e.Source != "WA2M-2" {
					t.Errorf("Source = %q, want WA2M-2", e.Source)
				}
				if e.Dest != "N3LLO-2" {
					t.Errorf("Dest = %q, want N3LLO-2", e.Dest)
				}
				if e.L2Type != "I" {
					t.Errorf("L2Type = %q, want I", e.L2Type)
				}
				if e.Modulo != 8 {
					t.Errorf("Modulo = %d, want 8", e.Modulo)
				}
				if e.PID != 207 { // 0xCF
					t.Errorf("PID = %d, want 207", e.PID)
				}
				if e.ILen != 100 {
					t.Errorf("ILen = %d, want 100", e.ILen)
				}
				if e.RSeq != 3 {
					t.Errorf("RSeq = %d, want 3", e.RSeq)
				}
				if e.TSeq != 2 {
					t.Errorf("TSeq = %d, want 2", e.TSeq)
				}
				if e.L3Type != "NetRom" {
					t.Errorf("L3Type = %q, want NetRom", e.L3Type)
				}
				if e.L4Type != "INFO" {
					t.Errorf("L4Type = %q, want INFO", e.L4Type)
				}
				if e.TTL != 7 {
					t.Errorf("TTL = %d, want 7", e.TTL)
				}
				if e.TxSeq != 1 {
					t.Errorf("TxSeq = %d, want 1", e.TxSeq)
				}
				if e.RxSeq != 2 {
					t.Errorf("RxSeq = %d, want 2", e.RxSeq)
				}
				if e.PayLen != 50 {
					t.Errorf("PayLen = %d, want 50", e.PayLen)
				}
			},
		},
		{
			name: "Connect frame (SABM sent as C by LinBPQ)",
			json: `{
				"@type": "L2Trace",
				"serial": 100,
				"dirn": "sent",
				"port": "2",
				"srce": "WA2M-2",
				"dest": "KB2FAF-2",
				"ctrl": 63,
				"l2Type": "C",
				"modulo": 8,
				"cr": "C",
				"pf": "P"
			}`,
			check: func(t *testing.T, h *mockHandler) {
				if len(h.l2Traces) != 1 {
					t.Fatalf("Expected 1 l2_trace, got %d", len(h.l2Traces))
				}
				e := h.l2Traces[0]
				if e.L2Type != "C" {
					t.Errorf("L2Type = %q, want C", e.L2Type)
				}
				if e.Port != "2" {
					t.Errorf("Port = %q, want 2", e.Port)
				}
				if e.CR != "C" {
					t.Errorf("CR = %q, want C", e.CR)
				}
				if e.PF != "P" {
					t.Errorf("PF = %q, want P", e.PF)
				}
			},
		},
		{
			name: "UI frame",
			json: `{
				"@type": "L2Trace",
				"serial": 200,
				"dirn": "rcvd",
				"port": "1",
				"srce": "N3LLO",
				"dest": "CQ",
				"l2Type": "UI",
				"pid": 255,
				"ilen": 45
			}`,
			check: func(t *testing.T, h *mockHandler) {
				if len(h.l2Traces) != 1 {
					t.Fatalf("Expected 1 l2_trace, got %d", len(h.l2Traces))
				}
				e := h.l2Traces[0]
				if e.L2Type != "UI" {
					t.Errorf("L2Type = %q, want UI", e.L2Type)
				}
				if e.PID != 255 {
					t.Errorf("PID = %d, want 255", e.PID)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := &mockHandler{}
			listener := newTestOARCListener(h)
			listener.parseOARCEvent([]byte(tt.json))
			tt.check(t, h)
		})
	}
}

func TestParseLinkUpEvent(t *testing.T) {
	tests := []struct {
		name  string
		json  string
		check func(t *testing.T, h *mockHandler)
	}{
		{
			name: "outgoing RF link",
			json: `{
				"@type": "LinkUpEvent",
				"id": 42,
				"direction": "outgoing",
				"port": "1",
				"remote": "N3LLO-2",
				"local": "WA2M-2",
				"isRF": true
			}`,
			check: func(t *testing.T, h *mockHandler) {
				if len(h.linkUps) != 1 {
					t.Fatalf("Expected 1 link_up, got %d", len(h.linkUps))
				}
				e := h.linkUps[0]
				if e.Type != "LinkUpEvent" {
					t.Errorf("Type = %q, want LinkUpEvent", e.Type)
				}
				if e.ID != 42 {
					t.Errorf("ID = %d, want 42", e.ID)
				}
				if e.Direction != "outgoing" {
					t.Errorf("Direction = %q, want outgoing", e.Direction)
				}
				if e.Port != "1" {
					t.Errorf("Port = %q, want 1", e.Port)
				}
				if e.Remote != "N3LLO-2" {
					t.Errorf("Remote = %q, want N3LLO-2", e.Remote)
				}
				if e.Local != "WA2M-2" {
					t.Errorf("Local = %q, want WA2M-2", e.Local)
				}
				if !e.IsRF {
					t.Error("IsRF should be true")
				}
			},
		},
		{
			name: "incoming link",
			json: `{
				"@type": "LinkUpEvent",
				"id": 7,
				"direction": "incoming",
				"port": "3",
				"remote": "KB2FAF-2",
				"local": "WA2M-2",
				"isRF": false
			}`,
			check: func(t *testing.T, h *mockHandler) {
				if len(h.linkUps) != 1 {
					t.Fatalf("Expected 1 link_up, got %d", len(h.linkUps))
				}
				e := h.linkUps[0]
				if e.Direction != "incoming" {
					t.Errorf("Direction = %q, want incoming", e.Direction)
				}
				if e.IsRF {
					t.Error("IsRF should be false")
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := &mockHandler{}
			listener := newTestOARCListener(h)
			listener.parseOARCEvent([]byte(tt.json))
			tt.check(t, h)
		})
	}
}

func TestParseLinkDownEvent(t *testing.T) {
	json := `{
		"@type": "LinkDownEvent",
		"id": 42,
		"direction": "outgoing",
		"port": "1",
		"remote": "N3LLO-2",
		"local": "WA2M-2",
		"bytesSent": 1024,
		"bytesRcvd": 2048,
		"frmsSent": 100,
		"frmsRcvd": 200,
		"frmsResent": 5,
		"reason": "Normal",
		"upForSecs": 3600,
		"isRF": true
	}`

	h := &mockHandler{}
	listener := newTestOARCListener(h)
	listener.parseOARCEvent([]byte(json))

	if len(h.linkDowns) != 1 {
		t.Fatalf("Expected 1 link_down, got %d", len(h.linkDowns))
	}
	e := h.linkDowns[0]
	if e.Type != "LinkDownEvent" {
		t.Errorf("Type = %q, want LinkDownEvent", e.Type)
	}
	if e.ID != 42 {
		t.Errorf("ID = %d, want 42", e.ID)
	}
	if e.BytesSent != 1024 {
		t.Errorf("BytesSent = %d, want 1024", e.BytesSent)
	}
	if e.BytesRcvd != 2048 {
		t.Errorf("BytesRcvd = %d, want 2048", e.BytesRcvd)
	}
	if e.FrmsSent != 100 {
		t.Errorf("FrmsSent = %d, want 100", e.FrmsSent)
	}
	if e.FrmsRcvd != 200 {
		t.Errorf("FrmsRcvd = %d, want 200", e.FrmsRcvd)
	}
	if e.FrmsResent != 5 {
		t.Errorf("FrmsResent = %d, want 5", e.FrmsResent)
	}
	if e.Reason != "Normal" {
		t.Errorf("Reason = %q, want Normal", e.Reason)
	}
	if e.UpForSecs != 3600 {
		t.Errorf("UpForSecs = %d, want 3600", e.UpForSecs)
	}
	if !e.IsRF {
		t.Error("IsRF should be true")
	}
}

func TestParseCircuitUpEvent(t *testing.T) {
	json := `{
		"@type": "CircuitUpEvent",
		"id": 99,
		"direction": "outgoing",
		"remote": "N3LLO",
		"local": "WA2M"
	}`

	h := &mockHandler{}
	listener := newTestOARCListener(h)
	listener.parseOARCEvent([]byte(json))

	if len(h.circuitUps) != 1 {
		t.Fatalf("Expected 1 circuit_up, got %d", len(h.circuitUps))
	}
	e := h.circuitUps[0]
	if e.Type != "CircuitUpEvent" {
		t.Errorf("Type = %q, want CircuitUpEvent", e.Type)
	}
	if e.ID != 99 {
		t.Errorf("ID = %d, want 99", e.ID)
	}
	if e.Direction != "outgoing" {
		t.Errorf("Direction = %q, want outgoing", e.Direction)
	}
	if e.Remote != "N3LLO" {
		t.Errorf("Remote = %q, want N3LLO", e.Remote)
	}
	if e.Local != "WA2M" {
		t.Errorf("Local = %q, want WA2M", e.Local)
	}
}

func TestParseCircuitDownEvent(t *testing.T) {
	json := `{
		"@type": "CircuitDownEvent",
		"id": 99,
		"segsSent": 500,
		"segsRcvd": 600,
		"segsResent": 10,
		"reason": "Normal"
	}`

	h := &mockHandler{}
	listener := newTestOARCListener(h)
	listener.parseOARCEvent([]byte(json))

	if len(h.circuitDowns) != 1 {
		t.Fatalf("Expected 1 circuit_down, got %d", len(h.circuitDowns))
	}
	e := h.circuitDowns[0]
	if e.Type != "CircuitDownEvent" {
		t.Errorf("Type = %q, want CircuitDownEvent", e.Type)
	}
	if e.ID != 99 {
		t.Errorf("ID = %d, want 99", e.ID)
	}
	if e.SegsSent != 500 {
		t.Errorf("SegsSent = %d, want 500", e.SegsSent)
	}
	if e.SegsRcvd != 600 {
		t.Errorf("SegsRcvd = %d, want 600", e.SegsRcvd)
	}
	if e.SegsResent != 10 {
		t.Errorf("SegsResent = %d, want 10", e.SegsResent)
	}
	if e.Reason != "Normal" {
		t.Errorf("Reason = %q, want Normal", e.Reason)
	}
}

func TestParseUnknownEventType(t *testing.T) {
	json := `{"@type": "unknown_future_type", "id": 1}`

	h := &mockHandler{}
	listener := newTestOARCListener(h)
	listener.parseOARCEvent([]byte(json))

	// Should not route to any handler
	if len(h.linkUps) != 0 || len(h.linkDowns) != 0 || len(h.l2Traces) != 0 ||
		len(h.circuitUps) != 0 || len(h.circuitDowns) != 0 {
		t.Error("Unknown event type should not be routed to any handler")
	}
}

func TestParseInvalidJSON(t *testing.T) {
	h := &mockHandler{}
	listener := newTestOARCListener(h)

	// Should not panic or route anything
	listener.parseOARCEvent([]byte(`not json at all`))
	listener.parseOARCEvent([]byte(`{}`))
	listener.parseOARCEvent([]byte(`{"@type": ""}`))

	if len(h.linkUps) != 0 || len(h.linkDowns) != 0 || len(h.l2Traces) != 0 ||
		len(h.circuitUps) != 0 || len(h.circuitDowns) != 0 {
		t.Error("Invalid JSON should not be routed to any handler")
	}
}

func TestParseMalformedEventBody(t *testing.T) {
	// Valid @type but the rest of the body has a type mismatch
	// e.g. "serial" should be int but is a string
	json := `{"@type": "L2Trace", "serial": "not_a_number"}`

	h := &mockHandler{}
	listener := newTestOARCListener(h)
	listener.parseOARCEvent([]byte(json))

	// Should fail to unmarshal into L2TraceEvent and not call handler
	if len(h.l2Traces) != 0 {
		t.Error("Malformed event body should not be routed to handler")
	}
}

func TestMultipleEventsSequentially(t *testing.T) {
	h := &mockHandler{}
	listener := newTestOARCListener(h)

	events := []string{
		`{"@type": "LinkUpEvent", "node": "WA2M", "id": 1, "direction": "outgoing", "port": "1", "remote": "N3LLO-2", "local": "WA2M-2", "isRF": true}`,
		`{"@type": "L2Trace", "serial": 1, "dirn": "sent", "port": "1", "srce": "WA2M-2", "dest": "N3LLO-2", "l2Type": "I", "pid": 207, "tseq": 0}`,
		`{"@type": "L2Trace", "serial": 2, "dirn": "rcvd", "port": "1", "srce": "N3LLO-2", "dest": "WA2M-2", "l2Type": "RR", "cr": "R"}`,
		`{"@type": "CircuitUpEvent", "node": "WA2M", "id": 10, "direction": "outgoing", "remote": "N3LLO:0001", "local": "WA2M:0001"}`,
		`{"@type": "CircuitDownEvent", "node": "WA2M", "id": 10, "direction": "outgoing", "segsSent": 50, "segsRcvd": 60, "reason": "Normal"}`,
		`{"@type": "LinkDownEvent", "node": "WA2M", "id": 1, "direction": "outgoing", "port": "1", "remote": "N3LLO-2", "local": "WA2M-2", "reason": "Normal", "upForSecs": 120}`,
	}

	for _, event := range events {
		listener.parseOARCEvent([]byte(event))
	}

	if len(h.linkUps) != 1 {
		t.Errorf("Expected 1 link_up, got %d", len(h.linkUps))
	}
	if len(h.l2Traces) != 2 {
		t.Errorf("Expected 2 l2_traces, got %d", len(h.l2Traces))
	}
	if len(h.circuitUps) != 1 {
		t.Errorf("Expected 1 circuit_up, got %d", len(h.circuitUps))
	}
	if len(h.circuitDowns) != 1 {
		t.Errorf("Expected 1 circuit_down, got %d", len(h.circuitDowns))
	}
	if len(h.linkDowns) != 1 {
		t.Errorf("Expected 1 link_down, got %d", len(h.linkDowns))
	}
}

func TestL2TraceEventFieldMapping(t *testing.T) {
	// Verify that JSON field names with non-obvious mappings parse correctly
	json := `{
		"@type": "L2Trace",
		"serial": 1,
		"dirn": "rcvd",
		"srce": "N3LLO-2",
		"dest": "WA2M-2",
		"port": "3",
		"l2Type": "REJ",
		"cr": "R",
		"ptcl": "AX25",
		"ilen": 0,
		"rseq": 5,
		"tseq": 0
	}`

	h := &mockHandler{}
	listener := newTestOARCListener(h)
	listener.parseOARCEvent([]byte(json))

	if len(h.l2Traces) != 1 {
		t.Fatalf("Expected 1 l2_trace, got %d", len(h.l2Traces))
	}
	e := h.l2Traces[0]
	// "dirn" -> Direction
	if e.Direction != "rcvd" {
		t.Errorf("Direction = %q, want rcvd", e.Direction)
	}
	// "srce" -> Source
	if e.Source != "N3LLO-2" {
		t.Errorf("Source = %q, want N3LLO-2", e.Source)
	}
	// "ptcl" -> Protocol
	if e.Protocol != "AX25" {
		t.Errorf("Protocol = %q, want AX25", e.Protocol)
	}
}
