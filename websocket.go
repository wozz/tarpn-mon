package main

import (
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// BroadcastNeighborCQ broadcasts a decoded neighbor CQ stats message to all WebSocket clients.
// Called from the monitor loop in main.go when an [LS1] CQ broadcast is detected.
func BroadcastNeighborCQ(rxPort int, msg *LinkStatCQMessage) {
	data := map[string]interface{}{
		"type":           "neighbor_link_stats",
		"callsign":       msg.Callsign,
		"reportedPort":   msg.PortNum,
		"rxPort":         rxPort,
		"l2Rxed":         msg.L2Rxed,
		"l2Sent":         msg.L2Sent,
		"l2Timeouts":     msg.L2Timeouts,
		"rejRxed":        msg.REJRxed,
		"rxCrcErrors":    msg.RXCRCErrors,
		"abandoned":      msg.Abandoned,
		"activeTxPct":    msg.ActiveTxPct,
		"activeBusyPct":  msg.ActiveBusyPct,
		"timestamp":      time.Now().UTC().Format(time.RFC3339),
	}
	jsonData, err := json.Marshal(data)
	if err != nil {
		wsLog.Errorw("Failed to marshal neighbor CQ", "error", err)
		return
	}
	broadcastDirect(string(jsonData))
}

// ErrAlreadyConnected is returned when trying to connect a feature that's already connected
var ErrAlreadyConnected = errors.New("already connected")

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow connections from any origin (for development)
	},
}

type ClientCommand struct {
	Cmd       string `json:"cmd"`
	LastSeq   int64  `json:"last_seq"`    // for "sync" - get messages after this seq
	BeforeSeq int64  `json:"before_seq"`  // for "load_before" - get messages before this seq
	Limit     int    `json:"limit"`       // for "latest" and "load_before" - max items to return

	// Feature connection fields
	Feature  string            `json:"feature,omitempty"`  // "chat", "bbs", "node"
	Host     string            `json:"host,omitempty"`
	Port     int               `json:"port,omitempty"`
	Callsign string            `json:"callsign,omitempty"`
	Password string            `json:"password,omitempty"`
	Options  map[string]string `json:"options,omitempty"`

	// Settings update fields
	Settings *FeatureSettings `json:"settings,omitempty"` // for update_settings

	// Link stats fields
	PortNum int `json:"port_num,omitempty"` // for get_link_stats_history
	Hours   int `json:"hours,omitempty"`    // for get_link_stats_history
}

// linkStatsCollectorRef holds a reference to the stats collector for WebSocket handlers
var linkStatsCollectorRef *LinkStatsCollector

// sessionTrackerRef holds a reference to the session tracker for WebSocket handlers
var sessionTrackerRef *SessionTracker

// BroadcastSessionUpdate sends a session update to all WebSocket clients.
// Used as the onChange callback for SessionTracker.
func BroadcastSessionUpdate(session *Session) {
	msg := map[string]interface{}{
		"type":    "session_update",
		"session": session,
	}
	data, err := json.Marshal(msg)
	if err != nil {
		wsLog.Errorw("Failed to marshal session update", "error", err)
		return
	}
	broadcastDirect(string(data))
}

func websocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		wsLog.Errorw("WebSocket upgrade failed", "error", err)
		return
	}
	wc := &websocketConn{
		wc: conn,
	}
	defer wc.kill()

	clientsMu.Lock()
	clients[wc] = true
	clientsMu.Unlock()
	UpdateWebSocketClientCount()

	defer func() {
		clientsMu.Lock()
		delete(clients, wc)
		clientsMu.Unlock()
		UpdateWebSocketClientCount()
	}()

	// Send initial status with buffer info and feature statuses
	minSeq, maxSeq, count := dataBuffer.getInfo()

	chatFS := appSettings.GetFeature("chat")
	bbsFS := appSettings.GetFeature("bbs")
	nodeFS := appSettings.GetFeature("node")

	initMsg := map[string]interface{}{
		"type": "init",
		"buffer": map[string]interface{}{
			"minSeq":   minSeq,
			"maxSeq":   maxSeq,
			"count":    count,
			"capacity": bufferSize,
		},
		"features": map[string]bool{
			"chat": chatFS != nil && chatFS.Enabled,
			"bbs":  bbsFS != nil && bbsFS.Enabled,
			"node": nodeFS != nil && nodeFS.Enabled,
		},
		"featureStatuses": GetAllFeatureStatuses(),
		"featureEnabled":  true, // Signal that dynamic feature connections are supported
		"featureSettings": appSettings.GetAllFeatures(),
	}
	if sessionTrackerRef != nil {
		initMsg["sessions"] = sessionTrackerRef.GetSessions()
	}
	if initData, err := json.Marshal(initMsg); err == nil {
		wc.write(string(initData))
	}

	// Read loop to handle commands
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			wsLog.Debugw("WebSocket connection closed", "error", err)
			break
		}

		var cmd ClientCommand
		if err := json.Unmarshal(msg, &cmd); err == nil {
			switch cmd.Cmd {
			case "sync":
				// Get messages after last_seq (for live updates after initial load)
				history := dataBuffer.getSince(cmd.LastSeq)
				for _, message := range history {
					if err := wc.write(message); err != nil {
						return
					}
				}

			case "latest":
				// Get the last N messages (for initial load)
				limit := cmd.Limit
				if limit <= 0 {
					limit = 1000 // default
				}
				if limit > 5000 {
					limit = 5000 // max
				}
				messages := dataBuffer.getLatest(limit)
				for _, message := range messages {
					if err := wc.write(message); err != nil {
						return
					}
				}

			case "load_before":
				// Get messages before a sequence (for scrollback/pagination)
				limit := cmd.Limit
				if limit <= 0 {
					limit = 500 // default
				}
				if limit > 2000 {
					limit = 2000 // max
				}
				messages := dataBuffer.getBefore(cmd.BeforeSeq, limit)
				for _, message := range messages {
					if err := wc.write(message); err != nil {
						return
					}
				}
				// Send end marker so client knows we're done
				endMsg := map[string]interface{}{
					"type":      "load_complete",
					"beforeSeq": cmd.BeforeSeq,
					"count":     len(messages),
				}
				if endData, err := json.Marshal(endMsg); err == nil {
					wc.write(string(endData))
				}

			case "status":
				// Get current buffer status
				minSeq, maxSeq, count := dataBuffer.getInfo()
				statusMsg := map[string]interface{}{
					"type": "status",
					"buffer": map[string]interface{}{
						"minSeq":   minSeq,
						"maxSeq":   maxSeq,
						"count":    count,
						"capacity": bufferSize,
					},
				}
				if statusData, err := json.Marshal(statusMsg); err == nil {
					wc.write(string(statusData))
				}

			case "get_sessions":
				// Return current session table
				if sessionTrackerRef != nil {
					sessMsg := map[string]interface{}{
						"type":     "sessions",
						"sessions": sessionTrackerRef.GetSessions(),
					}
					if sessData, err := json.Marshal(sessMsg); err == nil {
						wc.write(string(sessData))
					}
				}

			case "feature_connect":
				// Connect to a feature using stored settings
				fs := appSettings.GetFeature(cmd.Feature)
				if fs == nil {
					wsLog.Infow("Unknown feature for connect", "feature", cmd.Feature)
					continue
				}
				config := fs.ToFeatureConfig()

				// Mark as enabled and save
				fs.Enabled = true
				if err := appSettings.SetFeature(cmd.Feature, fs); err != nil {
					wsLog.Warnw("Failed to save settings on connect", "feature", cmd.Feature, "error", err)
				}

				var connectErr error
				switch cmd.Feature {
				case "chat":
					connectErr = ConnectChat(config)
				case "bbs":
					connectErr = ConnectBBS(config)
				case "node":
					connectErr = ConnectNode(config)
				default:
					wsLog.Infow("Unknown feature for connect", "feature", cmd.Feature)
					continue
				}

				if connectErr != nil {
					wsLog.Warnw("Feature connect failed", "feature", cmd.Feature, "error", connectErr)
					if errors.Is(connectErr, ErrAlreadyConnected) {
						var status FeatureStatus
						switch cmd.Feature {
						case "chat":
							status = GetChatStatus()
						case "bbs":
							status = GetBBSStatus()
						case "node":
							status = GetNodeStatus()
						}
						status.Type = "feature_status"
						wsLog.Infow("Feature already connected, sending status", "feature", cmd.Feature)
						if statusData, err := json.Marshal(status); err == nil {
							wc.write(string(statusData))
						}
					} else {
						errStatus := FeatureStatus{
							Type:    "feature_status",
							Feature: cmd.Feature,
							State:   StateError,
							Error:   connectErr.Error(),
						}
						if errData, err := json.Marshal(errStatus); err == nil {
							wc.write(string(errData))
						}
					}
				}
				// Broadcast updated settings to all clients
				broadcastSettings()

			case "feature_disconnect":
				// Disconnect from a feature and mark disabled
				var err error
				switch cmd.Feature {
				case "chat":
					err = DisconnectChat()
				case "bbs":
					err = DisconnectBBS()
				case "node":
					err = DisconnectNode()
				default:
					wsLog.Infow("Unknown feature for disconnect", "feature", cmd.Feature)
				}

				if err != nil {
					wsLog.Warnw("Feature disconnect failed", "feature", cmd.Feature, "error", err)
				}

				// Mark feature as disabled in settings
				if fs := appSettings.GetFeature(cmd.Feature); fs != nil {
					fs.Enabled = false
					if err := appSettings.SetFeature(cmd.Feature, fs); err != nil {
						wsLog.Warnw("Failed to save settings on disconnect", "feature", cmd.Feature, "error", err)
					}
					broadcastSettings()
				}

			case "get_link_stats":
				// Return latest link stats snapshot
				if linkStatsCollectorRef != nil {
					snap := linkStatsCollectorRef.GetLatestSnapshot()
					if snap != nil {
						BroadcastLinkStats(snap) // reuse the same format
					}
				}

			case "get_link_stats_history":
				// Return hourly summaries for a port
				if linkStatsCollectorRef != nil && linkStatsCollectorRef.storage != nil {
					hours := cmd.Hours
					if hours <= 0 {
						hours = 24
					}
					if hours > 720 { // max 30 days
						hours = 720
					}
					since := time.Now().Add(-time.Duration(hours) * time.Hour)
					summaries, err := linkStatsCollectorRef.storage.GetHourlySummary(cmd.PortNum, since)
					if err != nil {
						wsLog.Warnw("Failed to get link stats history", "error", err)
					} else {
						histMsg := map[string]interface{}{
							"type":    "link_stats_history",
							"portNum": cmd.PortNum,
							"hours":   hours,
							"data":    summaries,
						}
						if histData, err := json.Marshal(histMsg); err == nil {
							wc.write(string(histData))
						}
					}
				}

			case "feature_status":
				// Get status of all features or a specific one
				if cmd.Feature != "" {
					var status FeatureStatus
					switch cmd.Feature {
					case "chat":
						status = GetChatStatus()
					case "bbs":
						status = GetBBSStatus()
					case "node":
						status = GetNodeStatus()
					}
					status.Type = "feature_status"
					if statusData, err := json.Marshal(status); err == nil {
						wc.write(string(statusData))
					}
				} else {
					// Send all feature statuses
					for _, status := range GetAllFeatureStatuses() {
						status.Type = "feature_status"
						if statusData, err := json.Marshal(status); err == nil {
							wc.write(string(statusData))
						}
					}
				}

			case "get_settings":
				// Return all feature settings
				settingsMsg := map[string]interface{}{
					"type":     "settings",
					"features": appSettings.GetAllFeatures(),
				}
				if data, err := json.Marshal(settingsMsg); err == nil {
					wc.write(string(data))
				}

			case "update_settings":
				// Update a single feature's settings
				if cmd.Feature == "" || cmd.Settings == nil {
					wsLog.Warnw("update_settings: missing feature or settings")
					continue
				}
				feature := cmd.Feature
				newSettings := cmd.Settings

				// Get current settings to detect changes
				oldSettings := appSettings.GetFeature(feature)
				if oldSettings == nil {
					wsLog.Warnw("update_settings: unknown feature", "feature", feature)
					continue
				}

				// Save the new settings
				if err := appSettings.SetFeature(feature, newSettings); err != nil {
					wsLog.Warnw("Failed to save settings", "feature", feature, "error", err)
					continue
				}

				// Determine what action to take based on changes
				wasEnabled := oldSettings.Enabled
				nowEnabled := newSettings.Enabled
				credentialsChanged := oldSettings.Host != newSettings.Host ||
					oldSettings.Port != newSettings.Port ||
					oldSettings.Callsign != newSettings.Callsign ||
					oldSettings.Password != newSettings.Password

				switch {
				case !wasEnabled && nowEnabled:
					// Newly enabled — connect
					config := newSettings.ToFeatureConfig()
					connectFeatureByName(feature, config)
				case wasEnabled && !nowEnabled:
					// Disabled — disconnect
					disconnectFeatureByName(feature)
				case wasEnabled && nowEnabled && credentialsChanged:
					// Credentials changed while connected — reconnect
					disconnectFeatureByName(feature)
					// Small delay to allow disconnect to complete
					go func() {
						time.Sleep(500 * time.Millisecond)
						config := appSettings.GetFeature(feature).ToFeatureConfig()
						connectFeatureByName(feature, config)
					}()
				}

				// Broadcast updated settings to all clients
				broadcastSettings()
			}
		} else {
			wsLog.Warnw("Invalid JSON command", "raw", string(msg))
		}
	}
}

// broadcastSettings sends current feature settings to all connected WebSocket clients.
func broadcastSettings() {
	settingsMsg := map[string]interface{}{
		"type":     "settings",
		"features": appSettings.GetAllFeatures(),
	}
	data, err := json.Marshal(settingsMsg)
	if err != nil {
		wsLog.Errorw("Failed to marshal settings", "error", err)
		return
	}
	broadcastDirect(string(data))
}

// connectFeatureByName connects a feature using the given config.
func connectFeatureByName(feature string, config FeatureConfig) {
	var err error
	switch feature {
	case "chat":
		err = ConnectChat(config)
	case "bbs":
		err = ConnectBBS(config)
	case "node":
		err = ConnectNode(config)
	}
	if err != nil && !errors.Is(err, ErrAlreadyConnected) {
		wsLog.Warnw("Feature connect failed", "feature", feature, "error", err)
	}
}

// disconnectFeatureByName disconnects a feature.
func disconnectFeatureByName(feature string) {
	var err error
	switch feature {
	case "chat":
		err = DisconnectChat()
	case "bbs":
		err = DisconnectBBS()
	case "node":
		err = DisconnectNode()
	}
	if err != nil {
		wsLog.Warnw("Feature disconnect failed", "feature", feature, "error", err)
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	content, err := static.ReadFile("web-dist/index.html")
	if err != nil {
		wsLog.Errorw("Failed to read index.html", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(content)
}

func versionHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte(Version))
}

// StatusResponse contains server status and feature flags
type StatusResponse struct {
	Version  string         `json:"version"`
	Features FeatureFlags   `json:"features"`
	Buffer   BufferInfo     `json:"buffer"`
}

// FeatureFlags indicates which features are enabled on the server
type FeatureFlags struct {
	Chat bool `json:"chat"`
	BBS  bool `json:"bbs"`
	Node bool `json:"node"`
}

// BufferInfo contains information about the message buffer
type BufferInfo struct {
	MinSeq   int64 `json:"minSeq"`
	MaxSeq   int64 `json:"maxSeq"`
	Count    int   `json:"count"`
	Capacity int   `json:"capacity"`
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	minSeq, maxSeq, count := dataBuffer.getInfo()

	chatFS := appSettings.GetFeature("chat")
	bbsFS := appSettings.GetFeature("bbs")
	nodeFS := appSettings.GetFeature("node")
	status := StatusResponse{
		Version: Version,
		Features: FeatureFlags{
			Chat: chatFS != nil && chatFS.Enabled,
			BBS:  bbsFS != nil && bbsFS.Enabled,
			Node: nodeFS != nil && nodeFS.Enabled,
		},
		Buffer: BufferInfo{
			MinSeq:   minSeq,
			MaxSeq:   maxSeq,
			Count:    count,
			Capacity: bufferSize,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func setupRoutes() {
	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/ws", websocketHandler)
	http.HandleFunc("/version", versionHandler)
	http.HandleFunc("/api/status", statusHandler)

	// Prometheus metrics endpoint
	SetupMetricsHandler()

	// Create a file server for the 'static' directory within the embedded FS.
	// The 'static' variable (embed.FS) is defined in main.go.
	distFS, err := fs.Sub(static, "web-dist")
	if err != nil {
		wsLog.Fatalf("failed to create sub FS for static assets: %v", err)
	}
	fileServer := http.FileServer(http.FS(distFS))

	http.Handle("/_expo/", fileServer)
	http.Handle("/assets/", fileServer)
	http.Handle("/favicon.ico", fileServer)
	http.Handle("/canvaskit.wasm", fileServer)
}

type websocketConn struct {
	mu sync.Mutex
	wc *websocket.Conn
}

func (w *websocketConn) write(message string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.wc.WriteMessage(websocket.TextMessage, []byte(message))
}

func (w *websocketConn) kill() {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.wc.Close()
}

var (
	clients   = make(map[*websocketConn]bool)
	clientsMu sync.RWMutex
)

func broadcast(seq int64, message string) {
	dataBuffer.add(seq, message)

	clientsMu.RLock()
	defer clientsMu.RUnlock()

	for client := range clients {
		err := client.write(message)
		if err != nil {
			wsLog.Debugw("Websocket write failed, closing connection", "error", err)
			go func(c *websocketConn) {
				c.kill()
			}(client)
		}
	}
}

// broadcastDirect sends a message to all connected WebSocket clients without
// adding it to the circular buffer. Used for periodic snapshots like link stats
// that shouldn't be mixed into the monitor log timeline.
func broadcastDirect(message string) {
	clientsMu.RLock()
	defer clientsMu.RUnlock()

	for client := range clients {
		err := client.write(message)
		if err != nil {
			go func(c *websocketConn) {
				c.kill()
			}(client)
		}
	}
}