package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

// A client that stops reading must not stall broadcasts or block other
// clients from connecting. On bb8 one sleeping browser tab froze the web UI
// for everyone: the write to it blocked with clientsMu held.
func TestStalledClientDoesNotBlockBroadcast(t *testing.T) {
	old := wsWriteTimeout
	wsWriteTimeout = 200 * time.Millisecond
	defer func() { wsWriteTimeout = old }()

	registered := make(chan *websocketConn, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Errorf("upgrade: %v", err)
			return
		}
		wc := &websocketConn{wc: conn}
		clientsMu.Lock()
		clients[wc] = true
		clientsMu.Unlock()
		registered <- wc
	}))
	defer srv.Close()

	// Dial and never read.
	client, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(srv.URL, "http"), nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer client.Close()
	wc := <-registered
	defer func() {
		clientsMu.Lock()
		delete(clients, wc)
		clientsMu.Unlock()
		wc.kill()
	}()

	// Far more than the socket buffers hold, so the writes must block.
	msg := strings.Repeat("x", 256*1024)
	done := make(chan struct{})
	go func() {
		for i := 0; i < 64; i++ {
			broadcastDirect(msg)
		}
		close(done)
	}()

	// While that is in progress, a new client must still be able to register.
	locked := make(chan struct{})
	go func() {
		time.Sleep(50 * time.Millisecond)
		clientsMu.Lock()
		clientsMu.Unlock()
		close(locked)
	}()

	select {
	case <-locked:
	case <-time.After(2 * time.Second):
		t.Fatal("clientsMu stayed locked while writing to a stalled client")
	}
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("broadcast blocked on a client that is not reading")
	}
}
