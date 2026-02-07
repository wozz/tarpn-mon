package main

import (
	"encoding/json"
	"net/http"
)

// ChatClientCommand represents a command from a WebSocket client
type ChatClientCommand struct {
	Cmd       string `json:"cmd"`        // "send", "sync", "latest", "load_before", "users", "command", "set_name", "set_topic", "get_settings"
	Message   string `json:"message"`    // for "send" command
	LastSeq   int64  `json:"last_seq"`   // for "sync" command
	BeforeSeq int64  `json:"before_seq"` // for "load_before" command
	Limit     int    `json:"limit"`      // for "latest" and "load_before" commands
	Name      string `json:"name"`       // for "set_name" command
	QTH       string `json:"qth"`        // for "set_name" command (sent together with name)
	Topic     string `json:"topic"`      // for "set_topic" command
}

// ChatInitMessage is sent to clients on connection
type ChatInitMessage struct {
	Type   string         `json:"type"`
	Buffer ChatBufferInfo `json:"buffer"`
}

// chatWebsocketHandler handles WebSocket connections for chat
func chatWebsocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		chatLog.Errorw("Chat WebSocket upgrade failed", "error", err)
		return
	}

	wc := &websocketConn{
		wc: conn,
	}
	defer wc.kill()

	// Register this client for chat broadcasts
	chatClientsMu.Lock()
	chatClients[wc] = true
	chatClientsMu.Unlock()
	UpdateChatClientCount()

	defer func() {
		chatClientsMu.Lock()
		delete(chatClients, wc)
		chatClientsMu.Unlock()
		UpdateChatClientCount()
	}()

	// Send init message with buffer info
	if chatBuffer != nil {
		initMsg := ChatInitMessage{
			Type:   "chat_init",
			Buffer: chatBuffer.GetBufferInfo(),
		}
		if jsonData, err := json.Marshal(initMsg); err == nil {
			wc.write(string(jsonData))
		}
	}

	// Send initial connection status
	if chatClient != nil {
		status := &ChatMessage{
			Type:      "chat_status",
			Connected: chatClient.IsConnected(),
		}
		if jsonData, err := json.Marshal(status); err == nil {
			wc.write(string(jsonData))
		}
	}

	// Read loop to handle commands
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			chatLog.Debugw("Chat WebSocket closed", "error", err)
			break
		}

		var cmd ChatClientCommand
		if err := json.Unmarshal(msg, &cmd); err != nil {
			chatLog.Warnw("Invalid chat command JSON", "error", err, "raw", string(msg))
			continue
		}

		chatLog.Debugw("Chat WS command", "cmd", cmd.Cmd)

		switch cmd.Cmd {
		case "latest":
			// Initial load - get latest N messages
			if chatBuffer != nil {
				limit := cmd.Limit
				if limit <= 0 || limit > 500 {
					limit = 200 // Default to 200 messages
				}
				messages := chatBuffer.GetLatestMessages(limit)
				for _, msg := range messages {
					jsonStr := chatMessageToJSON(msg)
					if jsonStr != "" {
						if err := wc.write(jsonStr); err != nil {
							return
						}
					}
				}
			}

		case "load_before":
			// Pagination - load older messages before a given seq
			if chatBuffer != nil {
				limit := cmd.Limit
				if limit <= 0 || limit > 500 {
					limit = 200
				}
				messages := chatBuffer.GetMessagesBefore(cmd.BeforeSeq, limit)
				for _, msg := range messages {
					jsonStr := chatMessageToJSON(msg)
					if jsonStr != "" {
						if err := wc.write(jsonStr); err != nil {
							return
						}
					}
				}

				// Send completion message so frontend knows when to stop loading
				bufInfo := chatBuffer.GetBufferInfo()
				var oldestLoaded int64
				if len(messages) > 0 {
					oldestLoaded = messages[0].Seq
				}
				hasMore := len(messages) > 0 && oldestLoaded > bufInfo.MinSeq

				completeMsg := map[string]interface{}{
					"type":    "load_before_complete",
					"count":   len(messages),
					"hasMore": hasMore,
					"minSeq":  bufInfo.MinSeq,
				}
				if jsonData, err := json.Marshal(completeMsg); err == nil {
					wc.write(string(jsonData))
				}
			}

		case "sync":
			// Send message history since last_seq (for reconnection)
			if chatBuffer != nil {
				messages := chatBuffer.GetMessagesSince(cmd.LastSeq)
				for _, msg := range messages {
					jsonStr := chatMessageToJSON(msg)
					if jsonStr != "" {
						if err := wc.write(jsonStr); err != nil {
							return
						}
					}
				}
			}

		case "send":
			// Send a chat message
			if chatClient != nil && cmd.Message != "" {
				if err := chatClient.SendMessage(cmd.Message); err != nil {
					chatLog.Warnw("Failed to send chat message", "error", err)
					// Send error back to client
					errMsg := &ChatMessage{
						Type:    "chat_error",
						Message: "Failed to send message: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				}
			}

		case "command":
			// Send a chat command (e.g., /topic, /users)
			if chatClient != nil && cmd.Message != "" {
				if err := chatClient.SendCommand(cmd.Message); err != nil {
					chatLog.Warnw("Failed to send chat command", "error", err, "command", cmd.Message)
				}
			}

		case "users":
			// Get current user list
			if chatClient != nil {
				users := chatClient.GetUsers()
				usersMsg := &ChatMessage{
					Type:  "chat_users",
					Users: users,
				}
				if jsonData, err := json.Marshal(usersMsg); err == nil {
					wc.write(string(jsonData))
				}
			}

		case "status":
			// Get connection status
			if chatClient != nil {
				status := &ChatMessage{
					Type:      "chat_status",
					Connected: chatClient.IsConnected(),
				}
				if jsonData, err := json.Marshal(status); err == nil {
					wc.write(string(jsonData))
				}
			}

		case "set_name":
			// Update name and QTH
			if chatClient != nil {
				if err := chatClient.SetNameAndQTH(cmd.Name, cmd.QTH); err != nil {
					chatLog.Warnw("Failed to set name/QTH", "error", err, "name", cmd.Name, "qth", cmd.QTH)
					errMsg := &ChatMessage{
						Type:    "chat_error",
						Message: "Failed to update name: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				} else {
					// Send updated settings back
					sendChatSettings(wc)
				}
			}

		case "set_topic":
			// Change topic
			if chatClient != nil && cmd.Topic != "" {
				if err := chatClient.SetTopic(cmd.Topic); err != nil {
					chatLog.Warnw("Failed to set topic", "error", err, "topic", cmd.Topic)
					errMsg := &ChatMessage{
						Type:    "chat_error",
						Message: "Failed to change topic: " + err.Error(),
					}
					if jsonData, err := json.Marshal(errMsg); err == nil {
						wc.write(string(jsonData))
					}
				} else {
					// Send updated settings back
					sendChatSettings(wc)
				}
			}

		case "get_settings":
			// Get current chat settings
			sendChatSettings(wc)
		}
	}
}

// sendChatSettings sends current chat settings to a WebSocket client
func sendChatSettings(wc *websocketConn) {
	if chatClient == nil {
		return
	}
	settings := chatClient.GetSettings()
	if jsonData, err := json.Marshal(settings); err == nil {
		wc.write(string(jsonData))
	}
}

// setupChatRoutes adds the chat WebSocket route
func setupChatRoutes() {
	http.HandleFunc("/ws/chat", chatWebsocketHandler)
}
