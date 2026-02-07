// send-routes-via-cq - TARPN Link Status Broadcaster
//
// This program connects to a local G8BPQ packet radio node via Telnet (port 8010),
// retrieves the routes table using the "R R" command, parses it, and broadcasts
// link status information via CQ on each active port.
//
// Rewritten in Go for portability - based on original C version by TARPN project.

package main

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Version is set at build time via -ldflags "-X main.Version=..."
var Version = "dev"

const (
	NodeAddress = "127.0.0.1:8010"
	LogFileName = "/var/log/tarpn_linkstatus.log"
	MaxRoutes   = 22
	MaxPorts    = 32 // Supports higher port numbers
)

// Default ports to skip (can be overridden via command line)
var skipPorts = map[int]bool{
	32: true, // Virtual TCP port - skip by default
}

// RouteEntry represents a single parsed route from the "R R" response
type RouteEntry struct {
	PortNumber     int
	Callsign       string
	Quality        int
	QualityIsReal  bool // Quality > 1
	ChevronSet     bool // Has '>' prefix (link is active)
	LockedRoutes   int  // Number of '!' marks (1 = locked, 2 = double locked)
	NumberOfNodes  int
	InfoFramesSent int
	RetriesSent    int
	PercentRetries int
	MysteryFigure1 int
	MysteryFigure2 int
	TimeLastNB     string
	BuffersToSend  int
	MysteryFigure3 int
}

// NodeConnection manages the telnet connection to the node
type NodeConnection struct {
	conn     net.Conn
	reader   *bufio.Reader
	callsign string
}

func main() {
	// Parse command line arguments
	for i := 1; i < len(os.Args); i++ {
		arg := os.Args[i]
		switch {
		case arg == "-v" || arg == "--version":
			fmt.Printf("TARPN send-routes-via-cq -- version %s\n", Version)
			os.Exit(0)
		case arg == "-h" || arg == "--help":
			printUsage()
			os.Exit(0)
		case strings.HasPrefix(arg, "--skip="):
			// Parse comma-separated list of ports to skip
			portList := strings.TrimPrefix(arg, "--skip=")
			parseSkipPorts(portList)
		case arg == "--no-skip":
			// Clear default skip list
			skipPorts = make(map[int]bool)
		default:
			fmt.Fprintf(os.Stderr, "Unknown argument: %s\n", arg)
			printUsage()
			os.Exit(1)
		}
	}

	// Connect and get routes table
	nc, err := connectToNode()
	if err != nil {
		log.Fatalf("Failed to connect to node: %v", err)
	}

	routesResponse, err := nc.getRoutesTable()
	if err != nil {
		log.Fatalf("Failed to get routes table: %v", err)
	}
	nc.close()

	// Parse the routes table
	myCallsign, routes, err := parseRoutesTable(routesResponse)
	if err != nil {
		log.Fatalf("Failed to parse routes table: %v", err)
	}

	// Broadcast status on each port and track link status
	linkStatus := make([]rune, MaxPorts+1)
	for i := range linkStatus {
		linkStatus[i] = '-'
	}

	// For each port, find the first locked route with real quality and broadcast
	for portNum := 1; portNum <= MaxPorts; portNum++ {
		// Skip configured ports
		if skipPorts[portNum] {
			linkStatus[portNum] = 's' // 's' for skipped
			continue
		}

		for _, route := range routes {
			if route.PortNumber == portNum && route.LockedRoutes > 0 && route.QualityIsReal {
				// Set link status
				if route.ChevronSet {
					linkStatus[portNum] = 'g'
				} else {
					linkStatus[portNum] = 'B'
				}

				// Broadcast on this port
				if err := broadcastOnPort(route, myCallsign); err != nil {
					log.Printf("Warning: failed to broadcast on port %d: %v", portNum, err)
				}
				break // Only broadcast once per port
			}
		}
	}

	// Write link status to log file
	writeLogFile(linkStatus)
}

func printUsage() {
	fmt.Printf(`TARPN send-routes-via-cq -- version %s

Usage: send-routes-via-cq [options]

Options:
  -v, --version     Show version and exit
  -h, --help        Show this help message
  --skip=PORTS      Comma-separated list of ports to skip (default: 32)
  --no-skip         Don't skip any ports (clear default skip list)

Examples:
  send-routes-via-cq                    # Run with default settings (skip port 32)
  send-routes-via-cq --skip=32,33       # Skip ports 32 and 33
  send-routes-via-cq --no-skip          # Don't skip any ports
  send-routes-via-cq --skip=            # Don't skip any ports (empty list)
`, Version)
}

func parseSkipPorts(portList string) {
	// Clear existing skip list
	skipPorts = make(map[int]bool)

	if portList == "" {
		return
	}

	parts := strings.Split(portList, ",")
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		portNum, err := strconv.Atoi(p)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: invalid port number '%s', ignoring\n", p)
			continue
		}
		skipPorts[portNum] = true
	}
}

// connectToNode establishes a telnet connection to the node and logs in
func connectToNode() (*NodeConnection, error) {
	conn, err := net.DialTimeout("tcp", NodeAddress, 10*time.Second)
	if err != nil {
		return nil, fmt.Errorf("failed to connect: %w (is the NODE software running?)", err)
	}

	nc := &NodeConnection{
		conn:   conn,
		reader: bufio.NewReader(conn),
	}

	// Set read deadline for initial handshake
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))

	// Read welcome message and login prompt
	if _, err := nc.readResponse(); err != nil {
		nc.close()
		return nil, fmt.Errorf("failed to read welcome: %w", err)
	}

	// Send blank line to get clean login prompt
	if err := nc.send("\r"); err != nil {
		nc.close()
		return nil, err
	}

	// Read login prompt (contains our callsign)
	prompt, err := nc.readResponse()
	if err != nil {
		nc.close()
		return nil, fmt.Errorf("failed to read login prompt: %w", err)
	}

	// Extract callsign from prompt (format: "CALLSIGN:")
	callsign := extractCallsign(prompt)
	if callsign == "" {
		nc.close()
		return nil, fmt.Errorf("failed to extract callsign from prompt: %s", prompt)
	}
	nc.callsign = callsign

	// Login with callsign
	if err := nc.send(callsign + "\r"); err != nil {
		nc.close()
		return nil, err
	}
	if _, err := nc.readResponse(); err != nil {
		nc.close()
		return nil, err
	}

	// Send password
	if err := nc.send("p\r"); err != nil {
		nc.close()
		return nil, err
	}
	if _, err := nc.readResponse(); err != nil {
		nc.close()
		return nil, err
	}

	// Send privileged password command
	if err := nc.send("password\r"); err != nil {
		nc.close()
		return nil, err
	}
	if _, err := nc.readResponse(); err != nil {
		nc.close()
		return nil, err
	}

	return nc, nil
}

// extractCallsign extracts the callsign from the login prompt
func extractCallsign(prompt string) string {
	// Clean up the prompt - remove control characters and find callsign before ':'
	cleaned := strings.Map(func(r rune) rune {
		if r >= ' ' && r <= '~' {
			return r
		}
		return -1
	}, prompt)

	// Find the colon and extract what's before it
	idx := strings.Index(cleaned, ":")
	if idx == -1 {
		return ""
	}

	callsign := strings.TrimSpace(cleaned[:idx])

	// Validate callsign length (4-7 characters including SSID)
	if len(callsign) < 3 || len(callsign) > 9 {
		return ""
	}

	return callsign
}

// send sends a string to the node
func (nc *NodeConnection) send(s string) error {
	nc.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	_, err := nc.conn.Write([]byte(s))
	return err
}

// readResponse reads a response from the node
func (nc *NodeConnection) readResponse() (string, error) {
	nc.conn.SetReadDeadline(time.Now().Add(2 * time.Second))

	var response strings.Builder
	buf := make([]byte, 1024)

	for {
		n, err := nc.conn.Read(buf)
		if err != nil {
			// Timeout is expected - means we got all data
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				break
			}
			if response.Len() > 0 {
				break
			}
			return "", err
		}
		response.Write(buf[:n])

		// Brief pause to allow more data to arrive
		time.Sleep(100 * time.Millisecond)
	}

	return response.String(), nil
}

// close closes the connection
func (nc *NodeConnection) close() {
	nc.conn.Close()
}

// getRoutesTable sends "R R" command and returns the response
func (nc *NodeConnection) getRoutesTable() (string, error) {
	if err := nc.send("R R\r"); err != nil {
		return "", err
	}

	response, err := nc.readResponse()
	if err != nil {
		return "", err
	}

	return response, nil
}

// parseRoutesTable parses the "R R" response into route entries
// Returns: myCallsign, routes, error
func parseRoutesTable(response string) (string, []RouteEntry, error) {
	var routes []RouteEntry
	var myCallsign string

	// Extract my callsign from first line (format: "XXXX:CALLSIGN-N} Routes")
	callsignRe := regexp.MustCompile(`:([A-Z0-9]+-?\d*)\}`)
	if match := callsignRe.FindStringSubmatch(response); len(match) > 1 {
		myCallsign = match[1]
	}

	// Split into lines
	lines := splitRoutes(response)

	for _, line := range lines {
		route, ok := parseRouteLine(line)
		if ok {
			routes = append(routes, route)
		}
	}

	return myCallsign, routes, nil
}

// splitRoutes splits the response into individual route lines
func splitRoutes(response string) []string {
	var result []string

	// Normalize line endings
	response = strings.ReplaceAll(response, "\r\n", "\n")
	response = strings.ReplaceAll(response, "\r", "\n")

	lines := strings.Split(response, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)

		// Skip empty lines and header line
		if line == "" || strings.Contains(line, "} Routes") || strings.Contains(line, "}Routes") {
			continue
		}

		result = append(result, line)
	}

	return result
}

// parseRouteLine parses a single route line
func parseRouteLine(line string) (RouteEntry, bool) {
	var route RouteEntry

	// Check for chevron (active link indicator)
	// Handle both "> 32" and ">32" formats (with or without space after chevron)
	if strings.HasPrefix(line, ">") {
		route.ChevronSet = true
		line = strings.TrimPrefix(line, ">")
		// Don't TrimSpace here - we need to preserve the case where there's no space
		// The regex will handle leading whitespace
	}

	// Use regex to parse the line
	// Format: port callsign quality nodes[!|!!] infoframes retries percent m1 m2 time buffers m3 [trailing]
	// Examples:
	//   2 N2IRZ-2   200   0!!   0    0      0 0 00:00  0 0
	//   32 WA2M-9    200   1!   0    0      0 0 00:00  0 0 41430
	// Note: percent field may be empty or contain "0" or "18%" etc.
	// Note: there may be trailing data after the last field (like 41430)

	// Flexible regex to handle:
	// - Optional leading whitespace
	// - Variable spacing between fields
	// - 0, 1, or 2 exclamation marks
	// - Percent field with or without % sign, or just whitespace
	// - Optional trailing data
	re := regexp.MustCompile(`^\s*(\d+)\s+([A-Z0-9]+-?\d*)\s+(\d+)\s+(\d+)(!{0,2})\s*(\d+)\s+(\d+)\s+(\d+%?|\s*)\s*(\d+)\s+(\d+)\s+(\d+:\d+)\s+(\d+)\s+(\d+)`)

	match := re.FindStringSubmatch(line)
	if match == nil {
		// Try alternate pattern for lines where percent is just a number (no %)
		re2 := regexp.MustCompile(`^\s*(\d+)\s+([A-Z0-9]+-?\d*)\s+(\d+)\s+(\d+)(!{0,2})\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+:\d+)\s+(\d+)\s+(\d+)`)
		match = re2.FindStringSubmatch(line)
		if match == nil {
			return route, false
		}
	}

	route.PortNumber, _ = strconv.Atoi(match[1])
	route.Callsign = match[2]
	route.Quality, _ = strconv.Atoi(match[3])
	route.QualityIsReal = route.Quality > 1
	route.NumberOfNodes, _ = strconv.Atoi(match[4])
	route.LockedRoutes = len(match[5]) // Count '!' marks (0, 1, or 2)
	route.InfoFramesSent, _ = strconv.Atoi(match[6])
	route.RetriesSent, _ = strconv.Atoi(match[7])

	// Parse percent (may have % suffix or be empty)
	percentStr := strings.TrimSuffix(strings.TrimSpace(match[8]), "%")
	if percentStr != "" {
		route.PercentRetries, _ = strconv.Atoi(percentStr)
	}

	route.MysteryFigure1, _ = strconv.Atoi(match[9])
	route.MysteryFigure2, _ = strconv.Atoi(match[10])
	route.TimeLastNB = match[11]
	route.BuffersToSend, _ = strconv.Atoi(match[12])
	route.MysteryFigure3, _ = strconv.Atoi(match[13])

	return route, true
}

// broadcastOnPort sends a CQ message with status info on a specific port
func broadcastOnPort(route RouteEntry, myCallsign string) error {
	nc, err := connectToNode()
	if err != nil {
		return err
	}
	defer nc.close()

	// Listen on the port
	listenCmd := fmt.Sprintf("listen %d\r", route.PortNumber)
	if err := nc.send(listenCmd); err != nil {
		return err
	}
	if _, err := nc.readResponse(); err != nil {
		return err
	}

	// Build status message
	chevronChar := 'n'
	if route.ChevronSet {
		chevronChar = '>'
	}

	statusMsg := fmt.Sprintf("[TARPNstat V2]~%s~%c~tx%d~ret%d~buf%d~",
		myCallsign,
		chevronChar,
		route.InfoFramesSent,
		route.RetriesSent,
		route.BuffersToSend,
	)

	// Send CQ
	cqCmd := fmt.Sprintf("CQ %s\r", statusMsg)
	if err := nc.send(cqCmd); err != nil {
		return err
	}
	if _, err := nc.readResponse(); err != nil {
		return err
	}

	return nil
}

// writeLogFile writes the link status to the log file
func writeLogFile(linkStatus []rune) {
	f, err := os.OpenFile(LogFileName, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("Warning: could not open log file: %v", err)
		return
	}
	defer f.Close()

	// Build status string
	var statusStr strings.Builder
	for i := 1; i <= MaxPorts; i++ {
		switch linkStatus[i] {
		case 'g':
			statusStr.WriteString("good")
		case 'B':
			statusStr.WriteString("BAD!")
		case 's':
			statusStr.WriteString("skip")
		default:
			statusStr.WriteString("----")
		}
	}

	// Format timestamp
	timestamp := time.Now().Format("2006-01-02 15:04:05")

	logLine := fmt.Sprintf("%s -- %s\n", timestamp, statusStr.String())
	f.WriteString(logLine)
}
