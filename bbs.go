package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// BBSMessage represents a message in the BBS
type BBSMessage struct {
	Number  int    `json:"number"`
	Type    string `json:"type"`    // P (Personal), B (Bulletin), T (Traffic)
	Status  string `json:"status"`  // N (New), Y (Read), F (Forwarded), K (Killed), H (Held), D (Delivered)
	Date    string `json:"date"`
	From    string `json:"from"`
	Size    int    `json:"size"`
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body,omitempty"`
	Headers string `json:"headers,omitempty"`
}

// BBSClientMessage represents a message sent to WebSocket clients
type BBSClientMessage struct {
	Seq       int64        `json:"seq"`
	Type      string       `json:"type"` // "bbs_list", "bbs_message", "bbs_sent", "bbs_status", "bbs_error", "bbs_output"
	Messages  []BBSMessage `json:"messages,omitempty"`
	Message   *BBSMessage  `json:"message,omitempty"`
	Number    int          `json:"number,omitempty"`
	Connected bool         `json:"connected,omitempty"`
	InBBSMode bool         `json:"inBBSMode,omitempty"`
	Output    string       `json:"output,omitempty"`
	Error     string       `json:"error,omitempty"`
}

// BBSClient manages the connection to the BPQ BBS
type BBSClient struct {
	// messageSeq must be first for 64-bit alignment on 32-bit ARM
	messageSeq int64

	hostname  string
	port      int
	callsign  string
	password  string

	conn      net.Conn
	reader    *bufio.Reader
	state     FeatureState
	inBBSMode bool
	mu        sync.RWMutex

	// Dynamic connection state
	connectedAt *time.Time
	lastError   string

	messages   []BBSMessage
	messagesMu sync.RWMutex

	ctx    context.Context
	cancel context.CancelFunc

	// Pending read state - Run() uses this to know when to parse message content
	pendingReadMsgNum int

	// Response handling
	responseChan  chan string
	responseLines []string
	responseMu    sync.Mutex
}

// BBSClientConfig holds configuration for creating a BBS client
type BBSClientConfig struct {
	Hostname string
	Port     int
	Callsign string
	Password string
}

var (
	bbsClient    *BBSClient
	bbsManager   *BBSClient // Alias for feature manager interface
	bbsClientsMu sync.RWMutex
	bbsClients   = make(map[*websocketConn]bool)
)

// NewBBSClient creates a new BBS client
func NewBBSClient(cfg BBSClientConfig) *BBSClient {
	ctx, cancel := context.WithCancel(context.Background())
	return &BBSClient{
		hostname:     cfg.Hostname,
		port:         cfg.Port,
		callsign:     cfg.Callsign,
		password:     cfg.Password,
		state:        StateDisconnected,
		messages:     make([]BBSMessage, 0),
		ctx:          ctx,
		cancel:       cancel,
		responseChan: make(chan string, 100),
	}
}

// NewBBSClientWithConfig creates a new BBS client from FeatureConfig
func NewBBSClientWithConfig(config FeatureConfig) *BBSClient {
	return NewBBSClient(BBSClientConfig{
		Hostname: config.Host,
		Port:     config.Port,
		Callsign: config.Callsign,
		Password: config.Password,
	})
}

// Connect establishes connection to the BPQ node
func (b *BBSClient) Connect() error {
	addr := fmt.Sprintf("%s:%d", b.hostname, b.port)
	bbsLog.Infow("Connecting", "addr", addr, "callsign", b.callsign)

	b.mu.Lock()
	b.state = StateConnecting
	b.lastError = ""
	b.mu.Unlock()
	b.broadcastStatus()
	BroadcastFeatureStatus(b.GetStatus())

	conn, err := net.DialTimeout("tcp", addr, 30*time.Second)
	if err != nil {
		bbsLog.Errorf("TCP connection failed to %s: %v", addr, err)
		b.mu.Lock()
		b.state = StateError
		b.lastError = fmt.Sprintf("failed to connect to BBS server: %v", err)
		b.mu.Unlock()
		b.broadcastStatus()
		BroadcastFeatureStatus(b.GetStatus())
		return fmt.Errorf("failed to connect to BBS server: %w", err)
	}
	bbsLog.Debugf("TCP connection established to %s", addr)

	b.mu.Lock()
	b.conn = conn
	b.reader = bufio.NewReader(conn)
	b.mu.Unlock()

	// Initialize the connection (authenticate)
	bbsLog.Debugf("Starting authentication sequence")
	if err := b.initConnection(); err != nil {
		bbsLog.Errorf("Authentication/init failed: %v", err)
		conn.Close()
		b.mu.Lock()
		b.state = StateError
		b.lastError = err.Error()
		b.conn = nil
		b.mu.Unlock()
		b.broadcastStatus()
		BroadcastFeatureStatus(b.GetStatus())
		return err
	}
	bbsLog.Infof("Connected to node successfully")

	now := time.Now()
	b.mu.Lock()
	b.state = StateConnected
	b.connectedAt = &now
	b.lastError = ""
	b.mu.Unlock()

	// Broadcast connection status
	b.broadcastStatus()
	BroadcastFeatureStatus(b.GetStatus())

	return nil
}

// ConnectWithConfig connects using a FeatureConfig
func (b *BBSClient) ConnectWithConfig(config FeatureConfig) error {
	b.mu.Lock()
	b.hostname = config.Host
	b.port = config.Port
	b.callsign = config.Callsign
	b.password = config.Password
	b.mu.Unlock()

	return b.Connect()
}

// initConnection sends the initial authentication and enters BBS mode
// Flow: telnet negotiation -> auth -> CTEXT -> send BBS command -> BBS mode
func (b *BBSClient) initConnection() error {
	// Create telnet connection wrapper - handles IAC negotiation
	tc, err := NewTelnetConn(b.conn, 2*time.Second, bbsLog)
	if err != nil {
		return fmt.Errorf("telnet negotiation failed: %w", err)
	}

	// Use the telnet connection's reader
	b.reader = tc.Reader()

	// Authenticate using standard telnet protocol (waits for prompts)
	bbsLog.Debugf("Starting authentication")
	_, err = tc.Authenticate(b.callsign, b.password, 5*time.Second)
	if err != nil {
		return fmt.Errorf("authentication failed: %w", err)
	}

	// Now automatically enter BBS mode
	bbsLog.Debugf("Auth successful, sending BBS command")
	if err := tc.WriteCommand("BBS"); err != nil {
		return fmt.Errorf("failed to send BBS command: %w", err)
	}

	// Wait for BBS prompt/SID
	bbsLog.Debugf("Waiting for BBS prompt (15s timeout)")
	_, found, err := tc.ReadUntil(func(line string) bool {
		// Check for BBS SID like [LinBPQ-6.0.24.1-B2FHIM$]
		if strings.HasPrefix(line, "[") && strings.Contains(line, "BPQ") {
			bbsLog.Debugf("BBS SID detected: %q", line)
			return true
		}
		// Check for BBS prompt (CALL:NODENAME>)
		if strings.Contains(line, ":") && strings.HasSuffix(line, ">") {
			bbsLog.Debugf("BBS prompt detected: %q", line)
			return true
		}
		return false
	}, 15*time.Second)

	if err != nil {
		return fmt.Errorf("error waiting for BBS prompt: %w", err)
	}

	// Even if no prompt found, if we sent BBS command, try to continue
	b.mu.Lock()
	b.inBBSMode = true
	b.mu.Unlock()
	b.conn.SetReadDeadline(time.Time{})

	if found {
		bbsLog.Infof("Entered BBS mode successfully")
	} else {
		bbsLog.Debugf("BBS prompt timeout, continuing anyway")
	}

	return nil
}

// EnterBBS enters BBS mode from the node prompt
func (b *BBSClient) EnterBBS() error {
	bbsLog.Debugf("Entering BBS mode")
	b.mu.Lock()
	if b.state != StateConnected || b.conn == nil {
		b.mu.Unlock()
		bbsLog.Errorf("Cannot enter BBS mode: not connected")
		return fmt.Errorf("not connected to node")
	}
	conn := b.conn
	b.mu.Unlock()

	// Send BBS command (using CRLF for telnet standard)
	bbsLog.Debugf("Sending BBS command")
	if _, err := conn.Write([]byte("BBS\r\n")); err != nil {
		return fmt.Errorf("failed to send BBS command: %w", err)
	}

	// Wait for BBS prompt
	bbsLog.Debugf("Waiting for BBS prompt (10s timeout)")
	timeout := time.After(10 * time.Second)
	for {
		select {
		case <-timeout:
			bbsLog.Errorf("Timeout waiting for BBS prompt after 10s")
			return fmt.Errorf("timeout waiting for BBS prompt")
		default:
			b.conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			line, err := b.reader.ReadString('\n')
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					bbsLog.Debugf("Read timeout, continuing to wait...")
					continue
				}
				bbsLog.Debugf("Read error (non-timeout): %v", err)
				continue
			}

			line = strings.TrimSpace(line)
			bbsLog.Debugf("Received: %q", line)

			// Check for BBS SID like [LinBPQ-6.0.24.1-B2FHIM$]
			if strings.HasPrefix(line, "[") && strings.Contains(line, "BPQ") {
				bbsLog.Debugf("BBS SID detected: %q", line)
				b.mu.Lock()
				b.inBBSMode = true
				b.mu.Unlock()
				b.conn.SetReadDeadline(time.Time{})
				b.broadcastStatus()
				bbsLog.Infof("Entered BBS mode successfully")
				return nil
			}

			// Check for BBS prompt
			if strings.Contains(line, ":") && strings.HasSuffix(line, ">") {
				bbsLog.Debugf("BBS prompt detected: %q", line)
				b.mu.Lock()
				b.inBBSMode = true
				b.mu.Unlock()
				b.conn.SetReadDeadline(time.Time{})
				b.broadcastStatus()
				bbsLog.Infof("Entered BBS mode successfully")
				return nil
			}
		}
	}
}

// ExitBBS exits BBS mode back to node prompt
func (b *BBSClient) ExitBBS() error {
	b.mu.Lock()
	if b.state != StateConnected || b.conn == nil {
		b.mu.Unlock()
		return fmt.Errorf("not connected")
	}
	conn := b.conn
	b.mu.Unlock()

	// Send NODE command to return to node (using CRLF for telnet standard)
	if _, err := conn.Write([]byte("NODE\r\n")); err != nil {
		return fmt.Errorf("failed to send NODE command: %w", err)
	}

	b.mu.Lock()
	b.inBBSMode = false
	b.mu.Unlock()

	b.broadcastStatus()
	return nil
}

// ListMessages sends a list command - Run() will handle the response
// This is now async - it just sends the command and returns immediately
func (b *BBSClient) ListMessages(listType string) ([]BBSMessage, error) {
	b.mu.RLock()
	if b.state != StateConnected || !b.inBBSMode {
		b.mu.RUnlock()
		return nil, fmt.Errorf("not in BBS mode")
	}
	conn := b.conn
	if conn == nil {
		b.mu.RUnlock()
		return nil, fmt.Errorf("connection is nil")
	}
	b.mu.RUnlock()

	// Default to LM (list mine) if no type specified
	cmd := "LM"
	if listType != "" {
		cmd = listType
	}

	bbsLog.Debugf("Sending list command: %s", cmd)

	// Send list command - Run() will parse the response and broadcast
	// Using CRLF for telnet standard
	if _, err := conn.Write([]byte(cmd + "\r\n")); err != nil {
		return nil, fmt.Errorf("failed to send list command: %w", err)
	}

	// Return empty - the actual list will come through Run() -> broadcastMessageList
	return nil, nil
}

// parseMessageLine parses a message list line
// LinBPQ format: "307    13-Sep PN     173 SYSOP          SYSTEM Housekeeping Results"
// Fields: Msg# Date TS Size From To Subject
func (b *BBSClient) parseMessageLine(line string) *BBSMessage {
	if len(line) < 20 {
		return nil
	}

	// LinBPQ BBS format: Msg# Date TS Size From To Subject
	// Example: "307    13-Sep PN     173 SYSOP          SYSTEM Housekeeping Results"
	re := regexp.MustCompile(`^\s*(\d+)\s+(\d+-\S+)\s+([PBT])([NYFKHD$])\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$`)
	matches := re.FindStringSubmatch(line)

	if len(matches) >= 9 {
		num, _ := strconv.Atoi(matches[1])
		size, _ := strconv.Atoi(matches[5])
		return &BBSMessage{
			Number:  num,
			Date:    matches[2],
			Type:    matches[3],
			Status:  matches[4],
			Size:    size,
			From:    matches[6],
			To:      matches[7],
			Subject: matches[8],
		}
	}

	// Try alternate format with different date (e.g., "Jan 01" instead of "13-Sep")
	re2 := regexp.MustCompile(`^\s*(\d+)\s+(\S+\s+\d+)\s+([PBT])([NYFKHD$])\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$`)
	matches2 := re2.FindStringSubmatch(line)
	if len(matches2) >= 9 {
		num, _ := strconv.Atoi(matches2[1])
		size, _ := strconv.Atoi(matches2[5])
		return &BBSMessage{
			Number:  num,
			Date:    matches2[2],
			Type:    matches2[3],
			Status:  matches2[4],
			Size:    size,
			From:    matches2[6],
			To:      matches2[7],
			Subject: matches2[8],
		}
	}

	// Fallback: simpler pattern to at least capture number and type/status
	re3 := regexp.MustCompile(`^\s*(\d+)\s+\S+\s+([PBT])([NYFKHD$])\s+(.*)`)
	matches3 := re3.FindStringSubmatch(line)
	if len(matches3) >= 5 {
		num, _ := strconv.Atoi(matches3[1])
		return &BBSMessage{
			Number:  num,
			Type:    matches3[2],
			Status:  matches3[3],
			Subject: matches3[4],
		}
	}

	return nil
}

// ReadMessage sends a read command - Run() will handle the response
func (b *BBSClient) ReadMessage(msgNum int) (*BBSMessage, error) {
	b.mu.Lock()
	if b.state != StateConnected || !b.inBBSMode {
		b.mu.Unlock()
		return nil, fmt.Errorf("not in BBS mode")
	}
	conn := b.conn
	if conn == nil {
		b.mu.Unlock()
		return nil, fmt.Errorf("connection is nil")
	}
	// Set the pending read message number so Run() knows to parse message content
	b.pendingReadMsgNum = msgNum
	b.mu.Unlock()

	// Send read command (using CRLF for telnet standard)
	cmd := fmt.Sprintf("R %d", msgNum)
	bbsLog.Debugf("Sending read command: %s", cmd)
	if _, err := conn.Write([]byte(cmd + "\r\n")); err != nil {
		b.mu.Lock()
		b.pendingReadMsgNum = 0
		b.mu.Unlock()
		return nil, fmt.Errorf("failed to send read command: %w", err)
	}

	// Response will come through Run() -> broadcastReadMessage
	return nil, nil
}

// SendMessage sends a new message - sends all data in one burst
// LinBPQ buffers incoming data and processes line by line, so we can send
// the entire message at once without waiting for prompts
func (b *BBSClient) SendMessage(to, subject, body string, isBulletin bool) (int, error) {
	b.mu.RLock()
	if b.state != StateConnected || !b.inBBSMode {
		b.mu.RUnlock()
		return 0, fmt.Errorf("not in BBS mode")
	}
	conn := b.conn
	if conn == nil {
		b.mu.RUnlock()
		return 0, fmt.Errorf("connection is nil")
	}
	b.mu.RUnlock()

	// Determine command
	cmd := "SP " + to // Private message
	if isBulletin {
		cmd = "SB " + to // Bulletin
	}

	// Build the complete message as a single buffer
	// Format: SP/SB CALL\r\nSubject\r\nBody Line 1\r\n...\r\n/EX\r\n
	// Using \r\n (CRLF) which is standard for telnet protocol
	var buf strings.Builder
	buf.WriteString(cmd)
	buf.WriteString("\r\n")
	buf.WriteString(subject)
	buf.WriteString("\r\n")

	// Add body lines
	lines := strings.Split(body, "\n")
	for _, line := range lines {
		line = strings.TrimRight(line, "\r")
		buf.WriteString(line)
		buf.WriteString("\r\n")
	}

	// Add termination
	buf.WriteString("/EX\r\n")

	bbsLog.Debugf("Sending complete message in one burst: %s to %s, %d body lines", cmd, to, len(lines))

	// Send everything at once
	if _, err := conn.Write([]byte(buf.String())); err != nil {
		return 0, fmt.Errorf("failed to send message: %w", err)
	}

	// Run() will handle the response and broadcast confirmation
	return 0, nil
}

// DeleteMessage deletes a message by number - async, Run() handles response
func (b *BBSClient) DeleteMessage(msgNum int) error {
	b.mu.RLock()
	if b.state != StateConnected || !b.inBBSMode {
		b.mu.RUnlock()
		return fmt.Errorf("not in BBS mode")
	}
	conn := b.conn
	if conn == nil {
		b.mu.RUnlock()
		return fmt.Errorf("connection is nil")
	}
	b.mu.RUnlock()

	// Send kill command (using CRLF for telnet standard)
	cmd := fmt.Sprintf("K %d", msgNum)
	bbsLog.Debugf("Sending delete command: %s", cmd)
	if _, err := conn.Write([]byte(cmd + "\r\n")); err != nil {
		return fmt.Errorf("failed to send delete command: %w", err)
	}

	// Run() will handle the response
	return nil
}

// IsConnected returns connection status
func (b *BBSClient) IsConnected() bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.state == StateConnected
}

// GetStatus returns the current feature status for the BBS client
func (b *BBSClient) GetStatus() FeatureStatus {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return FeatureStatus{
		Type:        "feature_status",
		Feature:     "bbs",
		State:       b.state,
		Callsign:    b.callsign,
		Host:        b.hostname,
		Port:        b.port,
		Error:       b.lastError,
		ConnectedAt: b.connectedAt,
	}
}

// Disconnect gracefully disconnects the BBS client
func (b *BBSClient) Disconnect() error {
	b.mu.Lock()
	if b.state == StateDisconnected {
		b.mu.Unlock()
		return nil
	}
	b.state = StateDisconnecting
	b.mu.Unlock()
	BroadcastFeatureStatus(b.GetStatus())

	b.Close()

	b.mu.Lock()
	b.state = StateDisconnected
	b.connectedAt = nil
	b.mu.Unlock()
	b.broadcastStatus()
	BroadcastFeatureStatus(b.GetStatus())

	return nil
}

// IsInBBSMode returns whether we're in BBS mode
func (b *BBSClient) IsInBBSMode() bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.inBBSMode
}

// Close shuts down the BBS client
func (b *BBSClient) Close() {
	b.cancel()
	b.mu.Lock()
	if b.conn != nil {
		// Try to exit gracefully (using CRLF for telnet standard)
		if b.inBBSMode {
			b.conn.Write([]byte("B\r\n"))
			time.Sleep(100 * time.Millisecond)
		}
		b.conn.Close()
		b.conn = nil
	}
	b.state = StateDisconnected
	b.inBBSMode = false
	b.mu.Unlock()
}

// broadcastStatus sends status to all connected WebSocket clients
func (b *BBSClient) broadcastStatus() {
	msg := &BBSClientMessage{
		Seq:       atomic.AddInt64(&b.messageSeq, 1),
		Type:      "bbs_status",
		Connected: b.IsConnected(),
		InBBSMode: b.IsInBBSMode(),
	}
	b.broadcastMessage(msg)
}

// broadcastMessage sends a message to all connected BBS WebSocket clients
func (b *BBSClient) broadcastMessage(msg *BBSClientMessage) {
	jsonData, err := json.Marshal(msg)
	if err != nil {
		bbsLog.Errorf("Error marshalling BBS message: %v", err)
		return
	}

	msgStr := string(jsonData)

	bbsClientsMu.RLock()
	defer bbsClientsMu.RUnlock()

	for client := range bbsClients {
		if err := client.write(msgStr); err != nil {
			bbsLog.Errorf("BBS websocket error: %v", err)
			go client.kill()
		}
	}
}

// Run starts the main loop for the BBS client (handles reconnection)
func (b *BBSClient) Run() {
	bbsLog.Debugf("Starting main read loop")
	defer func() {
		bbsLog.Debugf("Read loop exiting, cleaning up")
		b.mu.Lock()
		b.state = StateDisconnected
		b.inBBSMode = false
		if b.conn != nil {
			b.conn.Close()
		}
		b.mu.Unlock()
		b.broadcastStatus()
		BroadcastFeatureStatus(b.GetStatus())
	}()

	// Accumulate message list lines
	var pendingMessages []BBSMessage

	// For reading message content
	var readingMsg *BBSMessage
	var bodyLines []string
	var inBody bool

	// Keep connection alive by reading any unsolicited data
	for {
		select {
		case <-b.ctx.Done():
			bbsLog.Debugf("Context cancelled, exiting read loop")
			return
		default:
			b.mu.RLock()
			if b.conn == nil {
				b.mu.RUnlock()
				bbsLog.Debugf("Connection is nil, exiting read loop")
				return
			}
			b.conn.SetReadDeadline(time.Now().Add(30 * time.Second))
			b.mu.RUnlock()

			line, err := b.reader.ReadString('\n')
			if err != nil {
				if b.ctx.Err() != nil {
					bbsLog.Debugf("Context cancelled during read")
					return
				}
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					// On timeout, if we have pending messages, broadcast them
					if len(pendingMessages) > 0 {
						bbsLog.Debugf("Timeout with %d pending messages, broadcasting", len(pendingMessages))
						b.broadcastMessageList(pendingMessages)
						pendingMessages = nil
					}
					// If we have a pending message read, broadcast what we have
					if readingMsg != nil {
						readingMsg.Body = strings.Join(bodyLines, "\n")
						bbsLog.Debugf("Timeout reading message, broadcasting what we have")
						b.broadcastReadMessage(readingMsg)
						readingMsg = nil
						bodyLines = nil
						inBody = false
						b.mu.Lock()
						b.pendingReadMsgNum = 0
						b.mu.Unlock()
					}
					continue
				}
				bbsLog.Errorf("Read error: %v", err)
				return
			}

			rawLine := line
			line = strings.TrimSpace(line)

			bbsLog.Debugf("Received: %s", line)

			// Re-read pendingReadMsgNum AFTER getting the line, in case a read command
			// was sent while we were blocked on ReadString
			b.mu.RLock()
			currentPendingRead := b.pendingReadMsgNum
			b.mu.RUnlock()

			// Check if we're reading a message (use the fresh value)
			if currentPendingRead > 0 && readingMsg == nil {
				// Start reading message content
				readingMsg = &BBSMessage{Number: currentPendingRead}
				bodyLines = nil
				inBody = false
				bbsLog.Debugf("Starting to read message #%d", currentPendingRead)
			}

			// If we're reading a message, parse it
			if readingMsg != nil {
				// Check for end of message (prompt)
				if strings.Contains(line, "--->") || (strings.Contains(line, ":") && strings.HasSuffix(line, ">")) {
					readingMsg.Body = strings.Join(bodyLines, "\n")
					bbsLog.Debugf("End of message #%d, body has %d lines", readingMsg.Number, len(bodyLines))
					b.broadcastReadMessage(readingMsg)
					readingMsg = nil
					bodyLines = nil
					inBody = false
					b.mu.Lock()
					b.pendingReadMsgNum = 0
					b.mu.Unlock()
					continue
				}

				// Parse headers or body
				// LinBPQ format: From, To, Type/Status, Date/Time, Bid, Title
				if !inBody {
					if strings.HasPrefix(line, "From:") {
						readingMsg.From = strings.TrimSpace(strings.TrimPrefix(line, "From:"))
					} else if strings.HasPrefix(line, "To:") {
						readingMsg.To = strings.TrimSpace(strings.TrimPrefix(line, "To:"))
					} else if strings.HasPrefix(line, "Title:") {
						// LinBPQ uses "Title:" for subject
						readingMsg.Subject = strings.TrimSpace(strings.TrimPrefix(line, "Title:"))
					} else if strings.HasPrefix(line, "Subject:") || strings.HasPrefix(line, "Subj:") {
						// Also support standard Subject: header
						readingMsg.Subject = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(line, "Subject:"), "Subj:"))
					} else if strings.HasPrefix(line, "Date/Time:") {
						// LinBPQ uses "Date/Time:" format
						readingMsg.Date = strings.TrimSpace(strings.TrimPrefix(line, "Date/Time:"))
					} else if strings.HasPrefix(line, "Date:") {
						// Also support standard Date: header
						readingMsg.Date = strings.TrimSpace(strings.TrimPrefix(line, "Date:"))
					} else if strings.HasPrefix(line, "Type/Status:") {
						ts := strings.TrimSpace(strings.TrimPrefix(line, "Type/Status:"))
						if len(ts) >= 2 {
							readingMsg.Type = string(ts[0])
							readingMsg.Status = string(ts[1])
						}
					} else if strings.HasPrefix(line, "Bid:") {
						// Skip Bid header (we don't need it for display)
					} else if line == "" || strings.TrimSpace(rawLine) == "" {
						// Blank line signals end of headers
						inBody = true
					}
				} else {
					bodyLines = append(bodyLines, line)
				}
				continue
			}

			// Not reading a message - handle list lines

			// Check if this is an end-of-list prompt (e.g., "0 unread--->" or "WA2M:MIKE>")
			if strings.Contains(line, "--->") || (strings.Contains(line, ":") && strings.HasSuffix(line, ">")) {
				// Broadcast accumulated messages (even if empty - frontend needs to know list is complete)
				bbsLog.Debugf("End of list detected, broadcasting %d messages", len(pendingMessages))
				b.broadcastMessageList(pendingMessages)
				pendingMessages = nil
				continue
			}

			// Check if this is a welcome/status line (skip it)
			if strings.Contains(line, "unread>>>>") || strings.Contains(line, "new-msgs=") {
				continue
			}

			// Check for message sent confirmation (e.g., "Message #307 Saved" or "Msg 307 Saved")
			if msgSentRe := regexp.MustCompile(`(?i)(message|msg)\s*#?(\d+)\s*(saved|accepted)`); msgSentRe.MatchString(line) {
				matches := msgSentRe.FindStringSubmatch(line)
				if len(matches) >= 3 {
					msgNum, _ := strconv.Atoi(matches[2])
					bbsLog.Debugf("Message #%d sent confirmation detected", msgNum)
					b.broadcastMessageSent(msgNum)
				}
				continue
			}

			// Try to parse as a message list line
			msg := b.parseMessageLine(line)
			if msg != nil {
				pendingMessages = append(pendingMessages, *msg)
				bbsLog.Debugf("Parsed message #%d: %s", msg.Number, msg.Subject)
			}
		}
	}
}

// broadcastReadMessage sends a read message to all connected WebSocket clients
func (b *BBSClient) broadcastReadMessage(msg *BBSMessage) {
	clientMsg := &BBSClientMessage{
		Seq:     atomic.AddInt64(&b.messageSeq, 1),
		Type:    "bbs_message",
		Message: msg,
	}
	b.broadcastMessage(clientMsg)
}

// broadcastMessageSent notifies clients that a message was sent successfully
func (b *BBSClient) broadcastMessageSent(msgNum int) {
	clientMsg := &BBSClientMessage{
		Seq:    atomic.AddInt64(&b.messageSeq, 1),
		Type:   "bbs_sent",
		Number: msgNum,
	}
	b.broadcastMessage(clientMsg)
}

// broadcastMessageList sends a message list to all connected WebSocket clients
func (b *BBSClient) broadcastMessageList(messages []BBSMessage) {
	msg := &BBSClientMessage{
		Seq:      atomic.AddInt64(&b.messageSeq, 1),
		Type:     "bbs_list",
		Messages: messages,
	}
	b.broadcastMessage(msg)
}

// initBBSClient initializes the global BBS client (called from main)
func initBBSClient(cfg BBSClientConfig) {
	bbsClient = NewBBSClient(cfg)
	bbsManager = bbsClient

	go func() {
		for {
			if err := bbsClient.Connect(); err != nil {
				bbsLog.Warnw("Connection failed, retrying", "error", err, "retryIn", "30s")
				time.Sleep(30 * time.Second)
				continue
			}

			// Note: initConnection() now automatically enters BBS mode
			bbsClient.Run()

			// Connection lost, wait before reconnecting
			bbsLog.Warnf("Connection lost, reconnecting in 10s")
			time.Sleep(10 * time.Second)
		}
	}()
}

// ConnectBBS connects the BBS feature with the given configuration
func ConnectBBS(config FeatureConfig) error {
	bbsLog.Infow("ConnectBBS called", "host", config.Host, "port", config.Port, "callsign", config.Callsign)
	if bbsManager != nil && bbsManager.IsConnected() {
		bbsLog.Debugf("Already connected, returning error")
		return fmt.Errorf("bbs: %w", ErrAlreadyConnected)
	}

	// Create new client if none exists
	if bbsManager == nil {
		bbsLog.Debugf("Initializing BBS manager")
		bbsManager = NewBBSClientWithConfig(config)
		bbsClient = bbsManager
	}

	go func() {
		if err := bbsManager.ConnectWithConfig(config); err != nil {
			bbsLog.Errorf("Connection failed: %v", err)
			return
		}

		// Note: initConnection() now automatically enters BBS mode
		bbsManager.Run()
		bbsLog.Infof("Connection ended")
	}()

	return nil
}

// DisconnectBBS disconnects the BBS feature
func DisconnectBBS() error {
	if bbsManager == nil {
		return fmt.Errorf("BBS is not initialized")
	}
	return bbsManager.Disconnect()
}

// GetBBSStatus returns the current BBS status
func GetBBSStatus() FeatureStatus {
	if bbsManager != nil {
		return bbsManager.GetStatus()
	}
	return FeatureStatus{
		Type:    "feature_status",
		Feature: "bbs",
		State:   StateDisconnected,
	}
}
