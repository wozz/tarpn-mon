package main

import (
	"encoding/json"
	"net/http"
)

// BBSClientCommand represents a command from a WebSocket client
type BBSClientCommand struct {
	Cmd       string `json:"cmd"`       // "list", "read", "send", "delete", "enter", "exit", "status"
	ListType  string `json:"listType"`  // for "list" command: "LM", "LB", "LL 20", etc.
	Number    int    `json:"number"`    // for "read" and "delete" commands
	To        string `json:"to"`        // for "send" command
	Subject   string `json:"subject"`   // for "send" command
	Body      string `json:"body"`      // for "send" command
	Bulletin  bool   `json:"bulletin"`  // for "send" command - true for bulletin
}

// bbsWebsocketHandler handles WebSocket connections for BBS
func bbsWebsocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		bbsLog.Errorw("BBS WebSocket upgrade failed", "error", err)
		return
	}

	wc := &websocketConn{
		wc: conn,
	}
	defer wc.kill()

	// Register this client for BBS broadcasts
	bbsClientsMu.Lock()
	bbsClients[wc] = true
	bbsClientsMu.Unlock()
	UpdateBBSClientCount()

	defer func() {
		bbsClientsMu.Lock()
		delete(bbsClients, wc)
		bbsClientsMu.Unlock()
		UpdateBBSClientCount()
	}()

	// Send initial connection status
	if bbsClient != nil {
		status := &BBSClientMessage{
			Type:      "bbs_status",
			Connected: bbsClient.IsConnected(),
			InBBSMode: bbsClient.IsInBBSMode(),
		}
		if jsonData, err := json.Marshal(status); err == nil {
			wc.write(string(jsonData))
		}
	}

	// Read loop to handle commands
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			bbsLog.Debugw("BBS WebSocket closed", "error", err)
			break
		}

		var cmd BBSClientCommand
		if err := json.Unmarshal(msg, &cmd); err != nil {
			bbsLog.Warnw("Invalid BBS command JSON", "error", err, "raw", string(msg))
			continue
		}

		// Handle commands
		switch cmd.Cmd {
		case "status":
			if bbsClient != nil {
				status := &BBSClientMessage{
					Type:      "bbs_status",
					Connected: bbsClient.IsConnected(),
					InBBSMode: bbsClient.IsInBBSMode(),
				}
				if jsonData, err := json.Marshal(status); err == nil {
					wc.write(string(jsonData))
				}
			}

		case "enter":
			// Enter BBS mode
			if bbsClient != nil {
				if err := bbsClient.EnterBBS(); err != nil {
					errMsg := &BBSClientMessage{
						Type:  "bbs_error",
						Error: "Failed to enter BBS mode: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
			}

		case "exit":
			// Exit BBS mode
			if bbsClient != nil {
				if err := bbsClient.ExitBBS(); err != nil {
					errMsg := &BBSClientMessage{
						Type:  "bbs_error",
						Error: "Failed to exit BBS mode: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
			}

		case "list":
			// List messages - async, Run() will broadcast the results
			if bbsClient != nil {
				_, err := bbsClient.ListMessages(cmd.ListType)
				if err != nil {
					errMsg := &BBSClientMessage{
						Type:  "bbs_error",
						Error: "Failed to send list command: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
				// Results will come through Run() -> broadcastMessageList
			}

		case "read":
			// Read a message - async, Run() will broadcast the result
			if bbsClient != nil && cmd.Number > 0 {
				_, err := bbsClient.ReadMessage(cmd.Number)
				if err != nil {
					errMsg := &BBSClientMessage{
						Type:  "bbs_error",
						Error: "Failed to send read command: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
				// Result will come through Run() -> broadcastReadMessage
			}

		case "send":
			// Send a message
			if bbsClient != nil && cmd.To != "" && cmd.Subject != "" {
				msgNum, err := bbsClient.SendMessage(cmd.To, cmd.Subject, cmd.Body, cmd.Bulletin)
				if err != nil {
					errMsg := &BBSClientMessage{
						Type:  "bbs_error",
						Error: "Failed to send message: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				} else {
					sentMsg := &BBSClientMessage{
						Type:   "bbs_sent",
						Number: msgNum,
					}
					if jsonData, err := json.Marshal(sentMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
			}

		case "delete":
			// Delete a message
			if bbsClient != nil && cmd.Number > 0 {
				err := bbsClient.DeleteMessage(cmd.Number)
				if err != nil {
					errMsg := &BBSClientMessage{
						Type:  "bbs_error",
						Error: "Failed to delete message: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				} else {
					// Send success - just update status
					status := &BBSClientMessage{
						Type:      "bbs_status",
						Connected: bbsClient.IsConnected(),
						InBBSMode: bbsClient.IsInBBSMode(),
					}
					if jsonData, err := json.Marshal(status); err == nil {
						wc.write(string(jsonData))
					}
				}
			}
		}
	}
}

// setupBBSRoutes adds the BBS WebSocket route
func setupBBSRoutes() {
	http.HandleFunc("/ws/bbs", bbsWebsocketHandler)
}
