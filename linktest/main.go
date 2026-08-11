// linktest - transmit a run of numbered test packets out one radio port.
//
// A portable reimplementation of TARPN's `linktest` (built from
// transmit_test.c, distributed only as a 32-bit ARM binary), so that the
// LINKTEST node command works on 64-bit installations.
//
// Behaviour was recovered by disassembling linktest-app version 9. What it
// does, and what this reproduces:
//
//   - connect to the LinBPQ telnet port
//   - log in by reading the callsign back out of the node's own login prompt
//   - "lis <port>" to attach to the requested radio port
//   - send 100 CQ frames, each carrying a sequence number and a rolling
//     window of a fixed pangram, two seconds apart
//
// The point is that a listening neighbour can see which of the numbered
// frames arrived, so gaps in the sequence measure the link rather than
// anything about the node.
//
// Deliberate differences from the original are marked "DIFFERENCE" below.
// Everything else is byte-for-byte what the original sends.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// Version is set at build time via -ldflags "-X main.Version=..."
var Version = "dev"

// OriginalVersion is what the binary this was derived from reports, kept so
// `linktest v` stays meaningful to anyone comparing nodes.
const OriginalVersion = 9

const (
	// The original hardcodes 127.0.1.1:8010. 127.0.1.1 is the Debian
	// hostname address; any 127/8 address reaches a LinBPQ listening on all
	// interfaces. DIFFERENCE: default to 127.0.0.1, which exists everywhere,
	// and make it settable.
	defaultHost = "127.0.0.1"
	defaultPort = 8010

	// snprintf(payload, 82, "test%02u:%s", n, window) in the original, so the
	// payload is at most 81 characters plus the terminator.
	payloadSize = 82

	defaultCount    = 100
	defaultInterval = 2 * time.Second

	// The original memcpy's 218 bytes of this into a stack buffer: 117
	// characters of text, 100 dots of padding, then the NUL. The window walks
	// through it one character per transmission, which is what makes each
	// frame's contents differ.
	foxText = " THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG'S BACK AGAIN AND AGAIN UNTIL HE WAS EATEN BY AN EXTRA TERRESTRIAL RODENT" +
		"...................................................................................................."

	// offset++ then wrap when >198, so the window start cycles 1..198,0.
	maxOffset = 198
)

func main() {
	var (
		host     = flag.String("host", defaultHost, "host running the node software")
		tcpPort  = flag.Int("tcp-port", defaultPort, "LinBPQ telnet port")
		count    = flag.Int("count", defaultCount, "number of transmissions")
		interval = flag.Duration("interval", defaultInterval, "delay between transmissions")
		password = flag.String("password", "p", "telnet password")
		showVer  = flag.Bool("v", false, "show version")
	)
	flag.Usage = usage
	flag.Parse()

	args := flag.Args()

	// The original's argument handling, preserved so existing callers work:
	//   linktest v|x        version
	//   linktest <port>     run, printing each frame as it goes
	//   linktest <port> X   run quietly (TARPN passes NOPRINT)
	if *showVer || (len(args) == 1 && (strings.HasPrefix(args[0], "v") || strings.HasPrefix(args[0], "x"))) {
		fmt.Printf("TARPN linktest -- version %d (portable reimplementation, build %s)\n", OriginalVersion, Version)
		return
	}
	if len(args) < 1 || len(args) > 2 {
		usage()
		os.Exit(1)
	}

	radioPort, err := strconv.Atoi(args[0])
	if err != nil || radioPort < 1 || radioPort > 32 {
		// DIFFERENCE: the original passes atoi() output straight through, so
		// a typo becomes "lis 0" and it sits there transmitting nothing.
		fmt.Fprintf(os.Stderr, "'%s' is not a valid port number\n", args[0])
		os.Exit(1)
	}
	verbose := len(args) == 1

	if verbose {
		fmt.Printf("TARPN linktest %d -- version %d\n", radioPort, OriginalVersion)
		fmt.Printf("Ths program transmits an %d byte text string, %d times, to CQ, on the specified port\n",
			payloadSize, *count)
		fmt.Println("A limitation of the G8BPQ PILINBPQ program restricts the longest command to 100 bytes")
	}

	if err := run(*host, *tcpPort, radioPort, *count, *interval, *password, verbose); err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, "Usage: %s Node-Port-Number [NOPRINT]\n\n", os.Args[0])
	fmt.Fprintln(os.Stderr, "Transmits numbered test frames to CQ on one radio port so a neighbour")
	fmt.Fprintln(os.Stderr, "can count how many arrive.")
	fmt.Fprintln(os.Stderr, "\nOptions:")
	flag.PrintDefaults()
}

// node wraps the telnet session to LinBPQ.
type node struct {
	conn net.Conn
	r    *bufio.Reader
}

func dial(host string, port int) (*node, error) {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), 10*time.Second)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to socket.  Is the NODE software running? (%w)", err)
	}
	return &node{conn: conn, r: bufio.NewReader(conn)}, nil
}

func (n *node) close() { _ = n.conn.Close() }

func (n *node) send(s string) error {
	if err := n.conn.SetWriteDeadline(time.Now().Add(10 * time.Second)); err != nil {
		return err
	}
	if _, err := n.conn.Write([]byte(s)); err != nil {
		return fmt.Errorf("failed to send data to socket: %w", err)
	}
	return nil
}

// recv reads whatever the node has to say.
//
// DIFFERENCE: the original calls sleep(1) then a blocking recv(), which hangs
// forever if the node goes quiet. This uses a deadline and treats a timeout as
// "nothing more to read", which is only fatal where a reply is actually
// required.
func (n *node) recv(wait time.Duration) (string, error) {
	if err := n.conn.SetReadDeadline(time.Now().Add(wait)); err != nil {
		return "", err
	}
	buf := make([]byte, 1024)
	num, err := n.r.Read(buf)
	if err != nil {
		if ne, ok := err.(net.Error); ok && ne.Timeout() {
			return "", nil
		}
		return "", fmt.Errorf("failed to receive data from socket: %w", err)
	}
	return string(buf[:num]), nil
}

// callsignFromPrompt recovers the login name from the node's own prompt.
//
// The node is configured with LOGINPROMPT=<callsign>: so the original takes
// the first 20 bytes of the prompt, drops everything at or below a space, then
// looks for a colon within the first 8 characters. The text before it is the
// callsign, and it must be 4 to 6 characters or the original bails out.
func callsignFromPrompt(prompt string) (string, error) {
	var compact []byte
	for i := 0; i < len(prompt) && i < 20; i++ {
		if prompt[i] > ' ' {
			compact = append(compact, prompt[i])
		}
	}

	colon := -1
	for i := 0; i < len(compact) && i < 8; i++ {
		if compact[i] == ':' {
			colon = i
			break
		}
	}
	if colon < 4 || colon > 6 {
		return "", fmt.Errorf("callsign field didn't work out.  len=%d value=%q", colon, string(compact))
	}
	return string(compact[:colon]), nil
}

func run(host string, tcpPort, radioPort, count int, interval time.Duration, password string, verbose bool) error {
	n, err := dial(host, tcpPort)
	if err != nil {
		return err
	}
	defer n.close()

	// Banner, then a bare CR to draw out the login prompt.
	if _, err := n.recv(5 * time.Second); err != nil {
		return err
	}
	if err := n.send("\r"); err != nil {
		return err
	}
	prompt, err := n.recv(5 * time.Second)
	if err != nil {
		return err
	}

	callsign, err := callsignFromPrompt(prompt)
	if err != nil {
		return err
	}

	if err := n.send(callsign + "\r"); err != nil {
		return err
	}
	if _, err := n.recv(5 * time.Second); err != nil {
		return err
	}

	// TARPN's generated bpq32.cfg defines the sysop user with password "p".
	if err := n.send(password + "\r"); err != nil {
		return err
	}
	if _, err := n.recv(5 * time.Second); err != nil {
		return err
	}

	// The original then sends the literal word "password". By this point the
	// session is already logged in, so the node answers with an invalid
	// command and it has no effect. Kept for fidelity with the original
	// exchange; harmless either way.
	if err := n.send("password\r"); err != nil {
		return err
	}
	if _, err := n.recv(5 * time.Second); err != nil {
		return err
	}

	// Attach to the radio port. Everything sent after this goes out there.
	if err := n.send(fmt.Sprintf("lis %d\r", radioPort)); err != nil {
		return err
	}
	if _, err := n.recv(5 * time.Second); err != nil {
		return err
	}

	if verbose {
		fmt.Printf("\nMade contact with port %d.  Now starting to send CQ messages.\r\n Do control C to exit\n", radioPort)
	}

	offset := 0
	for sent := 0; sent < count; sent++ {
		offset++
		if offset > maxOffset {
			offset = 0
		}

		window := foxText[offset:]
		payload := truncate(fmt.Sprintf("test%02d:%s", sent, window), payloadSize-1)

		if verbose {
			end := 10
			if len(window) < end {
				end = len(window)
			}
			fmt.Printf("CQ test%02d:%s\n", sent, window[:end])
		}

		if err := n.send(fmt.Sprintf("CQ %s\r\n", payload)); err != nil {
			return err
		}

		time.Sleep(interval)

		if _, err := n.recv(5 * time.Second); err != nil {
			return err
		}
	}

	fmt.Printf("We've done %d transmissions.  Quitting now\n", count)
	return nil
}

// truncate caps a string at n bytes, matching snprintf's behaviour.
func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}
