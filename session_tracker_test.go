package main

import (
	"sync"
	"testing"
	"time"

	"go.uber.org/zap"
)

func testLogger() *zap.SugaredLogger {
	logger, _ := zap.NewDevelopment()
	return logger.Sugar()
}

type changeRecorder struct {
	mu       sync.Mutex
	sessions []*Session
}

func (r *changeRecorder) record(s *Session) {
	r.mu.Lock()
	defer r.mu.Unlock()
	// Copy to avoid mutation
	cp := *s
	r.sessions = append(r.sessions, &cp)
}

func (r *changeRecorder) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.sessions)
}

func (r *changeRecorder) last() *Session {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.sessions) == 0 {
		return nil
	}
	return r.sessions[len(r.sessions)-1]
}

func TestSessionKeyNormalization(t *testing.T) {
	// A>B and B>A should produce the same key
	k1 := sessionKey("1", "WA2M-2", "N3LLO-2")
	k2 := sessionKey("1", "N3LLO-2", "WA2M-2")
	if k1 != k2 {
		t.Errorf("Session keys should match: %q != %q", k1, k2)
	}

	// Verify the key format is "port-lower-higher"
	expected := "1-N3LLO-2-WA2M-2"
	if k1 != expected {
		t.Errorf("Expected key %q, got %q", expected, k1)
	}
}

func TestSessionKeyDifferentPorts(t *testing.T) {
	k1 := sessionKey("1", "WA2M-2", "N3LLO-2")
	k2 := sessionKey("2", "WA2M-2", "N3LLO-2")
	if k1 == k2 {
		t.Errorf("Session keys for different ports should differ: %q == %q", k1, k2)
	}
}

func TestSessionKeyCaseInsensitive(t *testing.T) {
	k1 := sessionKey("1", "wa2m-2", "n3llo-2")
	k2 := sessionKey("1", "WA2M-2", "N3LLO-2")
	if k1 != k2 {
		t.Errorf("Session keys should be case-insensitive: %q != %q", k1, k2)
	}
}

func TestLinkUpCreatesConnectedSession(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
		IsRF:      true,
	})

	sessions := tracker.GetSessions()
	if len(sessions) != 1 {
		t.Fatalf("Expected 1 session, got %d", len(sessions))
	}

	sess := sessions[0]
	if sess.State != SessionConnected {
		t.Errorf("Expected state Connected, got %s", sess.State)
	}
	if sess.Initiator != "WA2M-2" {
		t.Errorf("Expected initiator WA2M-2, got %s", sess.Initiator)
	}
	if sess.Responder != "N3LLO-2" {
		t.Errorf("Expected responder N3LLO-2, got %s", sess.Responder)
	}
	if sess.StartedAt == nil {
		t.Error("Expected StartedAt to be set")
	}
	if sess.Port != 1 {
		t.Errorf("Expected port 1, got %d", sess.Port)
	}

	// onChange should have been called
	if rec.count() == 0 {
		t.Error("Expected onChange to be called")
	}
}

func TestLinkUpIncomingDirection(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "incoming",
		Port:      "2",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
		IsRF:      true,
	})

	sess := tracker.GetSessions()[0]
	if sess.Initiator != "N3LLO-2" {
		t.Errorf("Expected initiator N3LLO-2 for incoming, got %s", sess.Initiator)
	}
	if sess.Responder != "WA2M-2" {
		t.Errorf("Expected responder WA2M-2 for incoming, got %s", sess.Responder)
	}
}

func TestLinkDownSetsDisconnected(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	// First connect
	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
		IsRF:      true,
	})

	// Then disconnect
	tracker.HandleLinkDown(&LinkDownEvent{
		Type:       "link_down",
		ID:         1,
		Direction:  "outgoing",
		Port:       "1",
		Remote:     "N3LLO-2",
		Local:      "WA2M-2",
		BytesSent:  1024,
		BytesRcvd:  2048,
		FrmsSent:   100,
		FrmsRcvd:   200,
		FrmsResent: 5,
		Reason:     "Normal",
		UpForSecs:  60,
		IsRF:       true,
	})

	sess := tracker.GetSession("1-N3LLO-2-WA2M-2")
	if sess == nil {
		t.Fatal("Expected to find session")
	}
	if sess.State != SessionDisconnected {
		t.Errorf("Expected state Disconnected, got %s", sess.State)
	}
	if sess.EndedAt == nil {
		t.Error("Expected EndedAt to be set")
	}
	if sess.BytesSent != 1024 {
		t.Errorf("Expected BytesSent 1024, got %d", sess.BytesSent)
	}
	if sess.BytesReceived != 2048 {
		t.Errorf("Expected BytesReceived 2048, got %d", sess.BytesReceived)
	}
	if sess.FramesResent != 5 {
		t.Errorf("Expected FramesResent 5, got %d", sess.FramesResent)
	}
	if sess.DisconnectReason != "Normal" {
		t.Errorf("Expected reason Normal, got %s", sess.DisconnectReason)
	}
}

func TestLinkDownWithoutPriorLinkUp(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkDown(&LinkDownEvent{
		Type:       "link_down",
		ID:         1,
		Direction:  "outgoing",
		Port:       "1",
		Remote:     "N3LLO-2",
		Local:      "WA2M-2",
		BytesSent:  500,
		BytesRcvd:  600,
		FrmsResent: 2,
		Reason:     "Timeout",
	})

	sess := tracker.GetSession("1-N3LLO-2-WA2M-2")
	if sess == nil {
		t.Fatal("Expected session to be created on link down")
	}
	if sess.State != SessionDisconnected {
		t.Errorf("Expected Disconnected, got %s", sess.State)
	}
}

func TestL2TraceIFrameCounting(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	// Create a connected session first
	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	// Sent I-frame
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    1,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      0,
		ILen:      100,
	})

	// Received I-frame
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    2,
		Direction: "rcvd",
		Port:      "1",
		Source:    "N3LLO-2",
		Dest:      "WA2M-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      0,
		ILen:      50,
	})

	// Another sent I-frame (different sequence number)
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    3,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      1,
		ILen:      100,
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess == nil {
		t.Fatal("Expected to find session")
	}
	if sess.IFramesSent != 2 {
		t.Errorf("Expected 2 I-frames sent, got %d", sess.IFramesSent)
	}
	if sess.IFramesReceived != 1 {
		t.Errorf("Expected 1 I-frame received, got %d", sess.IFramesReceived)
	}
	if sess.TotalFrames != 3 {
		t.Errorf("Expected 3 total frames, got %d", sess.TotalFrames)
	}
	if !sess.HasText {
		t.Error("Expected HasText to be true for PID 0xF0")
	}
}

func TestL2TraceRetryDetection(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	// First I-frame with N(S)=0
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    1,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      0,
	})

	// Duplicate N(S)=0 -> timeout retry (no prior REJ from other side)
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    2,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      0,
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess.RetryCount != 1 {
		t.Errorf("Expected 1 retry, got %d", sess.RetryCount)
	}
	if sess.TimeoutRetries != 1 {
		t.Errorf("Expected 1 timeout retry, got %d", sess.TimeoutRetries)
	}
	if sess.REJRetries != 0 {
		t.Errorf("Expected 0 REJ retries, got %d", sess.REJRetries)
	}
}

func TestL2TraceREJRetryDetection(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	// First I-frame with N(S)=0 from WA2M-2
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    1,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      0,
	})

	// REJ from N3LLO-2 (the other side)
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    2,
		Direction: "rcvd",
		Port:      "1",
		Source:    "N3LLO-2",
		Dest:      "WA2M-2",
		L2Type:    "REJ",
		PID:       0,
		TSeq:      0,
	})

	// Retry with same N(S)=0 from WA2M-2 (within 5 seconds of REJ)
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    3,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      0,
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess.RetryCount != 1 {
		t.Errorf("Expected 1 retry, got %d", sess.RetryCount)
	}
	if sess.REJRetries != 1 {
		t.Errorf("Expected 1 REJ retry, got %d", sess.REJRetries)
	}
	if sess.TimeoutRetries != 0 {
		t.Errorf("Expected 0 timeout retries, got %d", sess.TimeoutRetries)
	}
	if sess.REJCount != 1 {
		t.Errorf("Expected 1 REJ count, got %d", sess.REJCount)
	}
}

func TestL2TraceNetROMProtocolFlag(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    1,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xCF,
		TSeq:      0,
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if !sess.HasNetROM {
		t.Error("Expected HasNetROM to be true for PID 0xCF")
	}
}

func TestCircuitTracking(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	// Create a connected session with NetROM
	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	// Send a NetROM frame to set HasNetROM
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    1,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xCF,
		TSeq:      0,
	})

	// Circuit up
	tracker.HandleCircuitUp(&CircuitUpEvent{
		Type:      "circuit_up",
		ID:        42,
		Direction: "outgoing",
		Remote:    "N3LLO",
		Local:     "WA2M",
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess == nil {
		t.Fatal("Expected session")
	}
	if len(sess.Circuits) != 1 {
		t.Fatalf("Expected 1 circuit, got %d", len(sess.Circuits))
	}
	if sess.Circuits[0].ID != 42 {
		t.Errorf("Expected circuit ID 42, got %d", sess.Circuits[0].ID)
	}
	if sess.Circuits[0].State != "connected" {
		t.Errorf("Expected circuit state connected, got %s", sess.Circuits[0].State)
	}

	// Circuit down
	tracker.HandleCircuitDown(&CircuitDownEvent{
		Type:       "circuit_down",
		ID:         42,
		SegsSent:   100,
		SegsRcvd:   200,
		SegsResent: 3,
		Reason:     "Normal",
	})

	sess = tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess.Circuits[0].State != "disconnected" {
		t.Errorf("Expected circuit disconnected, got %s", sess.Circuits[0].State)
	}
	if sess.Circuits[0].SegsSent != 100 {
		t.Errorf("Expected SegsSent 100, got %d", sess.Circuits[0].SegsSent)
	}
}

func TestGetSessionsSorting(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	// Create session 1 and disconnect it
	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})
	tracker.HandleLinkDown(&LinkDownEvent{
		Type:      "link_down",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
		Reason:    "Normal",
	})

	// Small delay to ensure different timestamps
	time.Sleep(10 * time.Millisecond)

	// Create session 2 (stays connected)
	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        2,
		Direction: "outgoing",
		Port:      "2",
		Remote:    "KB2FAF-2",
		Local:     "WA2M-2",
	})

	sessions := tracker.GetSessions()
	if len(sessions) != 2 {
		t.Fatalf("Expected 2 sessions, got %d", len(sessions))
	}

	// Connected session should be first
	if sessions[0].State != SessionConnected {
		t.Errorf("Expected first session to be Connected, got %s", sessions[0].State)
	}
	if sessions[1].State != SessionDisconnected {
		t.Errorf("Expected second session to be Disconnected, got %s", sessions[1].State)
	}
}

func TestSessionPruning(t *testing.T) {
	rec := &changeRecorder{}
	maxSize := 5
	tracker := NewSessionTracker(maxSize, rec.record, testLogger())

	// Create maxSize+2 sessions, all disconnected
	for i := 0; i < maxSize+2; i++ {
		port := "1"
		remote := "CALL-" + string(rune('A'+i))
		tracker.HandleLinkUp(&LinkUpEvent{
			Type:      "link_up",
			ID:        i,
			Direction: "outgoing",
			Port:      port,
			Remote:    remote,
			Local:     "WA2M-2",
		})
		time.Sleep(2 * time.Millisecond) // Ensure different timestamps
		tracker.HandleLinkDown(&LinkDownEvent{
			Type:      "link_down",
			ID:        i,
			Direction: "outgoing",
			Port:      port,
			Remote:    remote,
			Local:     "WA2M-2",
			Reason:    "Test",
		})
		time.Sleep(2 * time.Millisecond)
	}

	sessions := tracker.GetSessions()
	if len(sessions) > maxSize {
		t.Errorf("Expected at most %d sessions after pruning, got %d", maxSize, len(sessions))
	}
}

func TestSessionPruningKeepsConnected(t *testing.T) {
	rec := &changeRecorder{}
	maxSize := 3
	tracker := NewSessionTracker(maxSize, rec.record, testLogger())

	// Create a connected session
	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "KEEP-1",
		Local:     "WA2M-2",
	})

	// Create maxSize+1 disconnected sessions to trigger pruning
	for i := 0; i < maxSize+1; i++ {
		remote := "DROP-" + string(rune('A'+i))
		tracker.HandleLinkUp(&LinkUpEvent{
			Type:      "link_up",
			ID:        100 + i,
			Direction: "outgoing",
			Port:      "2",
			Remote:    remote,
			Local:     "WA2M-2",
		})
		time.Sleep(2 * time.Millisecond)
		tracker.HandleLinkDown(&LinkDownEvent{
			Type:      "link_down",
			ID:        100 + i,
			Direction: "outgoing",
			Port:      "2",
			Remote:    remote,
			Local:     "WA2M-2",
			Reason:    "Test",
		})
		time.Sleep(2 * time.Millisecond)
	}

	// The connected session should still be present
	sess := tracker.GetSession("1-KEEP-1-WA2M-2")
	if sess == nil {
		t.Error("Expected connected session to survive pruning")
	}
	if sess != nil && sess.State != SessionConnected {
		t.Errorf("Expected connected session to remain Connected, got %s", sess.State)
	}
}

func TestRetryRate(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	// Send 10 I-frames with unique sequence numbers
	for i := 0; i < 10; i++ {
		tracker.HandleL2Trace(&L2TraceEvent{
			Type:      "l2_trace",
			Serial:    int64(i),
			Direction: "sent",
			Port:      "1",
			Source:    "WA2M-2",
			Dest:      "N3LLO-2",
			L2Type:    "I",
			PID:       0xF0,
			TSeq:      i,
		})
	}

	// Now retry the last one (duplicate N(S)=9)
	tracker.HandleL2Trace(&L2TraceEvent{
		Type:      "l2_trace",
		Serial:    10,
		Direction: "sent",
		Port:      "1",
		Source:    "WA2M-2",
		Dest:      "N3LLO-2",
		L2Type:    "I",
		PID:       0xF0,
		TSeq:      9,
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	// 11 sent I-frames, 0 received, 1 retry
	// RetryRate = 1/11 * 100 ~= 9.09
	if sess.RetryRate < 9.0 || sess.RetryRate > 9.2 {
		t.Errorf("Expected retry rate ~9.09%%, got %.2f%%", sess.RetryRate)
	}
}

func TestFindSessionForFrame(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type:      "link_up",
		ID:        1,
		Direction: "outgoing",
		Port:      "1",
		Remote:    "N3LLO-2",
		Local:     "WA2M-2",
	})

	// Find with same order
	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess == nil {
		t.Error("Expected to find session with original order")
	}

	// Find with reversed order
	sess = tracker.FindSessionForFrame(1, "N3LLO-2", "WA2M-2")
	if sess == nil {
		t.Error("Expected to find session with reversed order")
	}

	// Not found on different port
	sess = tracker.FindSessionForFrame(99, "WA2M-2", "N3LLO-2")
	if sess != nil {
		t.Error("Expected no session on different port")
	}
}

func TestLinkUpResetsSession(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	// Connect, send some frames, disconnect
	tracker.HandleLinkUp(&LinkUpEvent{
		Type: "link_up", ID: 1, Direction: "outgoing",
		Port: "1", Remote: "N3LLO-2", Local: "WA2M-2",
	})
	tracker.HandleL2Trace(&L2TraceEvent{
		Type: "l2_trace", Serial: 1, Direction: "sent",
		Port: "1", Source: "WA2M-2", Dest: "N3LLO-2",
		L2Type: "I", PID: 0xCF, TSeq: 0,
	})
	tracker.HandleLinkDown(&LinkDownEvent{
		Type: "link_down", ID: 1, Direction: "outgoing",
		Port: "1", Remote: "N3LLO-2", Local: "WA2M-2",
		BytesSent: 500, Reason: "Normal",
	})

	// Reconnect - should reset counters
	tracker.HandleLinkUp(&LinkUpEvent{
		Type: "link_up", ID: 2, Direction: "outgoing",
		Port: "1", Remote: "N3LLO-2", Local: "WA2M-2",
	})

	sess := tracker.FindSessionForFrame(1, "WA2M-2", "N3LLO-2")
	if sess.State != SessionConnected {
		t.Errorf("Expected Connected, got %s", sess.State)
	}
	if sess.IFramesSent != 0 {
		t.Errorf("Expected IFramesSent reset to 0, got %d", sess.IFramesSent)
	}
	if sess.BytesSent != 0 {
		t.Errorf("Expected BytesSent reset to 0, got %d", sess.BytesSent)
	}
	if sess.HasNetROM {
		t.Error("Expected HasNetROM reset to false")
	}
}

func TestNotifyDebouncing(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(200, rec.record, testLogger())

	tracker.HandleLinkUp(&LinkUpEvent{
		Type: "link_up", ID: 1, Direction: "outgoing",
		Port: "1", Remote: "N3LLO-2", Local: "WA2M-2",
	})

	initialCount := rec.count()

	// Send many trace events rapidly - most should be debounced
	for i := 0; i < 20; i++ {
		tracker.HandleL2Trace(&L2TraceEvent{
			Type: "l2_trace", Serial: int64(i), Direction: "sent",
			Port: "1", Source: "WA2M-2", Dest: "N3LLO-2",
			L2Type: "I", PID: 0xF0, TSeq: i,
		})
	}

	// We should have far fewer than 20 additional notifications due to debouncing
	totalNotifications := rec.count()
	additionalNotifications := totalNotifications - initialCount
	if additionalNotifications > 5 {
		t.Errorf("Expected debounced notifications (<= 5), got %d additional", additionalNotifications)
	}
}

func TestL2TraceUIFramesIgnored(t *testing.T) {
	rec := &changeRecorder{}
	tracker := NewSessionTracker(100, rec.record, testLogger())

	// Send UI frames (broadcasts like ID beacons, CQ, TNC info)
	tracker.HandleL2Trace(&L2TraceEvent{
		Type: "l2_trace", Serial: 1, Direction: "sent",
		Port: "1", Source: "WA2M-2", Dest: "ID",
		L2Type: "UI", PID: 0xFF,
	})
	tracker.HandleL2Trace(&L2TraceEvent{
		Type: "l2_trace", Serial: 2, Direction: "sent",
		Port: "1", Source: "WA2M-2", Dest: "CQ",
		L2Type: "UI", PID: 0xFF,
	})
	tracker.HandleL2Trace(&L2TraceEvent{
		Type: "l2_trace", Serial: 3, Direction: "rcvd",
		Port: "1", Source: "N3LLO-2", Dest: "CQ",
		L2Type: "UI", PID: 0xFF,
	})

	sessions := tracker.GetSessions()
	if len(sessions) != 0 {
		t.Errorf("Expected 0 sessions from UI frames, got %d", len(sessions))
	}
	if rec.count() != 0 {
		t.Errorf("Expected 0 change notifications from UI frames, got %d", rec.count())
	}
}
