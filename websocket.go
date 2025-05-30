package main

import (
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

	// Add the new client to the list of connected clients
	clients[wc] = true

	history := dataBuffer.getAll()
	for _, message := range history {
		if err := wc.write(message); err != nil {
			log.Println(err)
			return
		}
	}

	for {
		// Handle incoming messages from the client (if any)
		_, _, err := conn.ReadMessage()
		if err != nil {
			log.Println(err)
			break
		}
		// You can add logic here to process commands from the web client, if needed.
	}

	// Remove the client from the list when the connection is closed
	delete(clients, wc)
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	content, _ := static.ReadFile("static/index.html")
	w.Write(content)
}

func versionHandler(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(Version))
}

func setupRoutes() {
	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/ws", websocketHandler)
	http.HandleFunc("/version", versionHandler)
	http.Handle("/static/", http.FileServer(http.FS(static)))
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
