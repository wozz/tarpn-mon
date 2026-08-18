package main

import (
	"encoding/json"
	"testing"
)

// LinBPQ sends the event timestamp as fractional epoch seconds, e.g.
// 1787067409.412, even though the OARC spec shows an integer. Declaring it
// int64 does not merely lose precision on a field nothing reads - encoding/json
// fails the whole object, so every l2_trace event was discarded with
//
//	cannot unmarshal number 1787067409.412 into Go struct field
//	L2TraceEvent.time of type int64
//
// and session tracking had no frame data at all.
func TestL2TraceAcceptsFractionalTime(t *testing.T) {
	raw := []byte(`{"@type":"l2Trace","serial":42,"time":1787067409.412,
	                "dirn":"rcvd","isRF":true,"reportFrom":"WA2M-2","port":"2",
	                "srce":"N2IRZ-2","dest":"WA2M-2","l2Type":"I","paylen":54}`)

	var ev L2TraceEvent
	if err := json.Unmarshal(raw, &ev); err != nil {
		t.Fatalf("fractional time must parse: %v", err)
	}
	if ev.Port != "2" || ev.Source != "N2IRZ-2" {
		t.Fatalf("event decoded wrongly: %+v", ev)
	}
	if int64(ev.Time) != 1787067409 {
		t.Errorf("Time = %v, want ~1787067409", ev.Time)
	}
}

// Integer timestamps, as the spec describes, must keep working.
func TestL2TraceAcceptsIntegerTime(t *testing.T) {
	var ev L2TraceEvent
	if err := json.Unmarshal([]byte(`{"@type":"l2Trace","time":1787067409,"port":"3"}`), &ev); err != nil {
		t.Fatalf("integer time must still parse: %v", err)
	}
	if ev.Port != "3" {
		t.Errorf("port = %q", ev.Port)
	}
}

func TestLinkEventsAcceptFractionalTime(t *testing.T) {
	var up LinkUpEvent
	if err := json.Unmarshal([]byte(`{"@type":"linkUp","time":1787067409.412,"port":"1","remote":"NZ2Z-2"}`), &up); err != nil {
		t.Fatalf("linkUp: %v", err)
	}
	var down LinkDownEvent
	if err := json.Unmarshal([]byte(`{"@type":"linkDown","time":1787067414.572,"port":"1","remote":"NZ2Z-2"}`), &down); err != nil {
		t.Fatalf("linkDown: %v", err)
	}
	if up.Remote != "NZ2Z-2" || down.Remote != "NZ2Z-2" {
		t.Errorf("decoded wrongly: up=%+v down=%+v", up, down)
	}
}
