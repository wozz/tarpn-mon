package main

type circularBuffer struct {
	buffer   []string
	head     int
	tail     int
	count    int
	capacity int
}

func newCircularBuffer(capacity int) *circularBuffer {
	return &circularBuffer{
		buffer:   make([]string, capacity),
		head:     0,
		tail:     0,
		count:    0,
		capacity: capacity,
	}
}

func (cb *circularBuffer) add(data string) {
	cb.buffer[cb.head] = data
	cb.head = (cb.head + 1) % cb.capacity
	if cb.count == cb.capacity {
		cb.tail = (cb.tail + 1) % cb.capacity
	} else {
		cb.count++
	}
}

func (cb *circularBuffer) getAll() []string {
	items := make([]string, cb.count)
	if cb.count == 0 {
		return items
	}
	if cb.head > cb.tail {
		copy(items, cb.buffer[cb.tail:cb.head])
	} else {
		copy(items, cb.buffer[cb.tail:])
		copy(items[cb.capacity-cb.tail:], cb.buffer[:cb.head])
	}
	return items
}
