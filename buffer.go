package main

import (
	"encoding/json"
	"os"
	"sync"
)

type bufferedItem struct {
	Seq  int64
	Data string
}

type circularBuffer struct {
	buffer   []bufferedItem
	head     int
	tail     int
	count    int
	capacity int
	mu       sync.RWMutex
}

func newCircularBuffer(capacity int) *circularBuffer {
	return &circularBuffer{
		buffer:   make([]bufferedItem, capacity),
		head:     0,
		tail:     0,
		count:    0,
		capacity: capacity,
	}
}

func (cb *circularBuffer) add(seq int64, data string) {
	cb.mu.Lock()
	defer cb.mu.Unlock()
	cb.buffer[cb.head] = bufferedItem{Seq: seq, Data: data}
	cb.head = (cb.head + 1) % cb.capacity
	if cb.count == cb.capacity {
		cb.tail = (cb.tail + 1) % cb.capacity
	} else {
		cb.count++
	}
}

func (cb *circularBuffer) getAll() []string {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	items := make([]string, cb.count)
	if cb.count == 0 {
		return items
	}
	
	idx := 0
	// Iterate from tail to head (logical)
	curr := cb.tail
	for i := 0; i < cb.count; i++ {
		items[idx] = cb.buffer[curr].Data
		idx++
		curr = (curr + 1) % cb.capacity
	}
	return items
}

func (cb *circularBuffer) getSince(seq int64) []string {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	var items []string
	if cb.count == 0 {
		return items
	}

	curr := cb.tail
	for i := 0; i < cb.count; i++ {
		if cb.buffer[curr].Seq > seq {
			items = append(items, cb.buffer[curr].Data)
		}
		curr = (curr + 1) % cb.capacity
	}
	return items
}

// getRange returns messages with seq > afterSeq, limited to 'limit' items
// Returns items in chronological order (oldest first)
func (cb *circularBuffer) getRange(afterSeq int64, limit int) []string {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	var items []string
	if cb.count == 0 || limit <= 0 {
		return items
	}

	curr := cb.tail
	for i := 0; i < cb.count && len(items) < limit; i++ {
		if cb.buffer[curr].Seq > afterSeq {
			items = append(items, cb.buffer[curr].Data)
		}
		curr = (curr + 1) % cb.capacity
	}
	return items
}

// getLatest returns the last 'limit' messages
// Returns items in chronological order (oldest first)
func (cb *circularBuffer) getLatest(limit int) []string {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	if cb.count == 0 || limit <= 0 {
		return []string{}
	}

	// Calculate how many to skip
	skip := 0
	if cb.count > limit {
		skip = cb.count - limit
	}

	items := make([]string, 0, min(limit, cb.count))
	curr := cb.tail
	for i := 0; i < cb.count; i++ {
		if i >= skip {
			items = append(items, cb.buffer[curr].Data)
		}
		curr = (curr + 1) % cb.capacity
	}
	return items
}

// getBefore returns up to 'limit' messages with seq < beforeSeq
// Returns items in chronological order (oldest first)
func (cb *circularBuffer) getBefore(beforeSeq int64, limit int) []string {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	if cb.count == 0 || limit <= 0 {
		return []string{}
	}

	// First pass: find all items before the sequence
	var candidates []string
	curr := cb.tail
	for i := 0; i < cb.count; i++ {
		if cb.buffer[curr].Seq < beforeSeq {
			candidates = append(candidates, cb.buffer[curr].Data)
		}
		curr = (curr + 1) % cb.capacity
	}

	// Return last 'limit' items
	if len(candidates) <= limit {
		return candidates
	}
	return candidates[len(candidates)-limit:]
}

// getInfo returns buffer statistics
func (cb *circularBuffer) getInfo() (minSeq, maxSeq int64, count int) {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	if cb.count == 0 {
		return 0, 0, 0
	}

	minSeq = cb.buffer[cb.tail].Seq

	// head-1 (with wrap) is the last item added
	lastIdx := (cb.head - 1 + cb.capacity) % cb.capacity
	maxSeq = cb.buffer[lastIdx].Seq

	return minSeq, maxSeq, cb.count
}

// Save writes the current buffer content to a JSON file
func (cb *circularBuffer) Save(filename string) error {
	cb.mu.RLock()
	defer cb.mu.RUnlock()

	var items []bufferedItem
	curr := cb.tail
	for i := 0; i < cb.count; i++ {
		items = append(items, cb.buffer[curr])
		curr = (curr + 1) % cb.capacity
	}

	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	return encoder.Encode(items)
}

// Load reads items from a JSON file and populates the buffer
// Note: This overwrites existing buffer content
func (cb *circularBuffer) Load(filename string) error {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	file, err := os.Open(filename)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // File doesn't exist, start empty
		}
		return err
	}
	defer file.Close()

	var items []bufferedItem
	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&items); err != nil {
		return err
	}

	// Rebuild buffer
	cb.head = 0
	cb.tail = 0
	cb.count = 0
	
	for _, item := range items {
		cb.buffer[cb.head] = item
		cb.head = (cb.head + 1) % cb.capacity
		if cb.count == cb.capacity {
			cb.tail = (cb.tail + 1) % cb.capacity
		} else {
			cb.count++
		}
	}

	return nil
}

// Close implements the ChatStorage interface
func (cb *circularBuffer) Close() error {
	return nil
}
