package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

// ChatUser represents a user in the chat system
type ChatUser struct {
	Call       string    `json:"call"`
	Name       string    `json:"name"`
	Node       string    `json:"node"`
	QTH        string    `json:"qth,omitempty"`
	Topic      string    `json:"topic"`
	Connected  time.Time `json:"connected"`
	Status     string    `json:"status,omitempty"`     // TARPN Home status: "IDL", "ACT", "AFK", "BBS"
	StatusTime string    `json:"statusTime,omitempty"` // When status last changed (from $TH message)
	THVersion  string    `json:"thVersion,omitempty"`  // TARPN Home version
}

// ChatMessage represents a chat message
type ChatMessage struct {
	Seq       int64  `json:"seq"`
	Type      string `json:"type"` // "chat_msg", "chat_join", "chat_leave", "chat_topic", "chat_users", "chat_status", "chat_th"
	Timestamp string `json:"timestamp"`
	From      string `json:"from,omitempty"`
	FromName  string `json:"fromName,omitempty"`
	To        string `json:"to,omitempty"`
	Topic     string `json:"topic,omitempty"`
	Message   string `json:"message,omitempty"`
	Node      string `json:"node,omitempty"`
	Users     []ChatUser `json:"users,omitempty"`
	Connected bool   `json:"connected,omitempty"`
}

// ChatSettings represents user-editable chat settings
type ChatSettings struct {
	Type  string `json:"type"` // "chat_settings"
	Name  string `json:"name"`
	QTH   string `json:"qth"`
	Topic string `json:"topic"`
}

// THInfo holds parsed data from a TARPN Home $TH status message
type THInfo struct {
	Version   string // e.g., "2.3.3"
	Status    string // e.g., "IDL", "ACT", "AFK", "BBS"
	Timestamp string // e.g., "01-25-2025 16:04"
}

// validTHStatuses contains the known $TH status codes
var validTHStatuses = map[string]bool{
	"IDL": true, "ACT": true, "AFK": true, "BBS": true,
}

// parseTHMessage parses a $TH status message. Returns nil if the text
// is not a $TH message or is malformed.
// Format: "V<version> > $TH:<status><timestamp>"
// Example: "V2.3.3 > $TH:IDL01-25-2025 16:04"
func parseTHMessage(text string) *THInfo {
	marker := " > $TH:"
	idx := strings.Index(text, marker)
	if idx < 0 {
		return nil
	}

	// Need at least 3 chars after marker for status code
	afterMarker := idx + len(marker)
	if len(text) < afterMarker+3 {
		return nil
	}

	status := text[afterMarker : afterMarker+3]
	if !validTHStatuses[status] {
		return nil
	}

	// Extract version: everything before marker, strip leading "V"
	version := text[:idx]
	if strings.HasPrefix(version, "V") {
		version = version[1:]
	}

	// Extract timestamp: everything after the 3-char status
	timestamp := strings.TrimRight(text[afterMarker+3:], "\r\n ")

	return &THInfo{
		Version:   version,
		Status:    status,
		Timestamp: timestamp,
	}
}

// ChatClient manages the connection to the tarpn-chat server via WebSocket
type ChatClient struct {
	// messageSeq must be first for 64-bit alignment on 32-bit ARM
	messageSeq int64

	hostname     string
	port         int
	callsign     string
	password     string
	userName     string
	userQTH      string // User's QTH/location

	wsConn       *websocket.Conn
	state        FeatureState
	connectedAt  *time.Time
	lastError    string
	mu           sync.RWMutex

	users        map[string]*ChatUser // keyed by "call@node"
	usersMu      sync.RWMutex

	currentTopic string
	ourNode      string // Our node identifier

	ctx          context.Context
	cancel       context.CancelFunc

	disconnectRequested bool // True if user intentionally disconnected (don't auto-reconnect)
}

var (
	chatClient     *ChatClient
	chatManager    *ChatClient // Alias for feature manager interface
	chatClientsMu  sync.RWMutex
	chatClients    = make(map[*websocketConn]bool)
	chatBuffer     ChatStorage
)

// NewChatClient creates a new chat client (not connected)
func NewChatClient() *ChatClient {
	ctx, cancel := context.WithCancel(context.Background())
	return &ChatClient{
		state:        StateDisconnected,
		users:        make(map[string]*ChatUser),
		currentTopic: "General",
		ctx:          ctx,
		cancel:       cancel,
	}
}

// ConnectWithConfig establishes connection using the provided configuration
func (c *ChatClient) ConnectWithConfig(config FeatureConfig) error {
	c.mu.Lock()
	if c.state == StateConnecting || c.state == StateConnected {
		c.mu.Unlock()
		return fmt.Errorf("already connected or connecting")
	}
	c.disconnectRequested = false // Reset flag - allow auto-reconnect
	c.hostname = config.Host
	c.port = config.Port
	c.callsign = config.Callsign
	c.password = config.Password
	if name, ok := config.Options["name"]; ok {
		c.userName = name
	} else {
		c.userName = config.Callsign
	}
	if node, ok := config.Options["node"]; ok {
		c.ourNode = node
	}
	if qth, ok := config.Options["qth"]; ok {
		c.userQTH = qth
	}
	c.state = StateConnecting
	c.lastError = ""
	c.mu.Unlock()

	// Broadcast connecting status
	BroadcastFeatureStatus(c.GetStatus())

	return c.doConnect()
}

// Connect establishes connection to the chat server (uses existing config)
func (c *ChatClient) Connect() error {
	c.mu.Lock()
	if c.state == StateConnecting || c.state == StateConnected {
		c.mu.Unlock()
		return fmt.Errorf("already connected or connecting")
	}
	c.state = StateConnecting
	c.lastError = ""
	c.mu.Unlock()

	// Broadcast connecting status
	BroadcastFeatureStatus(c.GetStatus())

	return c.doConnect()
}

// doConnect performs the WebSocket connection to tarpn-chat
func (c *ChatClient) doConnect() error {
	wsURL := url.URL{Scheme: "ws", Host: net.JoinHostPort(c.hostname, strconv.Itoa(c.port)), Path: "/"}
	chatLog.Infow("Connecting via WebSocket", "url", wsURL.String(), "callsign", c.callsign)

	dialer := websocket.Dialer{
		HandshakeTimeout: 30 * time.Second,
	}

	conn, _, err := dialer.Dial(wsURL.String(), nil)
	if err != nil {
		chatLog.Errorf("WebSocket connection failed to %s: %v", wsURL.String(), err)
		c.mu.Lock()
		c.state = StateError
		c.lastError = err.Error()
		c.mu.Unlock()
		BroadcastFeatureStatus(c.GetStatus())
		return fmt.Errorf("failed to connect to chat server via WebSocket: %w", err)
	}
	chatLog.Debugf("WebSocket connection established to %s", wsURL.String())

	// Set up pong handler to reset read deadline when pong is received
	conn.SetPongHandler(func(string) error {
		chatLog.Debugf("WebSocket pong received, resetting deadline")
		conn.SetReadDeadline(time.Now().Add(5 * time.Minute))
		return nil
	})

	c.mu.Lock()
	c.wsConn = conn
	c.mu.Unlock()

	// Wait for connected event from server
	_, message, err := conn.ReadMessage()
	if err != nil {
		conn.Close()
		c.mu.Lock()
		c.state = StateError
		c.lastError = err.Error()
		c.wsConn = nil
		c.mu.Unlock()
		BroadcastFeatureStatus(c.GetStatus())
		return fmt.Errorf("failed to read initial message: %w", err)
	}

	var event map[string]interface{}
	if err := json.Unmarshal(message, &event); err != nil {
		conn.Close()
		c.mu.Lock()
		c.state = StateError
		c.lastError = "invalid server response"
		c.wsConn = nil
		c.mu.Unlock()
		BroadcastFeatureStatus(c.GetStatus())
		return fmt.Errorf("invalid server response: %w", err)
	}

	eventType, _ := event["type"].(string)
	if eventType != "connected" {
		conn.Close()
		c.mu.Lock()
		c.state = StateError
		c.lastError = fmt.Sprintf("unexpected initial event: %s", eventType)
		c.wsConn = nil
		c.mu.Unlock()
		BroadcastFeatureStatus(c.GetStatus())
		return fmt.Errorf("unexpected initial event: %s", eventType)
	}

	chatLog.Debugf("Received connected event from server")

	// Send join command
	joinCmd := map[string]string{
		"cmd":  "join",
		"user": strings.ToUpper(c.callsign),
		"name": c.userName,
		"qth":  "TARPN-Mon",
	}
	if c.userQTH != "" {
		joinCmd["qth"] = c.userQTH
	}

	if err := conn.WriteJSON(joinCmd); err != nil {
		conn.Close()
		c.mu.Lock()
		c.state = StateError
		c.lastError = err.Error()
		c.wsConn = nil
		c.mu.Unlock()
		BroadcastFeatureStatus(c.GetStatus())
		return fmt.Errorf("failed to send join command: %w", err)
	}
	chatLog.Debugf("Sent join command: %+v", joinCmd)

	// Set node info based on callsign
	if strings.EqualFold(c.callsign, "chtbot") {
		c.ourNode = "BOT"
	} else {
		c.ourNode = strings.ToUpper(c.callsign)
	}

	chatLog.Infof("Connected successfully via WebSocket")

	// Clear stale users from previous session
	c.usersMu.Lock()
	c.users = make(map[string]*ChatUser)
	c.usersMu.Unlock()

	now := time.Now()
	c.mu.Lock()
	c.state = StateConnected
	c.connectedAt = &now
	c.lastError = ""
	wsConn := c.wsConn
	c.mu.Unlock()

	// Request current user list from server to rebuild state
	if wsConn != nil {
		getUsersCmd := map[string]string{"cmd": "get_users"}
		if jsonData, err := json.Marshal(getUsersCmd); err == nil {
			if err := wsConn.WriteMessage(websocket.TextMessage, jsonData); err != nil {
				chatLog.Warnf("Failed to request user list: %v", err)
			} else {
				chatLog.Debugf("Requested user list from server")
			}
		}
	}

	// Broadcast connection status
	BroadcastFeatureStatus(c.GetStatus())
	c.broadcastStatus(true)

	return nil
}

// Run starts the main WebSocket read loop for the chat client
func (c *ChatClient) Run() {
	chatLog.Debugf("Starting WebSocket read loop")
	defer func() {
		chatLog.Debugf("WebSocket read loop exiting, cleaning up")
		c.mu.Lock()
		c.state = StateDisconnected
		c.connectedAt = nil
		if c.wsConn != nil {
			c.wsConn.Close()
			c.wsConn = nil
		}
		c.mu.Unlock()
		BroadcastFeatureStatus(c.GetStatus())
		c.broadcastStatus(false)
	}()

	// Start WebSocket ping loop to keep connection alive
	go c.wsPingLoop()

	for {
		select {
		case <-c.ctx.Done():
			chatLog.Debugf("Context cancelled, exiting WebSocket read loop")
			return
		default:
			c.mu.RLock()
			conn := c.wsConn
			c.mu.RUnlock()

			if conn == nil {
				chatLog.Debugf("WebSocket connection is nil, exiting")
				return
			}

			// Set read deadline
			conn.SetReadDeadline(time.Now().Add(5 * time.Minute))

			_, message, err := conn.ReadMessage()
			if err != nil {
				if c.ctx.Err() != nil {
					chatLog.Debugf("Context cancelled during WebSocket read")
					return
				}
				chatLog.Errorf("WebSocket read error: %v", err)
				return
			}

			chatLog.Debugf("WebSocket received: %s", string(message))
			c.processJSONEvent(message)
		}
	}
}

// wsPingLoop sends periodic pings to keep the WebSocket connection alive
func (c *ChatClient) wsPingLoop() {
	// Send pings every 2 minutes (well under the 5-minute read deadline)
	ticker := time.NewTicker(2 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-c.ctx.Done():
			chatLog.Debugf("WebSocket ping loop exiting (context cancelled)")
			return
		case <-ticker.C:
			c.mu.RLock()
			conn := c.wsConn
			c.mu.RUnlock()

			if conn == nil {
				chatLog.Debugf("WebSocket ping loop exiting (connection nil)")
				return
			}

			// Send ping
			if err := conn.WriteControl(websocket.PingMessage, []byte{}, time.Now().Add(10*time.Second)); err != nil {
				chatLog.Warnf("WebSocket ping failed: %v", err)
				return
			}
			chatLog.Debugf("WebSocket ping sent")
		}
	}
}

// processJSONEvent handles incoming JSON events from tarpn-chat WebSocket API
func (c *ChatClient) processJSONEvent(message []byte) {
	var event map[string]interface{}
	if err := json.Unmarshal(message, &event); err != nil {
		chatLog.Warnf("Invalid JSON event: %v", err)
		return
	}

	eventType, _ := event["type"].(string)

	switch eventType {
	case "join":
		node, _ := event["node"].(string)
		user, _ := event["user"].(string)
		name, _ := event["name"].(string)
		chatLog.Debugf("WS JOIN: node=%s user=%s name=%s", node, user, name)
		c.handleUserJoin(node, user, name)

	case "leave":
		node, _ := event["node"].(string)
		user, _ := event["user"].(string)
		chatLog.Debugf("WS LEAVE: node=%s user=%s", node, user)
		c.handleUserLeave(node, user)

	case "data":
		node, _ := event["node"].(string)
		user, _ := event["user"].(string)
		text, _ := event["text"].(string)
		chatLog.Debugf("WS DATA: node=%s user=%s text=%q", node, user, text)
		c.handleDataMessage(node, user, text)

	case "private":
		node, _ := event["node"].(string)
		from, _ := event["from"].(string)
		to, _ := event["to"].(string)
		text, _ := event["text"].(string)
		chatLog.Debugf("WS PRIVATE: from=%s to=%s text=%q", from, to, text)
		// TODO: Handle private messages
		_ = node

	case "topic":
		node, _ := event["node"].(string)
		user, _ := event["user"].(string)
		topic, _ := event["topic"].(string)
		chatLog.Debugf("WS TOPIC: node=%s user=%s topic=%s", node, user, topic)
		c.handleTopicChange(node, user, topic)

	case "info":
		node, _ := event["node"].(string)
		user, _ := event["user"].(string)
		name, _ := event["name"].(string)
		chatLog.Debugf("WS INFO: node=%s user=%s name=%s", node, user, name)
		c.handleUserJoin(node, user, name) // Reuse join handler

	case "node_link":
		node, _ := event["node"].(string)
		newNode, _ := event["new_node"].(string)
		alias, _ := event["alias"].(string)
		chatLog.Infof("WS Node linked: %s (%s) via %s", newNode, alias, node)

	case "node_unlink":
		node, _ := event["node"].(string)
		lostNode, _ := event["lost_node"].(string)
		chatLog.Infof("WS Node unlinked: %s via %s", lostNode, node)

	case "users":
		// Response to get_users command - rebuild user list
		users, ok := event["users"].([]interface{})
		if ok {
			chatLog.Debugf("WS USERS: received %d users", len(users))
			c.usersMu.Lock()
			// Clear and rebuild from server's authoritative list
			c.users = make(map[string]*ChatUser)
			for _, u := range users {
				userMap, ok := u.(map[string]interface{})
				if !ok {
					continue
				}
				call, _ := userMap["call"].(string)
				name, _ := userMap["name"].(string)
				node, _ := userMap["node"].(string)
				qth, _ := userMap["qth"].(string)
				topic, _ := userMap["topic"].(string)
				if call != "" && node != "" {
					key := call + "@" + node
					c.users[key] = &ChatUser{
						Call:      call,
						Name:      name,
						Node:      node,
						QTH:       qth,
						Topic:     topic,
						Connected: time.Now(),
					}
				}
			}
			c.usersMu.Unlock()
			chatLog.Debugf("Rebuilt user list with %d users", len(c.users))

			// Broadcast updated user list to WebSocket clients
			c.broadcastUserList()
		}

	case "nodes":
		// Response to get_nodes command
		nodes, ok := event["nodes"].([]interface{})
		if ok {
			chatLog.Debugf("WS NODES: received %d nodes", len(nodes))
		}

	case "connected":
		chatLog.Debugf("WS CONNECTED event (already connected)")

	case "disconnected":
		reason, _ := event["reason"].(string)
		chatLog.Warnf("WS DISCONNECTED: %s", reason)

	case "error":
		message, _ := event["message"].(string)
		chatLog.Errorf("WS ERROR: %s", message)

	default:
		chatLog.Warnf("Unknown WebSocket event type: %s", eventType)
	}
}

// handleUserJoin processes a user join event
func (c *ChatClient) handleUserJoin(node, call, name string) {
	key := call + "@" + node

	c.usersMu.Lock()
	c.users[key] = &ChatUser{
		Call:      call,
		Name:      name,
		Node:      node,
		Topic:     c.currentTopic,
		Connected: time.Now(),
	}
	c.usersMu.Unlock()

	msg := &ChatMessage{
		Seq:       atomic.AddInt64(&c.messageSeq, 1),
		Type:      "chat_join",
		Timestamp: time.Now().Format("15:04:05"),
		From:      call,
		FromName:  name,
		Node:      node,
		Message:   fmt.Sprintf("%s (%s) joined", call, name),
	}
	c.broadcastMessage(msg)
}

// handleUserLeave processes a user leave event
func (c *ChatClient) handleUserLeave(node, call string) {
	key := call + "@" + node

	c.usersMu.Lock()
	user := c.users[key]
	delete(c.users, key)
	c.usersMu.Unlock()

	name := ""
	if user != nil {
		name = user.Name
	}

	msg := &ChatMessage{
		Seq:       atomic.AddInt64(&c.messageSeq, 1),
		Type:      "chat_leave",
		Timestamp: time.Now().Format("15:04:05"),
		From:      call,
		FromName:  name,
		Node:      node,
		Message:   fmt.Sprintf("%s left", call),
	}
	c.broadcastMessage(msg)
}

// handleDataMessage processes a chat message
func (c *ChatClient) handleDataMessage(node, call, text string) {
	// Check for $TH status message from TARPN Home
	if thInfo := parseTHMessage(text); thInfo != nil {
		chatLog.Infow("$TH status parsed",
			"node", node,
			"call", call,
			"status", thInfo.Status,
			"version", thInfo.Version,
			"timestamp", thInfo.Timestamp)

		// Update user's status in the user list
		key := call + "@" + node
		c.usersMu.Lock()
		if user, ok := c.users[key]; ok {
			user.Status = thInfo.Status
			user.StatusTime = thInfo.Timestamp
			user.THVersion = thInfo.Version
		}
		c.usersMu.Unlock()

		// Broadcast updated user list so frontends see new status
		c.broadcastUserList()

		// Also broadcast as a chat_th message (hidden by default in frontend)
		c.usersMu.RLock()
		user := c.users[key]
		c.usersMu.RUnlock()
		name := ""
		if user != nil {
			name = user.Name
		}
		msg := &ChatMessage{
			Seq:       atomic.AddInt64(&c.messageSeq, 1),
			Type:      "chat_th",
			Timestamp: time.Now().Format("15:04:05"),
			From:      call,
			FromName:  name,
			Node:      node,
			Message:   fmt.Sprintf("Status: %s (v%s)", thInfo.Status, thInfo.Version),
		}
		c.broadcastMessage(msg)
		return
	}

	c.usersMu.RLock()
	user := c.users[call+"@"+node]
	c.usersMu.RUnlock()

	name := ""
	if user != nil {
		name = user.Name
	}

	msg := &ChatMessage{
		Seq:       atomic.AddInt64(&c.messageSeq, 1),
		Type:      "chat_msg",
		Timestamp: time.Now().Format("15:04:05"),
		From:      call,
		FromName:  name,
		Node:      node,
		Message:   text,
	}
	c.broadcastMessage(msg)
}

// handleTopicChange processes a topic change
func (c *ChatClient) handleTopicChange(node, call, topic string) {
	c.usersMu.RLock()
	user := c.users[call+"@"+node]
	c.usersMu.RUnlock()

	name := ""
	if user != nil {
		name = user.Name
	}

	msg := &ChatMessage{
		Seq:       atomic.AddInt64(&c.messageSeq, 1),
		Type:      "chat_topic",
		Timestamp: time.Now().Format("15:04:05"),
		From:      call,
		FromName:  name,
		Node:      node,
		Topic:     topic,
		Message:   fmt.Sprintf("%s changed topic to %s", call, topic),
	}
	c.broadcastMessage(msg)
}

// SendMessage sends a chat message
func (c *ChatClient) SendMessage(text string) error {
	c.mu.RLock()
	wsConn := c.wsConn
	state := c.state
	c.mu.RUnlock()

	if state != StateConnected {
		return fmt.Errorf("not connected to chat server")
	}
	if wsConn == nil {
		return fmt.Errorf("not connected to chat server")
	}

	chatLog.Debugf("SendMessage called with: %q", text)

	// WebSocket JSON protocol: {"cmd": "send_data", "text": "..."}
	cmd := map[string]string{
		"cmd":  "send_data",
		"text": text,
	}
	err := wsConn.WriteJSON(cmd)
	chatLog.Debugf("Sent WebSocket send_data command: %+v", cmd)

	return err
}

// SendCommand sends a chat command (e.g., /topic, /users)
func (c *ChatClient) SendCommand(cmd string) error {
	return c.SendMessage(cmd)
}

// GetSettings returns current chat settings
func (c *ChatClient) GetSettings() *ChatSettings {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return &ChatSettings{
		Type:  "chat_settings",
		Name:  c.userName,
		QTH:   c.userQTH,
		Topic: c.currentTopic,
	}
}

// SetNameAndQTH updates the user's name and QTH, sending a set_info command to the server
func (c *ChatClient) SetNameAndQTH(name, qth string) error {
	c.mu.Lock()
	wsConn := c.wsConn
	state := c.state

	if state != StateConnected {
		c.mu.Unlock()
		return fmt.Errorf("not connected to chat server")
	}
	if wsConn == nil {
		c.mu.Unlock()
		return fmt.Errorf("not connected to chat server")
	}

	// Update local state
	if name != "" {
		c.userName = name
	}
	c.userQTH = qth

	userName := c.userName
	userQTH := c.userQTH
	c.mu.Unlock()

	if userQTH == "" {
		userQTH = "TARPN-Mon"
	}

	// WebSocket JSON protocol: {"cmd": "set_info", "name": "...", "qth": "..."}
	cmd := map[string]string{
		"cmd":  "set_info",
		"name": userName,
		"qth":  userQTH,
	}
	if err := wsConn.WriteJSON(cmd); err != nil {
		return fmt.Errorf("failed to send set_info: %w", err)
	}
	chatLog.Debugw("Sent WebSocket set_info command", "name", userName, "qth", userQTH)

	// Persist to settings file so name/QTH survive restarts
	if fs := appSettings.GetFeature("chat"); fs != nil {
		if fs.Options == nil {
			fs.Options = map[string]string{}
		}
		fs.Options["name"] = userName
		fs.Options["qth"] = c.userQTH // Save the raw value (not the "TARPN-Mon" default)
		if err := appSettings.SetFeature("chat", fs); err != nil {
			chatLog.Warnw("Failed to persist chat name/QTH to settings", "error", err)
		}
	}

	return nil
}

// SetTopic changes the current topic
func (c *ChatClient) SetTopic(topic string) error {
	c.mu.Lock()
	wsConn := c.wsConn
	state := c.state

	if state != StateConnected {
		c.mu.Unlock()
		return fmt.Errorf("not connected to chat server")
	}
	if wsConn == nil {
		c.mu.Unlock()
		return fmt.Errorf("not connected to chat server")
	}

	c.currentTopic = topic
	c.mu.Unlock()

	// WebSocket JSON protocol: {"cmd": "set_topic", "topic": "..."}
	cmd := map[string]string{
		"cmd":   "set_topic",
		"topic": topic,
	}
	if err := wsConn.WriteJSON(cmd); err != nil {
		return fmt.Errorf("failed to send set_topic: %w", err)
	}
	chatLog.Debugf("Sent WebSocket set_topic command: %+v", cmd)

	return nil
}

// GetUsers returns the current list of chat users
func (c *ChatClient) GetUsers() []ChatUser {
	c.usersMu.RLock()
	defer c.usersMu.RUnlock()

	users := make([]ChatUser, 0, len(c.users))
	for _, user := range c.users {
		users = append(users, *user)
	}
	return users
}

// IsConnected returns whether the chat client is connected
func (c *ChatClient) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.state == StateConnected
}

// GetStatus returns the current feature status
func (c *ChatClient) GetStatus() FeatureStatus {
	c.mu.RLock()
	defer c.mu.RUnlock()

	status := FeatureStatus{
		Feature:  "chat",
		State:    c.state,
		Callsign: c.callsign,
		Host:     c.hostname,
		Port:     c.port,
		Error:    c.lastError,
	}
	if c.connectedAt != nil {
		status.ConnectedAt = c.connectedAt
	}
	return status
}

// Disconnect gracefully disconnects from the chat server
func (c *ChatClient) Disconnect() error {
	chatLog.Infof("Disconnect requested")
	c.mu.Lock()
	if c.state != StateConnected && c.state != StateConnecting {
		c.mu.Unlock()
		chatLog.Debugf("Disconnect called but not connected (state=%v)", c.state)
		return fmt.Errorf("not connected")
	}
	c.state = StateDisconnecting
	c.mu.Unlock()

	BroadcastFeatureStatus(c.GetStatus())

	// Cancel context to stop the Run loop
	chatLog.Debugf("Cancelling context")
	c.cancel()

	c.mu.Lock()
	c.disconnectRequested = true // Mark as intentional disconnect - don't auto-reconnect

	if c.wsConn != nil {
		// Send leave command before closing
		chatLog.Debugf("Sending leave command via WebSocket")
		leaveCmd := map[string]string{"cmd": "leave"}
		c.wsConn.WriteJSON(leaveCmd)
		time.Sleep(100 * time.Millisecond)
		c.wsConn.Close()
		c.wsConn = nil
	}
	c.state = StateDisconnected
	c.connectedAt = nil

	// Create new context for potential reconnection
	c.ctx, c.cancel = context.WithCancel(context.Background())
	c.mu.Unlock()

	chatLog.Infof("Disconnected")
	BroadcastFeatureStatus(c.GetStatus())
	c.broadcastStatus(false)

	return nil
}

// Close shuts down the chat client (alias for Disconnect)
func (c *ChatClient) Close() {
	c.Disconnect()
}

// broadcastMessage sends a message to all connected chat WebSocket clients
func (c *ChatClient) broadcastMessage(msg *ChatMessage) {
	jsonData, err := json.Marshal(msg)
	if err != nil {
		chatLog.Errorf("Error marshalling chat message: %v", err)
		return
	}

	msgStr := string(jsonData)

	// Persist to storage (storage handles filtering of ephemeral messages)
	if chatBuffer != nil {
		chatBuffer.AddMessage(msg)
	}

	chatClientsMu.RLock()
	defer chatClientsMu.RUnlock()

	for client := range chatClients {
		if err := client.write(msgStr); err != nil {
			chatLog.Errorf("Chat websocket error: %v", err)
			go client.kill()
		}
	}
}

// broadcastStatus sends connection status to all chat clients
func (c *ChatClient) broadcastStatus(connected bool) {
	msg := &ChatMessage{
		Seq:       atomic.AddInt64(&c.messageSeq, 1),
		Type:      "chat_status",
		Timestamp: time.Now().Format("15:04:05"),
		Connected: connected,
	}
	c.broadcastMessage(msg)
}

// broadcastUserList sends the current user list to all browser WebSocket clients
func (c *ChatClient) broadcastUserList() {
	users := c.GetUsers()
	msg := &ChatMessage{
		Type:  "chat_users",
		Users: users,
	}
	jsonData, err := json.Marshal(msg)
	if err != nil {
		chatLog.Errorf("Error marshalling user list: %v", err)
		return
	}

	msgStr := string(jsonData)

	chatClientsMu.RLock()
	defer chatClientsMu.RUnlock()

	for client := range chatClients {
		if err := client.write(msgStr); err != nil {
			chatLog.Errorf("Chat websocket error: %v", err)
			go client.kill()
		}
	}
}

// initChatManager initializes the chat manager (called from main, lazy mode)
func initChatManager() {
	var err error
	chatBuffer, err = NewSQLiteChatStorage("chat.db")
	if err != nil {
		chatLog.Warnw("Failed to initialize chat storage, using memory fallback", "error", err)
		chatBuffer = NewMemoryChatStorage() // Fallback
	}
	chatClient = NewChatClient()
	chatManager = chatClient
}

// ConnectChat connects the chat feature with the given configuration
func ConnectChat(config FeatureConfig) error {
	chatLog.Infow("ConnectChat called", "host", config.Host, "port", config.Port, "callsign", config.Callsign)

	// Check if already connected BEFORE starting goroutine so we can return error
	if chatClient != nil && chatClient.IsConnected() {
		chatLog.Debugf("Already connected, returning error")
		return fmt.Errorf("chat: %w", ErrAlreadyConnected)
	}

	if chatClient == nil {
		chatLog.Debugf("Initializing chat manager")
		initChatManager()
	}

	// Set callsign for storage filtering - shows only history for this user
	if chatBuffer != nil {
		chatBuffer.SetCallsign(config.Callsign)
		// Initialize messageSeq from storage to avoid duplicate seq numbers
		info := chatBuffer.GetBufferInfo()
		if info.MaxSeq > 0 {
			atomic.StoreInt64(&chatClient.messageSeq, info.MaxSeq)
			chatLog.Debugf("Initialized messageSeq from storage: %d", info.MaxSeq)
		}
	}

	// Start connection in background with auto-reconnect
	go func() {
		for {
			if err := chatClient.ConnectWithConfig(config); err != nil {
				chatLog.Warnf("Connection failed: %v, retrying in 30s", err)
				time.Sleep(30 * time.Second)
				continue
			}

			chatClient.Run()

			// Check if we were intentionally disconnected
			chatClient.mu.RLock()
			intentional := chatClient.disconnectRequested
			chatClient.mu.RUnlock()
			if intentional {
				chatLog.Infof("Disconnected by user, not auto-reconnecting")
				return
			}

			// Connection lost unexpectedly, wait before reconnecting
			chatLog.Warnf("Connection lost unexpectedly, reconnecting in 10s")
			time.Sleep(10 * time.Second)
		}
	}()

	return nil
}

// DisconnectChat disconnects the chat feature
func DisconnectChat() error {
	if chatClient == nil {
		return fmt.Errorf("chat not initialized")
	}
	return chatClient.Disconnect()
}

// GetChatStatus returns the current chat status
func GetChatStatus() FeatureStatus {
	if chatClient == nil {
		return FeatureStatus{
			Feature: "chat",
			State:   StateDisconnected,
		}
	}
	return chatClient.GetStatus()
}
