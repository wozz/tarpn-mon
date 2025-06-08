package main

import (
	"bufio"
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"html"
	"log"
	"net"
	"net/http"
	"os"
	"regexp"
	"runtime/debug"
	"strconv"
	"strings"
	"time"
)

//go:embed static/*
var static embed.FS

type connState int

const (
	state_CONNECTING connState = iota
	state_INIT
	state_MON
	state_ERR
)

var (
	callsign    string
	hostname    string
	numPorts    int
	bufferSize  int
	debugInfo   bool
	versionInfo bool
)

var Version = "dev"

var state = state_CONNECTING

var dataBuffer *circularBuffer

var (
	enableConsoleOutput = false
	enableFileLogging   = false
	defaultCallsign     = ""
)

// Maximum backoff time between reconnection attempts
const maxBackoff = 5 * time.Minute

// Initial backoff time
const initialBackoff = 1 * time.Second

// LogMessageData holds the data for a log line to be sent as JSON
type LogMessageData struct {
	Type       string `json:"type"` // "log" or "tnc"
	Timestamp  string `json:"timestamp,omitempty"`
	Prefix     string `json:"prefix,omitempty"`
	Route      string `json:"route,omitempty"`
	Port       string `json:"port,omitempty"`
	Message    string `json:"message,omitempty"`
	RouteColor string `json:"routeColor,omitempty"`
	Raw        string `json:"raw,omitempty"` // For messages not matching the regex
}

// TNCDataMessage holds TNC port data and its port number
type TNCDataMessage struct {
	Type    string      `json:"type"` // "tnc_data"
	PortNum int         `json:"portNum"`
	Data    interface{} `json:"data"` // This will be the parsed TNCData struct
}

func init() {
	nodeIniCallsign, err := searchNodeIni()
	if err == nil {
		defaultCallsign = nodeIniCallsign
	}
}

func connectWithRetry(ctx context.Context) (net.Conn, error) {
	backoff := initialBackoff
	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
			conn, err := net.Dial("tcp", fmt.Sprintf("%s:8011", hostname))
			if err == nil {
				log.Printf("Successfully connected to %s:8011", hostname)
				return conn, nil
			}
			log.Printf("Connection failed: %v, retrying in %v", err, backoff)
			time.Sleep(backoff)
			// Exponential backoff with maximum limit
			backoff *= 2
			if backoff > maxBackoff {
				backoff = maxBackoff
			}
		}
	}
}

func initializeConnection(conn net.Conn) error {
	// Send initial commands to set up the connection
	time.Sleep(time.Second * 3)

	if _, err := conn.Write([]byte(fmt.Sprintf("%s\r", callsign))); err != nil {
		return fmt.Errorf("failed to send callsign: %v", err)
	}
	time.Sleep(time.Second)

	if _, err := conn.Write([]byte("p\r")); err != nil {
		return fmt.Errorf("failed to send p command: %v", err)
	}

	if _, err := conn.Write([]byte("BPQTERMTCP\r")); err != nil {
		return fmt.Errorf("failed to send BPQTERMTCP: %v", err)
	}
	time.Sleep(time.Second)

	if _, err := conn.Write([]byte(connectMonitorString(numPorts) + "\r")); err != nil {
		return fmt.Errorf("failed to send monitor string: %v", err)
	}
	time.Sleep(time.Second * 3)

	return nil
}

func keepAlive(ctx context.Context, conn net.Conn) {
	ticker := time.NewTicker(2 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if _, err := conn.Write([]byte{0}); err != nil {
				log.Printf("Keepalive failed: %v", err)
				return
			}
		}
	}
}

func handleConnection(ctx context.Context, conn net.Conn) error {
	// Create a separate context for this connection's keepalive
	keepaliveCtx, cancelKeepalive := context.WithCancel(ctx)
	defer cancelKeepalive() // Ensure keepalive is cancelled when we exit

	// Start keepalive in a separate goroutine
	go keepAlive(keepaliveCtx, conn)

	r := bufio.NewReader(conn)

	var fileWriter *bufio.Writer
	if enableFileLogging {
		logFile, err := os.Create(fmt.Sprintf("log_%d.txt", time.Now().Unix()))
		if err != nil {
			return fmt.Errorf("failed to create log file: %v", err)
		}
		defer logFile.Close()
		fileWriter = bufio.NewWriter(logFile)
		defer fileWriter.Flush()
	}

	state = state_CONNECTING
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			switch state {
			case state_CONNECTING:
				c, err := r.ReadString('\x0d')
				if err != nil {
					return fmt.Errorf("connection error: %v", err)
				}
				if strings.HasSuffix(c, "Connected to TelnetServer\x0d") {
					state = state_INIT
				}
			case state_INIT:
				c, err := r.ReadString('|')
				if err != nil {
					return fmt.Errorf("init error: %v", err)
				}
				if len(c) != 4 || c[:2] != "\xff\xff" {
					return fmt.Errorf("unexpected init string")
				}
				numPortsVal, err := strconv.Atoi(string(c[2]))
				if err != nil {
					return fmt.Errorf("invalid port number: %v", err)
				}
				for i := range numPortsVal {
					c, err = r.ReadString('|')
					if err != nil {
						return fmt.Errorf("error reading port info: %v", err)
					}
					c = strings.TrimSuffix(c, "|")
					log.Printf("PORT %d %s\n", i, c)
				}
				state = state_MON
			case state_MON:
				c, err := r.ReadString('\xfe')
				if err != nil {
					return fmt.Errorf("monitor error: %v", err)
				}

				if enableFileLogging {
					if _, err = fileWriter.WriteString(c); err != nil {
						return fmt.Errorf("log write error: %v", err)
					}
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

				// Try to parse as TNC structured data first
				if portNum, tncData, err := parseTNCData(c); err == nil {
					msg := TNCDataMessage{
						Type:    "tnc_data",
						PortNum: portNum,
						Data:    tncData,
					}
					jsonData, err := json.Marshal(msg)
					if err == nil {
						broadcast(string(jsonData))
					} else {
						log.Printf("Error marshalling TNC data to JSON: %v", err)
					}
				} // continue to parse as regular log line even for TNC data

				re := regexp.MustCompile(`(?s)^(\d{2}:\d{2}:\d{2})([RT]) ([A-Z0-9-]+>[A-Z0-9-]+) Port=(\d+) (.*)`)
				matches := re.FindStringSubmatch(c)
				var logMsgData LogMessageData
				if len(matches) == 6 {
					logMsgData = LogMessageData{
						Type:       "log",
						Timestamp:  matches[1],
						Prefix:     matches[2],
						Route:      matches[3],
						Port:       matches[4],
						Message:    html.EscapeString(matches[5]), // Keep HTML escaping for safety on client
						RouteColor: hashCallsign(matches[3]),
					}
				} else {
					logMsgData = LogMessageData{
						Type: "log",
						Raw:  c, // Send the raw string if it doesn't match
					}
				}
				jsonData, err := json.Marshal(logMsgData)
				if err == nil {
					broadcast(string(jsonData))
				} else {
					log.Printf("Error marshalling log message to JSON: %v", err)
				}

				if enableConsoleOutput {
					fmt.Println(c)
				}
			case state_ERR:
				return fmt.Errorf("connection in error state")
			default:
				return fmt.Errorf("unknown state")
			}
		}
	}
}

func main() {
	flag.StringVar(&callsign, "call", defaultCallsign, "callsign to use as pw for telnet connection to node")
	flag.StringVar(&hostname, "host", "localhost", "hostname to connect to")
	flag.IntVar(&numPorts, "ports", 12, "number of ports to monitor")
	flag.IntVar(&bufferSize, "buffer-size", 5000, "number of lines to store in the memory buffer")
	flag.BoolVar(&enableConsoleOutput, "console-out", false, "emit lines from monitor to console")
	flag.BoolVar(&debugInfo, "debug-info", false, "emit binary debug info")
	flag.BoolVar(&versionInfo, "version", false, "display version string")
	flag.Parse()

	if versionInfo {
		fmt.Println(Version)
		os.Exit(0)
	} else if debugInfo {
		info, _ := debug.ReadBuildInfo()
		fmt.Println(info)
		os.Exit(0)
	}

	dataBuffer = newCircularBuffer(bufferSize)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Set up HTTP routes and WebSocket handler
	setupRoutes()

	// Start the HTTP server
	go func() {
		log.Println("Starting HTTP server on :8212")
		if err := http.ListenAndServe(":8212", nil); err != nil {
			log.Fatal("ListenAndServe: ", err)
		}
	}()

	// Main connection loop
	for {
		select {
		case <-ctx.Done():
			return
		default:
			conn, err := connectWithRetry(ctx)
			if err != nil {
				log.Printf("Failed to establish connection: %v", err)
				// Simple backoff before retrying connectWithRetry to avoid tight loop on context errors
				time.Sleep(initialBackoff)
				continue
			}

			if err := initializeConnection(conn); err != nil {
				log.Printf("Failed to initialize connection: %v", err)
				conn.Close()
				time.Sleep(initialBackoff) // Backoff before retrying connection
				continue
			}

			// Handle the connection - keepalive is now managed inside handleConnection
			if err := handleConnection(ctx, conn); err != nil {
				log.Printf("Connection error: %v", err)
			}

			// Close the connection before retrying
			conn.Close()

			// Small delay before reconnecting to avoid tight loop if handleConnection exits immediately
			time.Sleep(time.Second)
		}
	}
}

func connectMonitorString(nump int) string {
	var portmask int64
	for i := range nump {
		portmask |= 1 << i
	}
	return fmt.Sprintf(`\\\\%x 1 1 1 0 0 0 1`, portmask)
}
