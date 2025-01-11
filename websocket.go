package main

import (
	"log"
	"net/http"

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
	defer conn.Close()

	// Add the new client to the list of connected clients
	clients[conn] = true

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
	delete(clients, conn)
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "static/index.html")
}

func setupRoutes() {
	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/ws", websocketHandler)
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("static"))))
}

var clients = make(map[*websocket.Conn]bool) // concurrent safe map of clients

func broadcast(message string) {
	for client := range clients {
		err := client.WriteMessage(websocket.TextMessage, []byte(message))
		if err != nil {
			log.Printf("Websocket error: %s", err)
			client.Close()
			delete(clients, client)
		}
	}
}
