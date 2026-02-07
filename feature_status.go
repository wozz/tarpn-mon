package main

import (
	"encoding/json"
	"time"
)

// FeatureState represents the connection state of a feature
type FeatureState string

const (
	StateDisconnected  FeatureState = "disconnected"
	StateConnecting    FeatureState = "connecting"
	StateConnected     FeatureState = "connected"
	StateDisconnecting FeatureState = "disconnecting"
	StateError         FeatureState = "error"
)

// FeatureConfig contains connection configuration for a feature
type FeatureConfig struct {
	Host     string            `json:"host"`
	Port     int               `json:"port"`
	Callsign string            `json:"callsign"`
	Password string            `json:"password"`
	Options  map[string]string `json:"options,omitempty"`
}

// FeatureStatus represents the current status of a feature connection
type FeatureStatus struct {
	Type        string       `json:"type"` // Always "feature_status"
	Feature     string       `json:"feature"`
	State       FeatureState `json:"state"`
	Callsign    string       `json:"callsign,omitempty"`
	Host        string       `json:"host,omitempty"`
	Port        int          `json:"port,omitempty"`
	Error       string       `json:"error,omitempty"`
	ConnectedAt *time.Time   `json:"connectedAt,omitempty"`
}

// FeatureManager interface for features that support dynamic connections
type FeatureManager interface {
	Connect(config FeatureConfig) error
	Disconnect() error
	GetStatus() FeatureStatus
	IsConnected() bool
}

// BroadcastFeatureStatus sends a feature status update to all connected WebSocket clients
func BroadcastFeatureStatus(status FeatureStatus) {
	status.Type = "feature_status"

	// Update Prometheus metrics for feature state
	UpdateFeatureStateMetrics(status.Feature, status.State)

	data, err := json.Marshal(status)
	if err != nil {
		wsLog.Errorw("Failed to marshal feature status", "error", err, "feature", status.Feature)
		return
	}

	// Broadcast to all connected clients
	clientsMu.RLock()
	defer clientsMu.RUnlock()

	for client := range clients {
		if err := client.write(string(data)); err != nil {
			wsLog.Debugw("Feature status broadcast failed", "error", err, "feature", status.Feature)
			go client.kill()
		}
	}
}

// GetAllFeatureStatuses returns the current status of all features
func GetAllFeatureStatuses() map[string]FeatureStatus {
	statuses := make(map[string]FeatureStatus)

	statuses["chat"] = GetChatStatus()
	statuses["bbs"] = GetBBSStatus()
	statuses["node"] = GetNodeStatus()

	return statuses
}

