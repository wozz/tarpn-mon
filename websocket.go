package main

import (
	"io/fs"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow connections from any origin (for development)
	},
}

func websocketHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println(err)
		return
	}
	wc := &websocketConn{
		wc: conn,
	}
	defer wc.kill()

	clients[wc] = true

	history := dataBuffer.getAll()
	for _, message := range history {
		if err := wc.write(message); err != nil {
			log.Println(err)
			return
		}
	}

	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			log.Printf("WebSocket read error: %v", err)
			break
		}
	}

	delete(clients, wc)
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	content, err := static.ReadFile("static/index.html")
	if err != nil {
		log.Printf("Error reading index.html: %v", err)
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

func setupRoutes() {
	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/ws", websocketHandler)
	http.HandleFunc("/version", versionHandler)

	// Create a file server for the 'static' directory within the embedded FS.
	// The 'static' variable (embed.FS) is defined in main.go.
	staticFS, err := fs.Sub(static, "static")
	if err != nil {
		log.Fatalf("failed to create sub FS for static assets: %v", err)
	}
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))
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

var clients = make(map[*websocketConn]bool)

func broadcast(message string) {
	dataBuffer.add(message)
	for client := range clients {
		err := client.write(message)
		if err != nil {
			log.Printf("Websocket error: %s", err)
			delete(clients, client)
			client.kill()
		}
	}
}
