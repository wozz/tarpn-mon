package main

import (
	"encoding/json"
	"net/http"
)

// NodeClientCommand represents a command from a WebSocket client
type NodeClientCommand struct {
	Cmd     string `json:"cmd"`     // "exec", "status", "sync"
	Command string `json:"command"` // for "exec" - the raw command to send
	LastSeq int64  `json:"last_seq"` // for "sync" - last seen sequence number
}

// nodeWebsocketHandler handles WebSocket connections for the node console
func nodeWebsocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		nodeLog.Errorw("Node WebSocket upgrade failed", "error", err)
		return
	}

	wc := &websocketConn{
		wc: conn,
	}
	defer wc.kill()

	// Register this client for node broadcasts
	nodeClientsMu.Lock()
	nodeClients[wc] = true
	nodeClientsMu.Unlock()
	UpdateNodeClientCount()

	defer func() {
		nodeClientsMu.Lock()
		delete(nodeClients, wc)
		nodeClientsMu.Unlock()
		UpdateNodeClientCount()
	}()

	// Send initial connection status
	if nodeClient != nil {
		status := &NodeMessage{
			Type:      "node_status",
			Connected: nodeClient.IsConnected(),
			Prompt:    nodeClient.GetPrompt(),
		}
		if jsonData, err := json.Marshal(status); err == nil {
			wc.write(string(jsonData))
		}
	}

	// Read loop to handle commands
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			nodeLog.Debugw("Node WebSocket closed", "error", err)
			break
		}

		var cmd NodeClientCommand
		if err := json.Unmarshal(msg, &cmd); err != nil {
			nodeLog.Warnw("Invalid Node command JSON", "error", err, "raw", string(msg))
			continue
		}

		// Handle commands
		switch cmd.Cmd {
		case "status":
			if nodeClient != nil {
				status := &NodeMessage{
					Type:      "node_status",
					Connected: nodeClient.IsConnected(),
					Prompt:    nodeClient.GetPrompt(),
				}
				if jsonData, err := json.Marshal(status); err == nil {
					wc.write(string(jsonData))
				}
			}

		case "sync":
			// Send buffered messages since last_seq
			if nodeBuffer != nil {
				items := nodeBuffer.getSince(cmd.LastSeq)
				for _, item := range items {
					wc.write(item)
				}
			}

		case "exec":
			// Execute a command on the node
			if nodeClient != nil && cmd.Command != "" {
				if err := nodeClient.SendCommand(cmd.Command); err != nil {
					errMsg := &NodeMessage{
						Type:  "node_error",
						Error: "Failed to send command: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
			}
		}
	}
}

// setupNodeRoutes adds the node WebSocket route
func setupNodeRoutes() {
	http.HandleFunc("/ws/node", nodeWebsocketHandler)
}
