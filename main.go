package main

import (
	"bufio"
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"html"
	"net"
	"net/http"
	"os"
	"regexp"
	"runtime/debug"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

//go:embed all:web-dist
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
	password    string
	hostname    string
	targetPort  int
	numPorts    int
	bufferSize  int
	debugInfo   bool
	versionInfo bool

	// Chat configuration
	chatEnabled  bool
	chatPort     int
	chatCallsign string
	chatPassword string
	chatUserName string
	chatNode     string

	// BBS configuration
	bbsEnabled  bool
	bbsPort     int
	bbsCallsign string
	bbsPassword string

	// Node Console configuration
	nodeEnabled  bool
	nodePort     int
	nodeCallsign string
	nodePassword string

	// Stats collection configuration
	statsEnabled    bool
	statsPort       int
	statsCallsign   string
	statsPassword   string
	statsInterval   int
	statsNoCQ       bool
	statsNoBulletin bool

	// Debug logging
	debugMode bool
)

var Version = "dev"

var state = state_CONNECTING

var dataBuffer *circularBuffer

// neighborStorageRef holds a reference to the link stats storage for CQ neighbor detection
var neighborStorageRef *LinkStatsStorage

var (
	enableConsoleOutput = false
	enableFileLogging   = false
	defaultCallsign     = ""
	messageSeq          int64
)

// Maximum backoff time between reconnection attempts
const maxBackoff = 5 * time.Minute

// Initial backoff time
const initialBackoff = 1 * time.Second

// LogMessageData holds the data for a log line to be sent as JSON
type LogMessageData struct {
	Seq        int64  `json:"seq"`
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
	Seq     int64       `json:"seq"`
	Type    string      `json:"type"` // "tnc_data"
	PortNum int         `json:"portNum"`
	Data    interface{} `json:"data"` // This will be the parsed TNCData struct
}

// TARPNStatMessage holds TARPN statistics parsed from log messages
type TARPNStatMessage struct {
	Seq       int64      `json:"seq"`
	Type      string     `json:"type"` // "tarpn_stat"
	Port      string     `json:"port"`
	Timestamp string     `json:"timestamp"`
	Data      *TARPNStat `json:"data"`
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
			conn, err := net.Dial("tcp", fmt.Sprintf("%s:%d", hostname, targetPort))
			if err == nil {
				mainLog.Infow("Connected to monitor port", "host", hostname, "port", targetPort)
				return conn, nil
			}
			mainLog.Warnw("Connection failed, retrying", "error", err, "backoff", backoff)
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
	// Create telnet connection wrapper with short negotiation timeout
	// FBB/monitor port doesn't typically send telnet negotiation, but handle it if present
	tc, err := NewTelnetConn(conn, 500*time.Millisecond, mainLog)
	if err != nil {
		return fmt.Errorf("telnet negotiation failed: %v", err)
	}

	// FBB mode authentication - send all credentials together in one write
	// Format: user\rpassword\rBPQTermTCP\r
	// LinBPQ expects CR-terminated lines with no prompts on FBB port
	authString := fmt.Sprintf("%s\r%s\rBPQTermTCP\r", callsign, password)
	mainLog.Debugw("Sending FBB auth", "callsign", callsign, "authLen", len(authString))

	if _, err := conn.Write([]byte(authString)); err != nil {
		return fmt.Errorf("failed to send FBB auth: %v", err)
	}

	// Wait for "Connected to TelnetServer" confirmation (10 second timeout)
	// If username doesn't match configured user, LinBPQ may send login prompt instead
	mainLog.Debugw("Waiting for connection confirmation")
	lines, found, err := tc.ReadUntil(func(line string) bool {
		mainLog.Debugw("FBB response line", "line", line)
		return strings.Contains(line, "Connected to TelnetServer")
	}, 10*time.Second)

	if err != nil {
		return fmt.Errorf("error waiting for connection confirmation: %v", err)
	}
	if !found {
		// Log what we did receive for debugging
		if len(lines) > 0 {
			mainLog.Warnw("FBB auth failed - received unexpected response", "lines", lines)
		}
		return fmt.Errorf("timeout waiting for connection confirmation (user may not be configured in LinBPQ)")
	}

	mainLog.Debugw("Connection confirmed, sending monitor string")
	if err := tc.WriteString(connectMonitorString(numPorts)); err != nil {
		return fmt.Errorf("failed to send monitor string: %v", err)
	}

	// Clear any read deadline before returning
	conn.SetReadDeadline(time.Time{})

	return nil
}

// keepAlive sends periodic keepalives to prevent LinBPQ's L4 idle session
// timeout (L4KILLTIMER) from disconnecting the monitor session. LinBPQ sends
// monitor data via direct send() bypassing the L4 session layer, so even an
// active monitor stream appears "idle" to the L4 timer. The CMS keepalive
// format ";;;;;;\r\n" is also intercepted before BuffertoNode() and does NOT
// reset the timer. A bare CR (\r) flows through BuffertoNode() (resetting
// L4KILLTIMER) and is treated as a null command by the node processor —
// silently discarded with no output (see Cmd.c:5166 comment "from keepalive").
func keepAlive(ctx context.Context, conn net.Conn) {
	ticker := time.NewTicker(2 * time.Minute)
	defer ticker.Stop()

	// Bare CR: passes through BuffertoNode() to reset L4KILLTIMER,
	// then handled as null command (no output, no side effects)
	keepaliveMsg := []byte("\r")

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if _, err := conn.Write(keepaliveMsg); err != nil {
				mainLog.Errorw("Keepalive failed", "error", err)
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

	// Start directly in INIT state - authentication is handled by initializeConnection
	state = state_INIT
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			switch state {
			case state_INIT:
				c, err := r.ReadString('|')
				if err != nil {
					return fmt.Errorf("init error: %v", err)
				}
				if len(c) < 4 || c[:2] != "\xff\xff" {
					return fmt.Errorf("unexpected init string")
				}
				c = strings.TrimSuffix(c, "|")
				numPortsVal, err := strconv.Atoi(string(c[2:]))
				if err != nil {
					return fmt.Errorf("invalid port number: %v", err)
				}
				for i := range numPortsVal {
					c, err = r.ReadString('|')
					if err != nil {
						return fmt.Errorf("error reading port info: %v", err)
					}
					c = strings.TrimSuffix(c, "|")
					mainLog.Infow("Port discovered", "port", i, "info", c)
				}
				state = state_MON
				SetMonitorConnectionState(state_MON)
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
				// Strip LinBPQ frame header: \xff\x1b<color>
				// RX frames: color=0x11 (17), TX frames: color=0x5b ('[')
				if strings.HasPrefix(c, "\xff\x1b\x11") {
					c = strings.TrimPrefix(c, "\xff\x1b\x11") // RX frame
				} else if strings.HasPrefix(c, "\xff\x1b[") {
					c = strings.TrimPrefix(c, "\xff\x1b[") // TX frame (0x5b = '[')
				} else if strings.HasPrefix(c, "\xff\x1b") {
					c = strings.TrimPrefix(c, "\xff\x1b") // Unknown color byte
				}
				c = strings.TrimSuffix(c, "\r")
				c = strings.ReplaceAll(c, "\r", "\n")

				// Try to parse as TNC structured data first
				if portNum, tncData, err := parseTNCData(c); err == nil {
					portStr := strconv.Itoa(portNum)
					msg := TNCDataMessage{
						Seq:     atomic.AddInt64(&messageSeq, 1),
						Type:    "tnc_data",
						PortNum: portNum,
						Data:    tncData,
					}
					jsonData, err := json.Marshal(msg)
					if err == nil {
						broadcast(msg.Seq, string(jsonData))
					} else {
						mainLog.Errorw("Failed to marshal TNC data", "error", err, "port", portNum)
					}
					// Update Prometheus metrics
					UpdateTNCMetrics(portStr, tncData)
					IncrementTNCDataMessages(portStr)
				} // continue to parse as regular log line even for TNC data

				re := regexp.MustCompile(`(?s)^(\d{2}:\d{2}:\d{2})([RT]) ([A-Z0-9-]+>[A-Z0-9-]+) Port=(\d+) (.*)`)
				matches := re.FindStringSubmatch(c)
				var logMsgData LogMessageData
				if len(matches) == 6 {
					logMsgData = LogMessageData{
						Seq:        atomic.AddInt64(&messageSeq, 1),
						Type:       "log",
						Timestamp:  matches[1],
						Prefix:     matches[2],
						Route:      matches[3],
						Port:       matches[4],
						Message:    html.EscapeString(matches[5]), // Keep HTML escaping for safety on client
						RouteColor: hashCallsign(matches[3]),
					}

					// Check for TARPN Stats
					if stat, err := parseTARPNStat(matches[5]); err == nil {
						tarpnStatLog.Debugw("Parsed TARPNstat", "stat", stat, "port", matches[4])
						statMsg := TARPNStatMessage{
							Seq:       atomic.AddInt64(&messageSeq, 1),
							Type:      "tarpn_stat",
							Port:      matches[4],
							Timestamp: matches[1],
							Data:      stat,
						}
						if statJson, err := json.Marshal(statMsg); err == nil {
							broadcast(statMsg.Seq, string(statJson))
						} else {
							tarpnStatLog.Errorw("Failed to marshal TARPNstat", "error", err)
						}
						// Update Prometheus metrics
						UpdateTARPNStatMetrics(matches[4], stat)
						IncrementTARPNStatMessages(matches[4])

						// Persist it. Unlike the [LS1] broadcast below, this
						// format is what every TARPN node emits, including
						// stock ones, so it is the only bilateral link data
						// available for neighbours not running this software.
						// matches[2] is the monitor's R/T direction flag.
						if neighborStorageRef != nil {
							if rxPort, convErr := strconv.Atoi(matches[4]); convErr == nil {
								if err := neighborStorageRef.SaveTARPNStat(matches[2], rxPort, stat); err != nil {
									tarpnStatLog.Warnw("Failed to save TARPNstat", "error", err)
								}
							}
						}
					} else if strings.Contains(matches[5], "[TARPNstat") {
						tarpnStatLog.Debugw("Failed to parse TARPNstat", "error", err, "raw", matches[5])
					}

					// Check for Link Stats CQ broadcast [LS1]
					if idx := strings.Index(matches[5], "[LS1]"); idx >= 0 {
						cqContent := matches[5][idx:]
						if cqMsg, err := DecodeCQ(cqContent); err == nil {
							rxPort, _ := strconv.Atoi(matches[4])
							neighborLog.Debugw("Parsed CQ stats",
								"callsign", cqMsg.Callsign,
								"reportedPort", cqMsg.PortNum,
								"rxPort", rxPort)
							if neighborStorageRef != nil {
								if err := neighborStorageRef.SaveNeighborCQ(rxPort, cqMsg); err != nil {
									neighborLog.Warnw("Failed to save neighbor CQ", "error", err)
								}
							}
							BroadcastNeighborCQ(rxPort, cqMsg)
						} else if strings.Contains(matches[5], "[LS1]") {
							neighborLog.Debugw("Failed to parse CQ", "error", err, "raw", matches[5])
						}
					}
				} else {
					logMsgData = LogMessageData{
						Seq:  atomic.AddInt64(&messageSeq, 1),
						Type: "log",
						Raw:  c, // Send the raw string if it doesn't match
					}
				}
				jsonData, err := json.Marshal(logMsgData)
				if err == nil {
					broadcast(logMsgData.Seq, string(jsonData))
					IncrementMonitorMessages()
					UpdateBufferMetrics()
				} else {
					mainLog.Errorw("Failed to marshal log message", "error", err, "seq", logMsgData.Seq)
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
	flag.StringVar(&password, "password", "p", "password to use for connection to node")
	flag.StringVar(&hostname, "host", "localhost", "hostname to connect to")
	flag.IntVar(&targetPort, "target-port", 8011, "target port to connect to on the host (FBB telnet port for monitor)")
	flag.IntVar(&numPorts, "ports", 12, "number of ports to monitor")
	flag.IntVar(&bufferSize, "buffer-size", 5000, "number of lines to store in the memory buffer")
	flag.BoolVar(&enableConsoleOutput, "console-out", false, "emit lines from monitor to console")
	flag.BoolVar(&debugInfo, "debug-info", false, "emit binary debug info")
	flag.BoolVar(&versionInfo, "version", false, "display version string")

	// Chat flags
	flag.BoolVar(&chatEnabled, "chat", false, "enable chat client")
	flag.IntVar(&chatPort, "chat-port", 8010, "BPQ telnet port for chat connection")
	flag.StringVar(&chatCallsign, "chat-call", "", "callsign for chat (defaults to -call value)")
	flag.StringVar(&chatPassword, "chat-password", "", "password for chat (defaults to -password value)")
	flag.StringVar(&chatUserName, "chat-name", "", "display name for chat")
	flag.StringVar(&chatNode, "chat-node", "", "node ID/alias for chat link (e.g. BOT)")

	// BBS flags
	flag.BoolVar(&bbsEnabled, "bbs", false, "enable BBS client")
	flag.IntVar(&bbsPort, "bbs-port", 8010, "BPQ telnet port for BBS connection")
	flag.StringVar(&bbsCallsign, "bbs-call", "", "callsign for BBS (defaults to -call value)")
	flag.StringVar(&bbsPassword, "bbs-password", "", "password for BBS (defaults to -password value)")

	// Node Console flags
	flag.BoolVar(&nodeEnabled, "node", false, "enable node console client")
	flag.IntVar(&nodePort, "node-port", 8010, "BPQ telnet port for node console connection")
	flag.StringVar(&nodeCallsign, "node-call", "", "callsign for node console (defaults to -call value)")
	flag.StringVar(&nodePassword, "node-password", "", "password for node console (defaults to -password value)")

	// Stats collection flags
	flag.BoolVar(&statsEnabled, "stats", false, "enable L2 link stats collection from LinBPQ S command")
	flag.IntVar(&statsPort, "stats-port", 8010, "BPQ telnet port for stats collection")
	flag.StringVar(&statsCallsign, "stats-call", "", "callsign for stats connection (defaults to -call value)")
	flag.StringVar(&statsPassword, "stats-password", "", "password for stats connection (defaults to -password value)")
	flag.IntVar(&statsInterval, "stats-interval", 60, "stats polling interval in seconds")
	flag.BoolVar(&statsNoCQ, "stats-no-cq", false, "collect stats but do not broadcast [LS1] link stats via CQ")
	flag.BoolVar(&statsNoBulletin, "stats-no-bulletin", false, "collect stats but do not post the daily BBS bulletin")

	// Debug flag
	flag.BoolVar(&debugMode, "debug", false, "enable verbose debug logging")

	// Config file flag
	configPath := flag.String("config", "tarpn-mon.json", "path to JSON config file")

	flag.Parse()

	// Enable debug logging if flag is set
	SetDebugLogging(debugMode)

	if versionInfo {
		fmt.Println(Version)
		os.Exit(0)
	} else if debugInfo {
		info, _ := debug.ReadBuildInfo()
		fmt.Println(info)
		os.Exit(0)
	}

	// Load persistent settings
	appSettings = NewAppSettings(*configPath)
	if err := appSettings.Load(); err != nil {
		mainLog.Warnw("Failed to load settings file", "path", *configPath, "error", err)
	}

	// Apply CLI flag overrides — only flags explicitly set on command line override config file
	flag.Visit(func(f *flag.Flag) {
		switch f.Name {
		case "chat":
			appSettings.Features["chat"].Enabled = chatEnabled
		case "chat-port":
			appSettings.Features["chat"].Port = chatPort
		case "chat-call":
			appSettings.Features["chat"].Callsign = chatCallsign
		case "chat-password":
			appSettings.Features["chat"].Password = chatPassword
		case "chat-name":
			if appSettings.Features["chat"].Options == nil {
				appSettings.Features["chat"].Options = map[string]string{}
			}
			appSettings.Features["chat"].Options["name"] = chatUserName
		case "chat-node":
			if appSettings.Features["chat"].Options == nil {
				appSettings.Features["chat"].Options = map[string]string{}
			}
			appSettings.Features["chat"].Options["node"] = chatNode
		case "bbs":
			appSettings.Features["bbs"].Enabled = bbsEnabled
		case "bbs-port":
			appSettings.Features["bbs"].Port = bbsPort
		case "bbs-call":
			appSettings.Features["bbs"].Callsign = bbsCallsign
		case "bbs-password":
			appSettings.Features["bbs"].Password = bbsPassword
		case "node":
			appSettings.Features["node"].Enabled = nodeEnabled
		case "node-port":
			appSettings.Features["node"].Port = nodePort
		case "node-call":
			appSettings.Features["node"].Callsign = nodeCallsign
		case "node-password":
			appSettings.Features["node"].Password = nodePassword
		case "host":
			// Apply host to all features that still have default host
			for _, fs := range appSettings.Features {
				if fs.Host == "localhost" || fs.Host == "" {
					fs.Host = hostname
				}
			}
		}
	})

	// For features enabled via CLI, fill in missing callsign/password from main flags
	for _, name := range []string{"chat", "bbs", "node"} {
		fs := appSettings.Features[name]
		if fs.Callsign == "" {
			fs.Callsign = callsign
		}
		if fs.Password == "" {
			fs.Password = password
		}
		if fs.Host == "" {
			fs.Host = hostname
		}
	}

	// Save merged settings
	if err := appSettings.Save(); err != nil {
		mainLog.Warnw("Failed to save settings", "error", err)
	}

	dataBuffer = newCircularBuffer(bufferSize)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Set up HTTP routes and WebSocket handler
	setupRoutes()
	setupChatRoutes()
	setupBBSRoutes()
	setupNodeRoutes()

	// Auto-connect features with saved settings
	autoConnectFeatures()

	// Initialize link stats storage (used for both local stats and neighbor CQ data)
	storage, err := NewLinkStatsStorage("linkstats.db")
	if err != nil {
		mainLog.Errorw("Failed to open link stats database", "error", err)
	}
	neighborStorageRef = storage

	// Initialize stats collector if enabled
	if statsEnabled {
		statsCall := statsCallsign
		if statsCall == "" {
			statsCall = callsign
		}
		statsPwd := statsPassword
		if statsPwd == "" {
			statsPwd = password
		}
		interval := time.Duration(statsInterval) * time.Second

		collector := NewLinkStatsCollector(LinkStatsCollectorConfig{
			Hostname:        hostname,
			Port:            statsPort,
			Callsign:        statsCall,
			Password:        statsPwd,
			PollInterval:    interval,
			DisableCQ:       statsNoCQ,
			DisableBulletin: statsNoBulletin,
		}, storage)

		collector.SetBroadcastFunc(BroadcastLinkStats)
		collector.SetMetricsUpdateFunc(UpdateLinkStatsMetrics)

		// Set reference for WebSocket handlers
		linkStatsCollectorRef = collector

		mainLog.Infow("Starting link stats collector",
			"callsign", statsCall, "host", hostname, "port", statsPort, "interval", interval)
		go collector.Run(ctx)
	}

	// Start the HTTP server
	go func() {
		mainLog.Infow("Starting HTTP server", "port", 8212)
		if err := http.ListenAndServe(":8212", nil); err != nil {
			mainLog.Fatalw("HTTP server failed", "error", err)
		}
	}()

	// Main connection loop
	firstConnect := true
	for {
		select {
		case <-ctx.Done():
			return
		default:
			SetMonitorConnectionState(state_CONNECTING)
			if !firstConnect {
				IncrementMonitorReconnects()
			}
			firstConnect = false

			conn, err := connectWithRetry(ctx)
			if err != nil {
				mainLog.Errorw("Failed to establish connection", "error", err)
				SetMonitorConnectionState(state_ERR)
				// Simple backoff before retrying connectWithRetry to avoid tight loop on context errors
				time.Sleep(initialBackoff)
				continue
			}

			if err := initializeConnection(conn); err != nil {
				mainLog.Errorw("Failed to initialize connection", "error", err)
				SetMonitorConnectionState(state_ERR)
				conn.Close()
				time.Sleep(initialBackoff) // Backoff before retrying connection
				continue
			}

			// Handle the connection - keepalive is now managed inside handleConnection
			if err := handleConnection(ctx, conn); err != nil {
				mainLog.Errorw("Connection error", "error", err)
			}

			// Close the connection before retrying
			conn.Close()
			SetMonitorConnectionState(state_CONNECTING)

			// Small delay before reconnecting to avoid tight loop if handleConnection exits immediately
			time.Sleep(time.Second)
		}
	}
}

// autoConnectFeatures connects features that are enabled in settings with valid credentials.
func autoConnectFeatures() {
	for _, name := range []string{"chat", "bbs", "node"} {
		fs := appSettings.GetFeature(name)
		if fs == nil || !fs.Enabled || fs.Callsign == "" {
			continue
		}

		config := fs.ToFeatureConfig()
		mainLog.Infow("Auto-connecting feature", "feature", name, "host", config.Host, "port", config.Port, "callsign", config.Callsign)
		connectFeatureByName(name, config)
	}
}

func connectMonitorString(nump int) string {
	var portmask int64
	for i := range nump {
		portmask |= 1 << i
	}
	return fmt.Sprintf(`\\\\%x 1 1 1 0 0 0 1`, portmask)
}
