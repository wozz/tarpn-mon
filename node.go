package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// NodeMessage represents output from the node console
type NodeMessage struct {
	Seq       int64    `json:"seq"`
	Type      string   `json:"type"` // "node_output", "node_status", "node_error", "node_prompt"
	Lines     []string `json:"lines,omitempty"`
	Prompt    string   `json:"prompt,omitempty"`
	Connected bool     `json:"connected,omitempty"`
	Error     string   `json:"error,omitempty"`
}

// NodeClient manages the connection to the BPQ node console
type NodeClient struct {
	// messageSeq must be first for 64-bit alignment on 32-bit ARM
	messageSeq int64

	hostname string
	port     int
	callsign string
	password string

	conn  net.Conn
	state FeatureState
	mu    sync.RWMutex

	// Dynamic connection state
	connectedAt *time.Time
	lastError   string

	prompt string // Current node prompt (e.g., "N0CALL de MYNODE>")

	ctx    context.Context
	cancel context.CancelFunc

	// Output buffer for collecting multi-line responses
	outputBuffer []string
	outputMu     sync.Mutex

	// Channel for sending commands
	cmdChan chan string
}

// NodeClientConfig holds configuration for creating a node client
type NodeClientConfig struct {
	Hostname string
	Port     int
	Callsign string
	Password string
}

var (
	nodeClient    *NodeClient
	nodeManager   *NodeClient // Alias for feature manager interface
	nodeClientsMu sync.RWMutex
	nodeClients   = make(map[*websocketConn]bool)
	nodeBuffer    *circularBuffer
)

// NewNodeClient creates a new node client
func NewNodeClient(cfg NodeClientConfig) *NodeClient {
	ctx, cancel := context.WithCancel(context.Background())
	return &NodeClient{
		hostname:     cfg.Hostname,
		port:         cfg.Port,
		callsign:     cfg.Callsign,
		password:     cfg.Password,
		state:        StateDisconnected,
		ctx:          ctx,
		cancel:       cancel,
		outputBuffer: make([]string, 0),
		cmdChan:      make(chan string, 10),
	}
}

// NewNodeClientWithConfig creates a new node client from FeatureConfig
func NewNodeClientWithConfig(config FeatureConfig) *NodeClient {
	return NewNodeClient(NodeClientConfig{
		Hostname: config.Host,
		Port:     config.Port,
		Callsign: config.Callsign,
		Password: config.Password,
	})
}

// Connect establishes connection to the BPQ node
func (n *NodeClient) Connect() error {
	addr := fmt.Sprintf("%s:%d", n.hostname, n.port)
	nodeLog.Infow("Connecting", "addr", addr, "callsign", n.callsign)

	n.mu.Lock()
	n.state = StateConnecting
	n.lastError = ""
	n.mu.Unlock()
	n.broadcastStatus()
	BroadcastFeatureStatus(n.GetStatus())

	conn, err := net.DialTimeout("tcp", addr, 30*time.Second)
	if err != nil {
		nodeLog.Errorf("TCP connection failed to %s: %v", addr, err)
		n.mu.Lock()
		n.state = StateError
		n.lastError = fmt.Sprintf("failed to connect to node: %v", err)
		n.mu.Unlock()
		n.broadcastStatus()
		BroadcastFeatureStatus(n.GetStatus())
		return fmt.Errorf("failed to connect to node: %w", err)
	}
	nodeLog.Debugf("TCP connection established to %s", addr)

	n.mu.Lock()
	n.conn = conn
	n.mu.Unlock()

	// Initialize the connection
	nodeLog.Debugf("Starting authentication sequence")
	if err := n.initConnection(); err != nil {
		nodeLog.Errorf("Authentication/init failed: %v", err)
		conn.Close()
		n.mu.Lock()
		n.state = StateError
		n.lastError = err.Error()
		n.conn = nil
		n.mu.Unlock()
		n.broadcastStatus()
		BroadcastFeatureStatus(n.GetStatus())
		return err
	}
	nodeLog.Infof("Connected successfully")

	now := time.Now()
	n.mu.Lock()
	n.state = StateConnected
	n.connectedAt = &now
	n.lastError = ""
	n.mu.Unlock()

	// Broadcast connection status
	n.broadcastStatus()
	BroadcastFeatureStatus(n.GetStatus())

	return nil
}

// ConnectWithConfig connects using a FeatureConfig
func (n *NodeClient) ConnectWithConfig(config FeatureConfig) error {
	n.mu.Lock()
	n.hostname = config.Host
	n.port = config.Port
	n.callsign = config.Callsign
	n.password = config.Password
	n.mu.Unlock()

	return n.Connect()
}


// initConnection sends the initial authentication
// Uses the shared TelnetConn for proper prompt-based auth
func (n *NodeClient) initConnection() error {
	// Create telnet connection wrapper - handles IAC negotiation
	tc, err := NewTelnetConn(n.conn, 2*time.Second, nodeLog)
	if err != nil {
		return fmt.Errorf("telnet negotiation failed: %w", err)
	}

	// Authenticate using standard telnet protocol (waits for prompts)
	nodeLog.Debugf("Starting authentication")
	_, err = tc.Authenticate(n.callsign, n.password, 5*time.Second)
	if err != nil {
		return fmt.Errorf("authentication failed: %w", err)
	}

	// Broadcast CTEXT
	n.broadcastOutput([]string{"Connected successfully"})

	// Send CR to trigger the node prompt
	nodeLog.Debugf("Auth successful, sending CR to trigger prompt")
	if err := tc.WriteString(""); err != nil {
		return fmt.Errorf("failed to send CR: %w", err)
	}

	// Wait for the node prompt
	nodeLog.Debugf("Waiting for node prompt (10s timeout)")
	lines, found, err := tc.ReadUntil(func(line string) bool {
		if n.isPrompt(line) {
			nodeLog.Debugf("Node prompt detected: %q", line)
			n.prompt = line
			return true
		}
		return false
	}, 10*time.Second)

	// Broadcast any output lines
	if len(lines) > 0 {
		n.broadcastOutput(lines)
	}

	if err != nil {
		return fmt.Errorf("error waiting for node prompt: %w", err)
	}

	// Even if no prompt found, consider it connected (prompt may come later)
	n.conn.SetReadDeadline(time.Time{})

	if found {
		nodeLog.Infof("Node console ready")
	} else {
		nodeLog.Debugf("No prompt received, but auth succeeded - continuing")
	}

	return nil
}

// isPrompt checks if a line looks like a node prompt
func (n *NodeClient) isPrompt(line string) bool {
	// Node prompt format: "CALL de NODE>" or "CALL:NODE>" (case insensitive)
	// Also matches prompts ending with just ">"
	promptRe := regexp.MustCompile(`(?i)^[A-Z0-9-]+\s+(de|:)\s*[A-Z0-9-]+>\s*$`)
	if promptRe.MatchString(strings.TrimSpace(line)) {
		return true
	}
	// Also check for simpler prompt format ending with ">"
	simplePromptRe := regexp.MustCompile(`(?i)^[A-Z0-9-]+>\s*$`)
	return simplePromptRe.MatchString(strings.TrimSpace(line))
}

// Run starts the main read loop for the node client
func (n *NodeClient) Run() {
	nodeLog.Debugf("Starting main read loop")
	defer func() {
		nodeLog.Debugf("Read loop exiting, cleaning up")
		n.mu.Lock()
		n.state = StateDisconnected
		if n.conn != nil {
			n.conn.Close()
		}
		n.mu.Unlock()
		n.broadcastStatus()
		BroadcastFeatureStatus(n.GetStatus())
	}()

	reader := bufio.NewReader(n.conn)

	// Start command sender goroutine
	go n.commandSender()

	for {
		select {
		case <-n.ctx.Done():
			nodeLog.Debugf("Context cancelled, exiting read loop")
			return
		default:
			n.conn.SetReadDeadline(time.Now().Add(30 * time.Second))
			// Use \n as delimiter since LinBPQ sends \r\n terminated lines
			line, err := reader.ReadString('\n')
			if err != nil {
				if n.ctx.Err() != nil {
					nodeLog.Debugf("Context cancelled during read")
					return // Context cancelled
				}
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					nodeLog.Debugf("Read timeout (30s), no data from server")
					continue
				}
				nodeLog.Errorf("Read error: %v", err)
				return
			}

			// Strip both \r and \n from line endings
			line = strings.TrimRight(line, "\r\n")

			if len(line) == 0 {
				continue
			}

			nodeLog.Debugf("Main loop received: %q", line)
			n.processLine(line)
		}
	}
}

// commandSender handles sending commands to the node
func (n *NodeClient) commandSender() {
	nodeLog.Debugf("Command sender started")
	for {
		select {
		case <-n.ctx.Done():
			nodeLog.Debugf("Command sender exiting")
			return
		case cmd := <-n.cmdChan:
			n.mu.RLock()
			conn := n.conn
			state := n.state
			n.mu.RUnlock()

			if state != StateConnected || conn == nil {
				nodeLog.Debugf("Cannot send command (state=%v, conn=%v): %s", state, conn != nil, cmd)
				continue
			}

			nodeLog.Debugf("Sending command: %q", cmd)
			// Use \r\n for telnet protocol (CRLF is standard)
			if _, err := conn.Write([]byte(cmd + "\r\n")); err != nil {
				nodeLog.Errorf("Write error: %v", err)
			}
		}
	}
}

// processLine handles incoming output from the node
func (n *NodeClient) processLine(line string) {
	// Clean any remaining telnet bytes from the line
	line = CleanTelnetBytes(line)
	if line == "" {
		return
	}

	// Check if this is a prompt
	if n.isPrompt(line) {
		n.prompt = line
		n.broadcastPrompt()
		return
	}

	// Broadcast each line immediately (no buffering - server doesn't send prompts reliably)
	n.broadcastOutput([]string{line})
}

// SendCommand sends a command to the node
func (n *NodeClient) SendCommand(cmd string) error {
	n.mu.RLock()
	state := n.state
	n.mu.RUnlock()

	if state != StateConnected {
		return fmt.Errorf("not connected to node")
	}

	select {
	case n.cmdChan <- cmd:
		return nil
	default:
		return fmt.Errorf("command queue full")
	}
}

// IsConnected returns whether the node client is connected
func (n *NodeClient) IsConnected() bool {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.state == StateConnected
}

// GetStatus returns the current feature status for the node client
func (n *NodeClient) GetStatus() FeatureStatus {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return FeatureStatus{
		Type:        "feature_status",
		Feature:     "node",
		State:       n.state,
		Callsign:    n.callsign,
		Host:        n.hostname,
		Port:        n.port,
		Error:       n.lastError,
		ConnectedAt: n.connectedAt,
	}
}

// Disconnect gracefully disconnects the node client
func (n *NodeClient) Disconnect() error {
	nodeLog.Infof("Disconnect requested")
	n.mu.Lock()
	if n.state == StateDisconnected {
		n.mu.Unlock()
		nodeLog.Debugf("Already disconnected")
		return nil
	}
	n.state = StateDisconnecting
	n.mu.Unlock()
	BroadcastFeatureStatus(n.GetStatus())

	n.Close()

	n.mu.Lock()
	n.state = StateDisconnected
	n.connectedAt = nil
	n.mu.Unlock()
	n.broadcastStatus()
	BroadcastFeatureStatus(n.GetStatus())
	nodeLog.Infof("Disconnected")

	return nil
}

// GetPrompt returns the current node prompt
func (n *NodeClient) GetPrompt() string {
	n.mu.RLock()
	defer n.mu.RUnlock()
	return n.prompt
}

// Close shuts down the node client
func (n *NodeClient) Close() {
	n.cancel()
	n.mu.Lock()
	if n.conn != nil {
		// Send bye command before closing
		n.conn.Write([]byte("BYE\r"))
		time.Sleep(100 * time.Millisecond)
		n.conn.Close()
		n.conn = nil
	}
	n.state = StateDisconnected
	n.mu.Unlock()
}

// broadcastOutput sends output lines to all connected WebSocket clients
func (n *NodeClient) broadcastOutput(lines []string) {
	msg := &NodeMessage{
		Seq:   atomic.AddInt64(&n.messageSeq, 1),
		Type:  "node_output",
		Lines: lines,
	}

	n.broadcast(msg)
}

// broadcastPrompt sends the current prompt to all clients
func (n *NodeClient) broadcastPrompt() {
	msg := &NodeMessage{
		Seq:    atomic.AddInt64(&n.messageSeq, 1),
		Type:   "node_prompt",
		Prompt: n.prompt,
	}

	n.broadcast(msg)
}

// broadcastStatus sends connection status to all clients
func (n *NodeClient) broadcastStatus() {
	n.mu.RLock()
	state := n.state
	prompt := n.prompt
	n.mu.RUnlock()

	msg := &NodeMessage{
		Seq:       atomic.AddInt64(&n.messageSeq, 1),
		Type:      "node_status",
		Connected: state == StateConnected,
		Prompt:    prompt,
	}

	n.broadcast(msg)
}

// broadcastError sends an error message to all clients
func (n *NodeClient) broadcastError(errMsg string) {
	msg := &NodeMessage{
		Seq:   atomic.AddInt64(&n.messageSeq, 1),
		Type:  "node_error",
		Error: errMsg,
	}

	n.broadcast(msg)
}

// broadcast sends a message to all connected node WebSocket clients
func (n *NodeClient) broadcast(msg *NodeMessage) {
	jsonData, err := json.Marshal(msg)
	if err != nil {
		nodeLog.Errorf("Error marshalling node message: %v", err)
		return
	}

	msgStr := string(jsonData)

	if nodeBuffer != nil {
		nodeBuffer.add(msg.Seq, msgStr)
	}

	nodeClientsMu.RLock()
	defer nodeClientsMu.RUnlock()

	for client := range nodeClients {
		if err := client.write(msgStr); err != nil {
			nodeLog.Errorf("Node websocket error: %v", err)
			go client.kill()
		}
	}
}

// initNodeClient initializes the global node client (called from main)
func initNodeClient(cfg NodeClientConfig) {
	nodeBuffer = newCircularBuffer(200) // Keep last 200 node messages
	nodeClient = NewNodeClient(cfg)
	nodeManager = nodeClient

	go func() {
		for {
			if err := nodeClient.Connect(); err != nil {
				nodeLog.Warnw("Connection failed, retrying", "error", err, "retryIn", "30s")
				time.Sleep(30 * time.Second)
				continue
			}

			nodeClient.Run()

			// Connection lost, wait before reconnecting
			nodeLog.Warnf("Connection lost, reconnecting in 10s")
			time.Sleep(10 * time.Second)
		}
	}()
}

// ConnectNode connects the Node feature with the given configuration
func ConnectNode(config FeatureConfig) error {
	nodeLog.Infow("ConnectNode called", "host", config.Host, "port", config.Port, "callsign", config.Callsign)
	if nodeManager != nil && nodeManager.IsConnected() {
		nodeLog.Debugf("Already connected, returning error")
		return fmt.Errorf("node: %w", ErrAlreadyConnected)
	}

	// Initialize buffer if needed
	if nodeBuffer == nil {
		nodeBuffer = newCircularBuffer(200)
	}

	// Create new client if none exists
	if nodeManager == nil {
		nodeLog.Debugf("Initializing node manager")
		nodeManager = NewNodeClientWithConfig(config)
		nodeClient = nodeManager
	}

	go func() {
		if err := nodeManager.ConnectWithConfig(config); err != nil {
			nodeLog.Errorf("Connection failed: %v", err)
			return
		}

		nodeManager.Run()
		nodeLog.Infof("Connection ended")
	}()

	return nil
}

// DisconnectNode disconnects the Node feature
func DisconnectNode() error {
	if nodeManager == nil {
		return fmt.Errorf("Node is not initialized")
	}
	return nodeManager.Disconnect()
}

// GetNodeStatus returns the current Node status
func GetNodeStatus() FeatureStatus {
	if nodeManager != nil {
		return nodeManager.GetStatus()
	}
	return FeatureStatus{
		Type:    "feature_status",
		Feature: "node",
		State:   StateDisconnected,
	}
}
