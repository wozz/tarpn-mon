package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.uber.org/zap"
)

type SessionState string

const (
	SessionDisconnected  SessionState = "disconnected"
	SessionConnecting    SessionState = "connecting"
	SessionConnected     SessionState = "connected"
	SessionDisconnecting SessionState = "disconnecting"
)

type Session struct {
	ID               string       `json:"id"`
	Port             int          `json:"port"`
	Initiator        string       `json:"initiator"`
	Responder        string       `json:"responder"`
	State            SessionState `json:"state"`
	StartedAt        *time.Time   `json:"startedAt,omitempty"`
	EndedAt          *time.Time   `json:"endedAt,omitempty"`
	LastActivity     time.Time    `json:"lastActivity"`
	IFramesSent      int          `json:"iFramesSent"`
	IFramesReceived  int          `json:"iFramesReceived"`
	TotalFrames      int          `json:"totalFrames"`
	RetryCount       int          `json:"retryCount"`
	REJCount         int          `json:"rejCount"`
	TimeoutRetries   int          `json:"timeoutRetries"`
	REJRetries       int          `json:"rejRetries"`
	RetryRate        float64      `json:"retryRate"`
	BytesSent        int64        `json:"bytesSent"`
	BytesReceived    int64        `json:"bytesReceived"`
	FramesResent     int64        `json:"framesResent"`
	DisconnectReason string       `json:"disconnectReason,omitempty"`
	HasNetROM        bool         `json:"hasNetROM"`
	HasIP            bool         `json:"hasIP"`
	HasText          bool         `json:"hasText"`
	Circuits         []Circuit    `json:"circuits,omitempty"`
}

type Circuit struct {
	ID         int    `json:"id"`
	Direction  string `json:"direction"`
	Remote     string `json:"remote"`
	Local      string `json:"local"`
	State      string `json:"state"`
	SegsSent   int64  `json:"segsSent"`
	SegsRcvd   int64  `json:"segsRcvd"`
	SegsResent int64  `json:"segsResent"`
}

type SessionTracker struct {
	mu             sync.RWMutex
	sessions       map[string]*Session
	circuits       map[int]*Circuit
	circuitSession map[int]string
	ordered        []*Session
	maxSize        int
	onChange       func(*Session)
	lastNS         map[string]int
	lastREJ        map[string]time.Time
	lastNotify     map[string]time.Time
	logger         *zap.SugaredLogger
}

func NewSessionTracker(maxSize int, onChange func(*Session), logger *zap.SugaredLogger) *SessionTracker {
	return &SessionTracker{
		sessions:       make(map[string]*Session),
		circuits:       make(map[int]*Circuit),
		circuitSession: make(map[int]string),
		maxSize:        maxSize,
		onChange:        onChange,
		lastNS:         make(map[string]int),
		lastREJ:        make(map[string]time.Time),
		lastNotify:     make(map[string]time.Time),
		logger:         logger,
	}
}

// sessionKey produces a normalized key from a port and two station callsigns.
// It sorts the callsigns alphabetically so that A>B and B>A map to the same session.
func sessionKey(port string, station1, station2 string) string {
	p, err := strconv.Atoi(port)
	if err != nil {
		p = 0
	}
	s1 := strings.ToUpper(strings.TrimSpace(station1))
	s2 := strings.ToUpper(strings.TrimSpace(station2))
	if s1 > s2 {
		s1, s2 = s2, s1
	}
	return fmt.Sprintf("%d-%s-%s", p, s1, s2)
}

func (st *SessionTracker) HandleLinkUp(event *LinkUpEvent) {
	st.mu.Lock()
	defer st.mu.Unlock()

	key := sessionKey(event.Port, event.Remote, event.Local)
	now := time.Now()

	sess, exists := st.sessions[key]
	if !exists {
		sess = &Session{
			ID: key,
		}
		st.sessions[key] = sess
	}

	// Parse port
	p, _ := strconv.Atoi(event.Port)
	sess.Port = p

	// Set initiator/responder based on direction
	if event.Direction == "outgoing" {
		sess.Initiator = event.Local
		sess.Responder = event.Remote
	} else {
		sess.Initiator = event.Remote
		sess.Responder = event.Local
	}

	sess.State = SessionConnected
	sess.StartedAt = &now
	sess.EndedAt = nil
	sess.LastActivity = now
	sess.DisconnectReason = ""

	// Reset counters for the new session
	sess.IFramesSent = 0
	sess.IFramesReceived = 0
	sess.TotalFrames = 0
	sess.RetryCount = 0
	sess.REJCount = 0
	sess.TimeoutRetries = 0
	sess.REJRetries = 0
	sess.RetryRate = 0
	sess.BytesSent = 0
	sess.BytesReceived = 0
	sess.FramesResent = 0
	sess.HasNetROM = false
	sess.HasIP = false
	sess.HasText = false
	sess.Circuits = nil

	// Clear per-session tracking state
	st.clearSessionNS(key)

	st.rebuildOrdered()
	st.logger.Debugw("Session connected", "id", key, "initiator", sess.Initiator, "responder", sess.Responder)
	st.notifyChangeLocked(sess, true)
}

func (st *SessionTracker) HandleLinkDown(event *LinkDownEvent) {
	st.mu.Lock()
	defer st.mu.Unlock()

	key := sessionKey(event.Port, event.Remote, event.Local)
	sess, exists := st.sessions[key]
	if !exists {
		// We may receive a down for a session we never saw come up; create it
		sess = &Session{
			ID: key,
		}
		p, _ := strconv.Atoi(event.Port)
		sess.Port = p
		if event.Direction == "outgoing" {
			sess.Initiator = event.Local
			sess.Responder = event.Remote
		} else {
			sess.Initiator = event.Remote
			sess.Responder = event.Local
		}
		st.sessions[key] = sess
	}

	now := time.Now()
	sess.State = SessionDisconnected
	sess.EndedAt = &now
	sess.LastActivity = now
	sess.BytesSent = event.BytesSent
	sess.BytesReceived = event.BytesRcvd
	sess.FramesResent = event.FrmsResent
	sess.DisconnectReason = event.Reason

	st.clearSessionNS(key)
	st.rebuildOrdered()
	st.logger.Debugw("Session disconnected", "id", key, "reason", event.Reason)
	st.notifyChangeLocked(sess, true)
	st.pruneOldSessions()
}

func (st *SessionTracker) HandleL2Trace(event *L2TraceEvent) {
	st.mu.Lock()
	defer st.mu.Unlock()

	key := sessionKey(event.Port, event.Source, event.Dest)

	portNum, _ := strconv.Atoi(event.Port)
	sess, exists := st.sessions[key]
	if !exists {
		sess = &Session{
			ID:    key,
			Port:  portNum,
			State: SessionConnecting,
		}
		// We don't know direction from a trace alone, assign alphabetically
		s1 := strings.ToUpper(event.Source)
		s2 := strings.ToUpper(event.Dest)
		if s1 < s2 {
			sess.Initiator = s1
			sess.Responder = s2
		} else {
			sess.Initiator = s2
			sess.Responder = s1
		}
		st.sessions[key] = sess
		st.rebuildOrdered()
	}

	now := time.Now()
	sess.LastActivity = now
	sess.TotalFrames++
	stateChange := false

	// Handle connect request -> session connecting
	// LinBPQ sends "C" for SABM (connect), "SABME" for extended connect
	if event.L2Type == "C" || event.L2Type == "SABME" {
		if sess.State == SessionDisconnected || sess.State == SessionConnecting {
			sess.State = SessionConnecting
			stateChange = true
		}
	}

	// Handle UA after connect request -> connected
	if event.L2Type == "UA" {
		if sess.State == SessionConnecting {
			sess.State = SessionConnected
			t := now
			sess.StartedAt = &t
			stateChange = true
		}
	}

	// Handle disconnect request -> disconnecting
	// LinBPQ sends "D" for DISC
	if event.L2Type == "D" {
		if sess.State == SessionConnected {
			sess.State = SessionDisconnecting
			stateChange = true
		}
	}

	// Handle DM -> disconnected
	if event.L2Type == "DM" {
		if sess.State != SessionDisconnected {
			sess.State = SessionDisconnected
			t := now
			sess.EndedAt = &t
			stateChange = true
		}
	}

	// I-frame handling
	if event.L2Type == "I" {
		if event.Direction == "sent" {
			sess.IFramesSent++
		} else {
			sess.IFramesReceived++
		}

		// Retry detection via duplicate N(S)
		nsKey := fmt.Sprintf("%s-%s", key, event.Source)
		lastNS, tracked := st.lastNS[nsKey]
		if tracked && event.TSeq == lastNS {
			// Duplicate N(S) means a retry
			sess.RetryCount++

			// Classify: check if the other side sent a REJ within 5 seconds
			otherStation := event.Dest
			rejKey := fmt.Sprintf("%s-%s", key, otherStation)
			if rejTime, ok := st.lastREJ[rejKey]; ok && now.Sub(rejTime) < 5*time.Second {
				sess.REJRetries++
			} else {
				sess.TimeoutRetries++
			}

			st.updateRetryRate(sess)
		}
		st.lastNS[nsKey] = event.TSeq
	}

	// REJ tracking
	if event.L2Type == "REJ" {
		sess.REJCount++
		rejKey := fmt.Sprintf("%s-%s", key, event.Source)
		st.lastREJ[rejKey] = now
	}

	// Protocol flags from PID
	if event.PID == 0xCF {
		sess.HasNetROM = true
	}
	if event.PID == 0xF0 {
		sess.HasText = true
	}

	st.notifyChangeLocked(sess, stateChange)
}

func (st *SessionTracker) HandleCircuitUp(event *CircuitUpEvent) {
	st.mu.Lock()
	defer st.mu.Unlock()

	circuit := &Circuit{
		ID:        event.ID,
		Direction: event.Direction,
		Remote:    event.Remote,
		Local:     event.Local,
		State:     "connected",
	}
	st.circuits[event.ID] = circuit

	// Find the most recent connected session with NetROM
	var bestSession *Session
	var bestTime time.Time
	for _, sess := range st.sessions {
		if sess.State == SessionConnected && sess.HasNetROM {
			if bestSession == nil || sess.LastActivity.After(bestTime) {
				bestSession = sess
				bestTime = sess.LastActivity
			}
		}
	}

	if bestSession != nil {
		bestSession.Circuits = append(bestSession.Circuits, *circuit)
		st.circuitSession[event.ID] = bestSession.ID
		st.logger.Debugw("Circuit attached to session", "circuitID", event.ID, "sessionID", bestSession.ID)
		st.notifyChangeLocked(bestSession, true)
	} else {
		st.logger.Debugw("Circuit up but no matching session found", "circuitID", event.ID)
	}
}

func (st *SessionTracker) HandleCircuitDown(event *CircuitDownEvent) {
	st.mu.Lock()
	defer st.mu.Unlock()

	circuit, exists := st.circuits[event.ID]
	if !exists {
		st.logger.Debugw("Circuit down for unknown circuit", "circuitID", event.ID)
		return
	}

	circuit.State = "disconnected"
	circuit.SegsSent = event.SegsSent
	circuit.SegsRcvd = event.SegsRcvd
	circuit.SegsResent = event.SegsResent

	// Update the circuit in its parent session
	sessID, hasSess := st.circuitSession[event.ID]
	if hasSess {
		if sess, ok := st.sessions[sessID]; ok {
			for i := range sess.Circuits {
				if sess.Circuits[i].ID == event.ID {
					sess.Circuits[i].State = "disconnected"
					sess.Circuits[i].SegsSent = event.SegsSent
					sess.Circuits[i].SegsRcvd = event.SegsRcvd
					sess.Circuits[i].SegsResent = event.SegsResent
					break
				}
			}
			st.notifyChangeLocked(sess, true)
		}
	}
}

func (st *SessionTracker) GetSessions() []*Session {
	st.mu.RLock()
	defer st.mu.RUnlock()

	result := make([]*Session, len(st.ordered))
	copy(result, st.ordered)
	return result
}

func (st *SessionTracker) GetSession(id string) *Session {
	st.mu.RLock()
	defer st.mu.RUnlock()

	sess, exists := st.sessions[id]
	if !exists {
		return nil
	}
	return sess
}

func (st *SessionTracker) FindSessionForFrame(port int, source, dest string) *Session {
	st.mu.RLock()
	defer st.mu.RUnlock()

	key := sessionKey(strconv.Itoa(port), source, dest)
	sess, exists := st.sessions[key]
	if !exists {
		return nil
	}
	return sess
}

// notifyChangeLocked calls onChange. If stateChange is true, calls immediately.
// Otherwise debounces to at most once per second per session.
// Must be called with st.mu held.
func (st *SessionTracker) notifyChangeLocked(session *Session, stateChange bool) {
	if st.onChange == nil {
		return
	}

	if stateChange {
		st.lastNotify[session.ID] = time.Now()
		st.onChange(session)
		return
	}

	last, ok := st.lastNotify[session.ID]
	if !ok || time.Since(last) >= time.Second {
		st.lastNotify[session.ID] = time.Now()
		st.onChange(session)
	}
}

func (st *SessionTracker) updateRetryRate(sess *Session) {
	total := sess.IFramesSent + sess.IFramesReceived
	if total > 0 {
		sess.RetryRate = float64(sess.RetryCount) / float64(total) * 100
	}
}

// rebuildOrdered rebuilds the sorted ordered slice.
// Connected sessions first, then sorted by LastActivity descending.
// Must be called with st.mu held.
func (st *SessionTracker) rebuildOrdered() {
	st.ordered = make([]*Session, 0, len(st.sessions))
	for _, s := range st.sessions {
		st.ordered = append(st.ordered, s)
	}
	sort.Slice(st.ordered, func(i, j int) bool {
		si := st.ordered[i]
		sj := st.ordered[j]
		// Connected sessions come first
		iConn := si.State == SessionConnected || si.State == SessionConnecting
		jConn := sj.State == SessionConnected || sj.State == SessionConnecting
		if iConn != jConn {
			return iConn
		}
		// Then by last activity, most recent first
		return si.LastActivity.After(sj.LastActivity)
	})
}

// clearSessionNS removes lastNS and lastREJ entries for a given session key.
func (st *SessionTracker) clearSessionNS(sessionKey string) {
	prefix := sessionKey + "-"
	for k := range st.lastNS {
		if strings.HasPrefix(k, prefix) {
			delete(st.lastNS, k)
		}
	}
	for k := range st.lastREJ {
		if strings.HasPrefix(k, prefix) {
			delete(st.lastREJ, k)
		}
	}
}

// pruneOldSessions removes the oldest disconnected sessions if we exceed maxSize.
func (st *SessionTracker) pruneOldSessions() {
	if len(st.sessions) <= st.maxSize {
		return
	}

	// Collect disconnected sessions sorted by LastActivity (oldest first)
	var disconnected []*Session
	for _, s := range st.sessions {
		if s.State == SessionDisconnected {
			disconnected = append(disconnected, s)
		}
	}
	sort.Slice(disconnected, func(i, j int) bool {
		return disconnected[i].LastActivity.Before(disconnected[j].LastActivity)
	})

	toRemove := len(st.sessions) - st.maxSize
	for i := 0; i < toRemove && i < len(disconnected); i++ {
		id := disconnected[i].ID
		delete(st.sessions, id)
		delete(st.lastNotify, id)
		st.clearSessionNS(id)
		st.logger.Debugw("Pruned old session", "id", id)
	}

	st.rebuildOrdered()
}
