package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"net"
	"strings"
	"time"
)

// Telnet protocol constants (RFC 854)
const (
	TelnetIAC  byte = 255 // Interpret As Command
	TelnetDONT byte = 254 // Refuse to perform option
	TelnetDO   byte = 253 // Request to perform option
	TelnetWONT byte = 252 // Refusal to perform option
	TelnetWILL byte = 251 // Agreement to perform option
	TelnetSB   byte = 250 // Subnegotiation Begin
	TelnetGA   byte = 249 // Go Ahead
	TelnetEL   byte = 248 // Erase Line
	TelnetEC   byte = 247 // Erase Character
	TelnetAYT  byte = 246 // Are You There
	TelnetAO   byte = 245 // Abort Output
	TelnetIP   byte = 244 // Interrupt Process
	TelnetSE   byte = 240 // Subnegotiation End

	// Telnet options
	TelnetOptEcho byte = 1 // Echo
	TelnetOptSGA  byte = 3 // Suppress Go-Ahead
)

// TelnetConn wraps a net.Conn with telnet protocol handling
type TelnetConn struct {
	conn   net.Conn
	reader *bufio.Reader
	logger interface {
		Debugf(format string, args ...interface{})
	}
}

// TelnetLogger interface for optional logging
type TelnetLogger interface {
	Debugf(format string, args ...interface{})
}

// nullLogger is a no-op logger
type nullLogger struct{}

func (nullLogger) Debugf(format string, args ...interface{}) {}

// NewTelnetConn creates a new telnet connection wrapper
// Handles initial IAC negotiation and returns a ready-to-use connection
func NewTelnetConn(conn net.Conn, negotiationTimeout time.Duration, logger TelnetLogger) (*TelnetConn, error) {
	if logger == nil {
		logger = nullLogger{}
	}

	tc := &TelnetConn{
		conn:   conn,
		logger: logger,
	}

	// Handle telnet negotiation
	leftover, err := tc.negotiate(negotiationTimeout)
	if err != nil {
		return nil, err
	}

	// Create buffered reader, prepending any leftover text
	if len(leftover) > 0 {
		combined := io.MultiReader(bytes.NewReader(leftover), conn)
		tc.reader = bufio.NewReader(combined)
	} else {
		tc.reader = bufio.NewReader(conn)
	}

	return tc, nil
}

// negotiate handles the initial telnet IAC negotiation
// Returns any leftover readable text that was consumed during negotiation
func (tc *TelnetConn) negotiate(timeout time.Duration) ([]byte, error) {
	tc.logger.Debugf("Starting telnet negotiation (timeout=%v)", timeout)
	tc.conn.SetReadDeadline(time.Now().Add(timeout))
	defer tc.conn.SetReadDeadline(time.Time{})

	buf := make([]byte, 256)
	var leftover []byte

	for {
		n, err := tc.conn.Read(buf)
		if err != nil {
			// Timeout or error - done with negotiation
			break
		}

		tc.logger.Debugf("Telnet received (%d bytes): %v", n, buf[:n])

		// Respond to IAC commands
		responses := tc.processIAC(buf[:n])
		if len(responses) > 0 {
			tc.logger.Debugf("Sending telnet responses: %v", responses)
			tc.conn.Write(responses)
		}

		// Find where readable text starts (skip telnet IAC sequences)
		textStart := -1
		for i, b := range buf[:n] {
			if b >= 0x20 && b < 0x7f {
				textStart = i
				break
			}
		}
		if textStart >= 0 {
			leftover = make([]byte, n-textStart)
			copy(leftover, buf[textStart:n])
			tc.logger.Debugf("Saved leftover text: %q", string(leftover))
			break
		}
	}

	return leftover, nil
}

// processIAC processes telnet IAC commands and returns appropriate responses
func (tc *TelnetConn) processIAC(data []byte) []byte {
	var responses []byte

	for i := 0; i < len(data)-2; i++ {
		if data[i] != TelnetIAC {
			continue
		}

		cmd := data[i+1]
		opt := data[i+2]

		switch cmd {
		case TelnetWILL:
			if opt == TelnetOptEcho {
				// Don't want server to echo our input
				tc.logger.Debugf("Telnet: Server WILL ECHO, responding DONT")
				responses = append(responses, TelnetIAC, TelnetDONT, opt)
			} else {
				// Accept other options (like SGA)
				tc.logger.Debugf("Telnet: Server WILL %d, responding DO", opt)
				responses = append(responses, TelnetIAC, TelnetDO, opt)
			}
			i += 2

		case TelnetDO:
			// Server asks us to do something, we decline
			tc.logger.Debugf("Telnet: Server DO %d, responding WONT", opt)
			responses = append(responses, TelnetIAC, TelnetWONT, opt)
			i += 2

		case TelnetDONT:
			tc.logger.Debugf("Telnet: Server DONT %d", opt)
			i += 2

		case TelnetWONT:
			tc.logger.Debugf("Telnet: Server WONT %d", opt)
			i += 2
		}
	}

	return responses
}

// Reader returns the buffered reader for the connection
func (tc *TelnetConn) Reader() *bufio.Reader {
	return tc.reader
}

// Conn returns the underlying net.Conn
func (tc *TelnetConn) Conn() net.Conn {
	return tc.conn
}

// Write writes data to the connection
func (tc *TelnetConn) Write(data []byte) (int, error) {
	return tc.conn.Write(data)
}

// WriteString writes a string followed by CR to the connection
func (tc *TelnetConn) WriteString(s string) error {
	_, err := tc.conn.Write([]byte(s + "\r"))
	return err
}

// WriteCommand writes a command followed by CRLF (telnet standard)
func (tc *TelnetConn) WriteCommand(cmd string) error {
	_, err := tc.conn.Write([]byte(cmd + "\r\n"))
	return err
}

// SetReadDeadline sets the read deadline on the underlying connection
func (tc *TelnetConn) SetReadDeadline(t time.Time) error {
	return tc.conn.SetReadDeadline(t)
}

// Close closes the underlying connection
func (tc *TelnetConn) Close() error {
	return tc.conn.Close()
}

// ReadUntil reads lines until one matches the predicate or timeout
// Returns all lines read and whether a match was found
func (tc *TelnetConn) ReadUntil(predicate func(string) bool, timeout time.Duration) ([]string, bool, error) {
	var lines []string
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		tc.conn.SetReadDeadline(time.Now().Add(1 * time.Second))
		line, err := tc.reader.ReadString('\n')
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				// Check partial line for match
				if line != "" && predicate(strings.TrimRight(line, "\r\n")) {
					lines = append(lines, strings.TrimRight(line, "\r\n"))
					return lines, true, nil
				}
				continue
			}
			return lines, false, err
		}

		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			continue
		}

		lines = append(lines, line)
		tc.logger.Debugf("ReadUntil: %q", line)

		if predicate(line) {
			return lines, true, nil
		}
	}

	return lines, false, nil
}

// ReadLine reads a single line with timeout
func (tc *TelnetConn) ReadLine(timeout time.Duration) (string, error) {
	tc.conn.SetReadDeadline(time.Now().Add(timeout))
	line, err := tc.reader.ReadString('\n')
	if err != nil {
		return strings.TrimRight(line, "\r\n"), err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

// Authenticate performs standard LinBPQ telnet authentication
// For standard telnet port (not FBB/monitor port):
// 1. Send callsign, wait for password prompt
// 2. Send password, wait for CTEXT ("Connected to")
// Returns the remote node name extracted from CTEXT if available
func (tc *TelnetConn) Authenticate(callsign, password string, promptTimeout time.Duration) (remoteNode string, err error) {
	// Send callsign
	tc.logger.Debugf("Sending callsign: %s", callsign)
	if err := tc.WriteString(callsign); err != nil {
		return "", fmt.Errorf("failed to send callsign: %w", err)
	}

	// Wait for password prompt
	tc.logger.Debugf("Waiting for password prompt")
	_, found, err := tc.ReadUntil(func(line string) bool {
		lower := strings.ToLower(line)
		return strings.Contains(lower, "password") || strings.Contains(line, "type p") || strings.HasSuffix(line, ":")
	}, promptTimeout)

	if err != nil {
		return "", fmt.Errorf("error waiting for password prompt: %w", err)
	}
	if !found {
		return "", fmt.Errorf("timeout waiting for password prompt")
	}

	// Send password
	tc.logger.Debugf("Sending password")
	if err := tc.WriteString(password); err != nil {
		return "", fmt.Errorf("failed to send password: %w", err)
	}

	// Wait for CTEXT ("Connected to ... Telnet Server")
	tc.logger.Debugf("Waiting for CTEXT")
	lines, found, err := tc.ReadUntil(func(line string) bool {
		return strings.Contains(line, "Connected to") && strings.Contains(line, "Telnet")
	}, promptTimeout)

	if err != nil {
		return "", fmt.Errorf("error waiting for CTEXT: %w", err)
	}
	if !found {
		return "", fmt.Errorf("authentication failed - no CTEXT received")
	}

	// Extract remote node name from CTEXT
	for _, line := range lines {
		if idx := strings.Index(line, "Connected to "); idx >= 0 {
			rest := line[idx+len("Connected to "):]
			if endIdx := strings.Index(rest, "'s "); endIdx > 0 {
				remoteNode = rest[:endIdx]
				tc.logger.Debugf("Remote node identified: %s", remoteNode)
			}
		}
	}

	tc.logger.Debugf("Authentication successful")
	return remoteNode, nil
}

// AuthenticateFBB performs LinBPQ FBB/monitor port authentication
// FBB mode doesn't send prompts - we send credentials immediately
// Then send BPQTERMTCP and wait for "Connected to TelnetServer"
func (tc *TelnetConn) AuthenticateFBB(callsign, password string, timeout time.Duration) error {
	// FBB mode: send credentials immediately (no prompts)
	tc.logger.Debugf("FBB auth: sending callsign")
	if err := tc.WriteString(callsign); err != nil {
		return fmt.Errorf("failed to send callsign: %w", err)
	}

	tc.logger.Debugf("FBB auth: sending password")
	if err := tc.WriteString(password); err != nil {
		return fmt.Errorf("failed to send password: %w", err)
	}

	tc.logger.Debugf("FBB auth: sending BPQTERMTCP")
	if err := tc.WriteString("BPQTERMTCP"); err != nil {
		return fmt.Errorf("failed to send BPQTERMTCP: %w", err)
	}

	// Wait for "Connected to TelnetServer"
	tc.logger.Debugf("FBB auth: waiting for connection confirmation")
	_, found, err := tc.ReadUntil(func(line string) bool {
		return strings.Contains(line, "Connected to TelnetServer")
	}, timeout)

	if err != nil {
		return fmt.Errorf("error during FBB auth: %w", err)
	}
	if !found {
		return fmt.Errorf("FBB authentication failed - no confirmation received")
	}

	tc.logger.Debugf("FBB authentication successful")
	return nil
}

// CleanTelnetBytes removes telnet IAC sequences and non-printable characters
func CleanTelnetBytes(s string) string {
	var result []byte
	data := []byte(s)
	for i := 0; i < len(data); i++ {
		if data[i] == TelnetIAC && i+2 < len(data) {
			// Skip IAC + command + option
			i += 2
			continue
		}
		// Keep printable ASCII and common whitespace
		if data[i] >= 32 && data[i] < 127 || data[i] == '\t' {
			result = append(result, data[i])
		}
	}
	return strings.TrimSpace(string(result))
}

// StripTelnetAndPrompts removes telnet bytes and login prompts, keeping only content from CTEXT onward
func StripTelnetAndPrompts(lines []string) []string {
	var result []string
	foundCtext := false
	for _, line := range lines {
		if strings.Contains(line, "Connected to") || strings.Contains(line, "Telnet Server") {
			foundCtext = true
			cleaned := CleanTelnetBytes(line)
			if cleaned != "" {
				result = append(result, cleaned)
			}
			continue
		}
		if foundCtext {
			cleaned := CleanTelnetBytes(line)
			if cleaned != "" {
				result = append(result, cleaned)
			}
		}
	}
	return result
}
