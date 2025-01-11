package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type connState int

const (
	state_CONNECTING connState = iota
	state_INIT
	state_MON
	state_ERR
)

var state = state_CONNECTING

func reader(conn net.Conn) {
	start := time.Now()
	r := bufio.NewReader(conn)

	logFile, err := os.Create(fmt.Sprintf("log_%d.txt", time.Now().Unix()))
	if err != nil {
		panic(err)
	}
	fileWriter := bufio.NewWriter(logFile)

	for {
		switch state {
		case state_CONNECTING:
			// looking for "Connected to TelnetServer"
			c, err := r.ReadString('\x0d')
			if err != nil {
				panic(err)
			}
			if strings.HasSuffix(c, "Connected to TelnetServer\x0d") {
				state = state_INIT
			} else {
				fmt.Println([]byte(c))
			}
		case state_INIT:
			// list ports \xff\xffnum_ports|port0|port1|etc|
			c, err := r.ReadString('|')
			if len(c) != 4 || c[:2] != "\xff\xff" {
				fmt.Println([]byte(c))
				panic("unexpected init string")
			}
			numPorts, err := strconv.Atoi(string(c[2]))
			if err != nil {
				panic("unexpected num ports value")
			}
			for i := range numPorts {
				c, err = r.ReadString('|')
				if err != nil {
					panic(err)
				}
				c = strings.TrimSuffix(c, "|")
				fmt.Printf("PORT %d %s\n", i, c)
			}
			state = state_MON
		case state_MON:
			c, err := r.ReadString('\xfe')
			if err != nil {
				fmt.Printf("\n\nsince start: %v\n\n", time.Since(start))
				fmt.Println(c)
				panic(err)
			}
			// log monitor lines
			_, err = fileWriter.WriteString(c)
			if err != nil {
				panic(err)
			}
			c = strings.TrimSuffix(c, "\xfe")

			if strings.HasPrefix(c, "\xff\x1b\x11") {
				c = strings.TrimPrefix(c, "\xff\x1b\x11")
			} else if strings.HasPrefix(c, "\xff\x1b") {
				c = strings.TrimPrefix(c, "\xff\x1b")
			}
			c = strings.TrimPrefix(c, "[")
			c = strings.TrimSuffix(c, "\r")
			c = strings.ReplaceAll(c, "\r", "\n")
			if tncData, err := parseTNCData(c); err == nil {
				jsonData, err := json.Marshal(tncData)
				if err == nil {
					broadcast("TNC_DATA:" + string(jsonData))
				}
			}
			fmt.Println(c)
			broadcast(c)
		case state_ERR:
			panic("unknown error")
		default:
			panic("unknown state")
		}
	}
}

func main() {
	ctx := context.Background()
	conn, err := net.Dial("tcp", "bb8.lan:8011")
	if err != nil {
		log.Fatalf("could not connect: %v", err)
	}

	go reader(conn)
	time.Sleep(time.Second * 3)

	conn.Write([]byte("wa2m\r"))
	time.Sleep(time.Second * 1)
	conn.Write([]byte("p\r"))
	// must send this string to get monitor mode
	conn.Write([]byte("BPQTERMTCP\r"))
	time.Sleep(time.Second)
	conn.Write([]byte(`\\\\1 1 1 1 0 0 0 1` + "\r"))
	time.Sleep(time.Second * 3)

	go func() {
		// keep session alive
		for {
			<-time.After(time.Minute * 2)
			if _, err := conn.Write([]byte{0}); err != nil {
				panic(err)
			}
		}
	}()

	// Set up HTTP routes and WebSocket handler
	setupRoutes()

	// Start the HTTP server
	go func() {
		log.Println("Starting HTTP server on :8080")
		if err := http.ListenAndServe(":8080", nil); err != nil {
			log.Fatal("ListenAndServe: ", err)
		}
	}()

	<-ctx.Done()

}
