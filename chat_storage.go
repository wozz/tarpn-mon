package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"sync"

	_ "modernc.org/sqlite" // Pure Go SQLite, no CGO required
)

// ChatBufferInfo contains info about the chat message buffer
type ChatBufferInfo struct {
	MinSeq int64 `json:"minSeq"`
	MaxSeq int64 `json:"maxSeq"`
	Count  int   `json:"count"`
}

// ChatStorage defines the interface for chat message persistence
type ChatStorage interface {
	// SetCallsign sets the current user callsign for filtering
	SetCallsign(callsign string)
	// AddMessage stores a chat message for the current callsign
	AddMessage(msg *ChatMessage)
	// GetMessagesSince returns messages since seq for the current callsign
	GetMessagesSince(seq int64) []*ChatMessage
	// GetLatestMessages returns the most recent N messages for the current callsign
	GetLatestMessages(limit int) []*ChatMessage
	// GetMessagesBefore returns messages before the given seq (for pagination)
	GetMessagesBefore(beforeSeq int64, limit int) []*ChatMessage
	// GetBufferInfo returns info about the message buffer for the current callsign
	GetBufferInfo() ChatBufferInfo
	Close() error
}

// SQLiteChatStorage implements ChatStorage using SQLite
type SQLiteChatStorage struct {
	db       *sql.DB
	callsign string
	mu       sync.RWMutex
}

// NewSQLiteChatStorage creates a new SQLite-backed chat storage
func NewSQLiteChatStorage(dbPath string) (*SQLiteChatStorage, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Create table with structured columns
	createTableSQL := `
	CREATE TABLE IF NOT EXISTS chat_messages (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		seq INTEGER NOT NULL,
		session_callsign TEXT NOT NULL,
		msg_type TEXT NOT NULL,
		timestamp TEXT NOT NULL,
		sender_call TEXT,
		sender_name TEXT,
		sender_node TEXT,
		recipient TEXT,
		topic TEXT,
		message TEXT,
		connected INTEGER,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	CREATE INDEX IF NOT EXISTS idx_session_seq ON chat_messages(session_callsign, seq);
	`
	_, err = db.Exec(createTableSQL)
	if err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to create table: %w", err)
	}

	return &SQLiteChatStorage{db: db}, nil
}

// SetCallsign sets the current user callsign for filtering
func (s *SQLiteChatStorage) SetCallsign(callsign string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.callsign = strings.ToUpper(callsign)
}

// AddMessage stores a chat message
func (s *SQLiteChatStorage) AddMessage(msg *ChatMessage) {
	s.mu.RLock()
	callsign := s.callsign
	s.mu.RUnlock()

	// Skip ephemeral message types
	if msg.Type == "chat_users" || msg.Type == "chat_th" {
		return
	}

	var connected int
	if msg.Connected {
		connected = 1
	}

	_, err := s.db.Exec(`
		INSERT INTO chat_messages
		(seq, session_callsign, msg_type, timestamp, sender_call, sender_name, sender_node, recipient, topic, message, connected)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		msg.Seq, callsign, msg.Type, msg.Timestamp,
		msg.From, msg.FromName, msg.Node, msg.To, msg.Topic, msg.Message, connected)
	if err != nil {
		storageLog.Errorw("Failed to save chat message", "error", err, "seq", msg.Seq, "type", msg.Type)
	}
}

// GetMessagesSince returns messages since the given sequence number
func (s *SQLiteChatStorage) GetMessagesSince(seq int64) []*ChatMessage {
	s.mu.RLock()
	callsign := s.callsign
	s.mu.RUnlock()

	rows, err := s.db.Query(`
		SELECT seq, msg_type, timestamp, sender_call, sender_name, sender_node, recipient, topic, message, connected
		FROM chat_messages
		WHERE session_callsign = ? AND seq > ?
		ORDER BY seq ASC`, callsign, seq)
	if err != nil {
		storageLog.Errorw("Failed to query chat history", "error", err, "sinceSeq", seq)
		return nil
	}
	defer rows.Close()

	var messages []*ChatMessage
	for rows.Next() {
		var msg ChatMessage
		var senderCall, senderName, senderNode, recipient, topic, message sql.NullString
		var connected int

		if err := rows.Scan(&msg.Seq, &msg.Type, &msg.Timestamp,
			&senderCall, &senderName, &senderNode, &recipient, &topic, &message, &connected); err != nil {
			storageLog.Errorw("Failed to scan chat message", "error", err)
			continue
		}

		msg.From = senderCall.String
		msg.FromName = senderName.String
		msg.Node = senderNode.String
		msg.To = recipient.String
		msg.Topic = topic.String
		msg.Message = message.String
		msg.Connected = connected == 1

		messages = append(messages, &msg)
	}
	return messages
}

// GetLatestMessages returns the most recent N messages
func (s *SQLiteChatStorage) GetLatestMessages(limit int) []*ChatMessage {
	s.mu.RLock()
	callsign := s.callsign
	s.mu.RUnlock()

	// Use subquery to get latest N messages in correct order
	rows, err := s.db.Query(`
		SELECT seq, msg_type, timestamp, sender_call, sender_name, sender_node, recipient, topic, message, connected
		FROM (
			SELECT seq, msg_type, timestamp, sender_call, sender_name, sender_node, recipient, topic, message, connected
			FROM chat_messages
			WHERE session_callsign = ?
			ORDER BY seq DESC
			LIMIT ?
		) ORDER BY seq ASC`, callsign, limit)
	if err != nil {
		storageLog.Errorw("Failed to query latest chat messages", "error", err, "limit", limit)
		return nil
	}
	defer rows.Close()

	return s.scanMessages(rows)
}

// GetMessagesBefore returns messages before the given sequence number (for pagination)
func (s *SQLiteChatStorage) GetMessagesBefore(beforeSeq int64, limit int) []*ChatMessage {
	s.mu.RLock()
	callsign := s.callsign
	s.mu.RUnlock()

	// Use subquery to get messages before seq in correct order
	rows, err := s.db.Query(`
		SELECT seq, msg_type, timestamp, sender_call, sender_name, sender_node, recipient, topic, message, connected
		FROM (
			SELECT seq, msg_type, timestamp, sender_call, sender_name, sender_node, recipient, topic, message, connected
			FROM chat_messages
			WHERE session_callsign = ? AND seq < ?
			ORDER BY seq DESC
			LIMIT ?
		) ORDER BY seq ASC`, callsign, beforeSeq, limit)
	if err != nil {
		storageLog.Errorw("Failed to query chat messages before seq", "error", err, "beforeSeq", beforeSeq, "limit", limit)
		return nil
	}
	defer rows.Close()

	return s.scanMessages(rows)
}

// GetBufferInfo returns info about the message buffer for the current callsign
func (s *SQLiteChatStorage) GetBufferInfo() ChatBufferInfo {
	s.mu.RLock()
	callsign := s.callsign
	s.mu.RUnlock()

	var info ChatBufferInfo
	row := s.db.QueryRow(`
		SELECT COALESCE(MIN(seq), 0), COALESCE(MAX(seq), 0), COUNT(*)
		FROM chat_messages
		WHERE session_callsign = ?`, callsign)

	if err := row.Scan(&info.MinSeq, &info.MaxSeq, &info.Count); err != nil {
		storageLog.Errorw("Failed to query chat buffer info", "error", err, "callsign", callsign)
	}
	return info
}

// scanMessages is a helper to scan rows into ChatMessage slice
func (s *SQLiteChatStorage) scanMessages(rows *sql.Rows) []*ChatMessage {
	var messages []*ChatMessage
	for rows.Next() {
		var msg ChatMessage
		var senderCall, senderName, senderNode, recipient, topic, message sql.NullString
		var connected int

		if err := rows.Scan(&msg.Seq, &msg.Type, &msg.Timestamp,
			&senderCall, &senderName, &senderNode, &recipient, &topic, &message, &connected); err != nil {
			storageLog.Errorw("Failed to scan chat message", "error", err)
			continue
		}

		msg.From = senderCall.String
		msg.FromName = senderName.String
		msg.Node = senderNode.String
		msg.To = recipient.String
		msg.Topic = topic.String
		msg.Message = message.String
		msg.Connected = connected == 1

		messages = append(messages, &msg)
	}
	return messages
}

func (s *SQLiteChatStorage) Close() error {
	return s.db.Close()
}

// MemoryChatStorage is a simple in-memory fallback that implements ChatStorage
type MemoryChatStorage struct {
	messages map[string][]*ChatMessage // keyed by callsign
	callsign string
	mu       sync.RWMutex
}

// NewMemoryChatStorage creates a new in-memory chat storage
func NewMemoryChatStorage() *MemoryChatStorage {
	return &MemoryChatStorage{
		messages: make(map[string][]*ChatMessage),
	}
}

func (m *MemoryChatStorage) SetCallsign(callsign string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.callsign = strings.ToUpper(callsign)
}

func (m *MemoryChatStorage) AddMessage(msg *ChatMessage) {
	// Skip ephemeral message types
	if msg.Type == "chat_users" || msg.Type == "chat_th" {
		return
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	// Make a copy to avoid mutation issues
	msgCopy := *msg
	entries := m.messages[m.callsign]
	entries = append(entries, &msgCopy)

	// Limit to last 500 messages per user
	if len(entries) > 500 {
		entries = entries[len(entries)-500:]
	}
	m.messages[m.callsign] = entries
}

func (m *MemoryChatStorage) GetMessagesSince(seq int64) []*ChatMessage {
	m.mu.RLock()
	defer m.mu.RUnlock()

	entries := m.messages[m.callsign]
	var result []*ChatMessage
	for _, msg := range entries {
		if msg.Seq > seq {
			result = append(result, msg)
		}
	}
	return result
}

func (m *MemoryChatStorage) GetLatestMessages(limit int) []*ChatMessage {
	m.mu.RLock()
	defer m.mu.RUnlock()

	entries := m.messages[m.callsign]
	if len(entries) <= limit {
		// Return a copy
		result := make([]*ChatMessage, len(entries))
		copy(result, entries)
		return result
	}
	// Return last N messages
	result := make([]*ChatMessage, limit)
	copy(result, entries[len(entries)-limit:])
	return result
}

func (m *MemoryChatStorage) GetMessagesBefore(beforeSeq int64, limit int) []*ChatMessage {
	m.mu.RLock()
	defer m.mu.RUnlock()

	entries := m.messages[m.callsign]
	var result []*ChatMessage

	// Find messages before beforeSeq
	for _, msg := range entries {
		if msg.Seq < beforeSeq {
			result = append(result, msg)
		}
	}

	// Return last N of those
	if len(result) <= limit {
		return result
	}
	return result[len(result)-limit:]
}

func (m *MemoryChatStorage) GetBufferInfo() ChatBufferInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()

	entries := m.messages[m.callsign]
	if len(entries) == 0 {
		return ChatBufferInfo{}
	}

	return ChatBufferInfo{
		MinSeq: entries[0].Seq,
		MaxSeq: entries[len(entries)-1].Seq,
		Count:  len(entries),
	}
}

func (m *MemoryChatStorage) Close() error {
	return nil
}

// Helper to convert ChatMessage to JSON string (for WebSocket sending)
func chatMessageToJSON(msg *ChatMessage) string {
	data, err := json.Marshal(msg)
	if err != nil {
		return ""
	}
	return string(data)
}
