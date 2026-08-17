// tarpn-npa - neighbour/port association.
//
// Locks the NetROM route for each configured neighbour to the port it is
// actually heard on.
//
// Why this has to exist: every RF port is generated with
// IGNOREUNLOCKEDROUTES=1, and LinBPQ discards a NODES broadcast whose route is
// not locked (L3Code.c):
//
//	if ((ROUTE->NEIGHBOUR_FLAG) == 0)	// not a LOCKED ROUTE
//	    if (PORT->IgnoreUnlocked)
//	        return;
//
// Nothing in the generated config locks the NinoTNC ports, because /dev/ttyACM*
// numbering follows kernel enumeration order - the neighbour named in slot A is
// not reliably on port 1. So the association has to be discovered from what is
// actually being heard, which is what this does: MH per port, match against the
// neighbours named in node.conf, then lock.
//
// This replaces the closed-source 32-bit neighbor_port_association.app. That
// binary shipped unstripped, and its symbols gave the mechanism directly:
// RTS_GetTelnetConnectionToNode, LogIntoTelnetAndGetNeighborsHeardLists,
// CmpCallsignWithNodeInitNeighbor_SetAssigned,
// FillInNodePortCallsignAndRouteLockString, LogIntoTelnetAndSetRouteAndFrack -
// building "r <call> <port> 200 !" from the literals "r " and " 200 !".
//
// Two things the legacy app also did are deliberately not done here:
//
//   - "frack <ms>" per route. The stock template hardcoded FRACK=9000 in every
//     port block, so the per-neighbour value could only be applied at runtime.
//     This installation renders PORT_x_FRACK into the port blocks directly, so
//     the value is already right before the engine starts.
//   - "C <port> !" to connect to the neighbour. Links come up on demand; keying
//     a transmitter purely to populate a table is airtime for nothing.
package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var Version = "dev"

const (
	defaultNode    = "127.0.0.1:8010"
	defaultConfig  = "/etc/tarpn/node.conf"
	defaultQuality = 200

	// The telnet port. Routes on it belong to NetROM-over-TCP attachments such
	// as tarpn-chat, which are locked by config and have no RF port to discover.
	telnetPort = 32

	// Ports 1-10 are the NinoTNC slots A-J, 11 and 12 the manual serial ports.
	// Nothing above that carries a neighbour in this configuration.
	maxRFPort = 12
)

// errNoSuchPort means the node has no such port, which is the normal answer for
// most of the scan range on a node with a few radios.
var errNoSuchPort = errors.New("no such port")

type route struct {
	Port     int
	Callsign string
	Quality  int
	Nodes    int
	Locked   bool
}

// conn wraps the telnet session to the node.
type conn struct {
	c        net.Conn
	r        *bufio.Reader
	callsign string
	verbose  bool
}

func main() {
	var (
		nodeAddr = flag.String("node", defaultNode, "LinBPQ telnet address")
		confPath = flag.String("config", defaultConfig, "node.conf to read neighbours from")
		quality  = flag.Int("quality", defaultQuality, "route quality to set when locking")
		dryRun   = flag.Bool("dry-run", false, "report what would change, send nothing")
		verbose  = flag.Bool("verbose", false, "log every command and reply")
		showVer  = flag.Bool("version", false, "print version and exit")
	)
	flag.Usage = usage
	flag.Parse()

	if *showVer {
		fmt.Printf("tarpn-npa %s\n", Version)
		return
	}

	if err := run(*nodeAddr, *confPath, *quality, *dryRun, *verbose); err != nil {
		fmt.Fprintf(os.Stderr, "tarpn-npa: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `tarpn-npa - lock each neighbour's route to the port it is heard on

Reads the neighbours named in node.conf, asks the node which callsigns it has
heard on each port, and locks the route where the two agree. Without a locked
route LinBPQ ignores a neighbour's node broadcasts, because RF ports are
generated with IGNOREUNLOCKEDROUTES=1.

Usage: tarpn-npa [options]

`)
	flag.PrintDefaults()
}

func run(nodeAddr, confPath string, quality int, dryRun, verbose bool) error {
	wanted, err := readNeighbours(confPath)
	if err != nil {
		return err
	}
	if len(wanted) == 0 {
		fmt.Println("no neighbours configured in " + confPath + "; nothing to do")
		return nil
	}

	nc, err := dial(nodeAddr, verbose)
	if err != nil {
		return err
	}
	defer nc.close()

	existing, err := nc.routes()
	if err != nil {
		return fmt.Errorf("reading the route table: %w", err)
	}

	// Scan every RF port the config can describe, not just the ones with a
	// neighbour configured. The reason this program exists is that the slot a
	// neighbour is configured in need not be the port it is on, and that
	// includes moving onto a port nothing was configured for. Ports the node
	// does not have answer "Invalid Port" and are skipped quietly.
	heard := map[int]map[string]bool{}
	for port := 1; port <= maxRFPort; port++ {
		calls, err := nc.mheard(port)
		if err != nil {
			if errors.Is(err, errNoSuchPort) {
				continue
			}
			fmt.Printf("port %d: %v\n", port, err)
			continue
		}
		heard[port] = calls
	}

	changes := 0
	for _, call := range sortedCalls(wanted) {
		on := portsHearing(heard, call)

		switch len(on) {
		case 0:
			fmt.Printf("%-9s not heard on any configured port - leaving it alone\n", call)
			continue
		case 1:
			// good
		default:
			// A point-to-point link should only ever hear its own neighbour.
			// Locking the wrong one is worse than locking none, so stop.
			fmt.Printf("%-9s heard on ports %v - ambiguous, not locking\n", call, on)
			continue
		}

		port := on[0]
		configured := wanted[call]
		if port != configured {
			fmt.Printf("%-9s heard on port %d, but node.conf puts it on port %d\n",
				call, port, configured)
		}

		// Drop a lock that points somewhere the neighbour demonstrably is not.
		// Only ever done when it has been positively located elsewhere, so a
		// neighbour that is merely quiet keeps its route.
		for _, r := range existing {
			if r.Callsign == call && r.Locked && r.Port != port {
				fmt.Printf("%-9s unlocking stale route on port %d\n", call, r.Port)
				if !dryRun {
					if err := nc.unlock(call, r.Port); err != nil {
						return fmt.Errorf("unlocking %s on port %d: %w", call, r.Port, err)
					}
				}
				changes++
			}
		}

		if cur, ok := find(existing, call, port); ok && cur.Locked && cur.Quality == quality {
			if verbose {
				fmt.Printf("%-9s already locked on port %d at quality %d\n", call, port, quality)
			}
			continue
		}

		fmt.Printf("%-9s locking on port %d at quality %d\n", call, port, quality)
		if !dryRun {
			if err := nc.lock(call, port, quality); err != nil {
				return fmt.Errorf("locking %s on port %d: %w", call, port, err)
			}
		}
		changes++
	}

	if changes == 0 {
		fmt.Println("no changes needed")
		return nil
	}
	if dryRun {
		fmt.Printf("%d change(s) needed; nothing sent (--dry-run)\n", changes)
		return nil
	}

	// Persist, so the locks survive a restart. LinBPQ is built with AUTOSAVE=0
	// and only writes BPQNODES.dat on this command.
	if err := nc.saveNodes(); err != nil {
		return fmt.Errorf("saving the node table: %w", err)
	}
	fmt.Printf("%d change(s) applied and saved\n", changes)
	return nil
}

// ---------------------------------------------------------------------------
// node.conf
// ---------------------------------------------------------------------------

// slotPorts maps the NinoTNC slot letters to the LinBPQ port numbers the
// generated config assigns them.
var slotPorts = []struct {
	Slot string
	Port int
}{
	{"A", 1}, {"B", 2}, {"C", 3}, {"D", 4}, {"E", 5},
	{"F", 6}, {"G", 7}, {"H", 8}, {"I", 9}, {"J", 10},
}

// readNeighbours returns callsign -> the port node.conf believes it is on.
// The port is advisory: it is reported when it disagrees with reality, but the
// lock always follows what was actually heard.
func readNeighbours(path string) (map[string]int, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}
	defer f.Close()

	conf := map[string]string{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		conf[strings.TrimSpace(k)] = strings.TrimSpace(v)
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}

	out := map[string]int{}
	add := func(call string, port int) {
		call = strings.ToUpper(strings.TrimSpace(call))
		if call == "" || !validCall(call) {
			return
		}
		out[call] = port
	}

	for _, s := range slotPorts {
		add(conf["PORT_"+s.Slot+"_NEIGHBOR"], s.Port)
	}
	for _, p := range []int{11, 12} {
		key := fmt.Sprintf("PORT_%d_", p)
		if !isTrue(conf[key+"ENABLED"]) {
			continue
		}
		add(conf[key+"NEIGHBOR"], p)
	}
	return out, nil
}

func isTrue(s string) bool {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "true", "yes", "on", "1":
		return true
	}
	return false
}

var callRe = regexp.MustCompile(`^[A-Z0-9]{3,7}(-[0-9]{1,2})?$`)

func validCall(s string) bool { return callRe.MatchString(s) }

// ---------------------------------------------------------------------------
// Talking to the node
// ---------------------------------------------------------------------------

func dial(addr string, verbose bool) (*conn, error) {
	c, err := net.DialTimeout("tcp", addr, 10*time.Second)
	if err != nil {
		return nil, fmt.Errorf("connecting to %s: %w (is the node running?)", addr, err)
	}
	nc := &conn{c: c, r: bufio.NewReader(c), verbose: verbose}

	// Welcome banner, then a blank line to draw a clean login prompt.
	if _, err := nc.read(); err != nil {
		nc.close()
		return nil, fmt.Errorf("reading the welcome message: %w", err)
	}
	if err := nc.write("\r"); err != nil {
		nc.close()
		return nil, err
	}
	prompt, err := nc.read()
	if err != nil {
		nc.close()
		return nil, fmt.Errorf("reading the login prompt: %w", err)
	}

	// The prompt is the operator callsign followed by a colon, which is also
	// the username the generated config expects.
	call := callsignFromPrompt(prompt)
	if call == "" {
		nc.close()
		return nil, fmt.Errorf("could not read a callsign from the login prompt %q", clean(prompt))
	}
	nc.callsign = call

	for _, step := range []string{call, "p", "password"} {
		if err := nc.write(step + "\r"); err != nil {
			nc.close()
			return nil, err
		}
		if _, err := nc.read(); err != nil {
			nc.close()
			return nil, fmt.Errorf("during login: %w", err)
		}
	}

	// "password" with no argument authorises outright when the telnet user
	// carries the SYSOP flag (PWDCMD short-circuits on Secure_Session). If it
	// did not, the node answers with a five-number challenge instead, and the
	// route commands below would be refused.
	return nc, nil
}

func callsignFromPrompt(prompt string) string {
	cleaned := clean(prompt)
	i := strings.Index(cleaned, ":")
	if i < 0 {
		return ""
	}
	fields := strings.Fields(cleaned[:i])
	if len(fields) == 0 {
		return ""
	}
	call := strings.ToUpper(fields[len(fields)-1])
	if !validCall(call) {
		return ""
	}
	return call
}

func clean(s string) string {
	return strings.Map(func(r rune) rune {
		if r == '\r' || r == '\n' || (r >= ' ' && r <= '~') {
			return r
		}
		return -1
	}, s)
}

func (nc *conn) write(s string) error {
	if nc.verbose {
		fmt.Printf("  -> %s\n", strings.TrimSpace(s))
	}
	nc.c.SetWriteDeadline(time.Now().Add(5 * time.Second))
	_, err := nc.c.Write([]byte(s))
	return err
}

// read collects output until the node goes quiet. The node does not send a
// distinctive end-of-reply marker, so a short idle gap is the terminator.
func (nc *conn) read() (string, error) {
	nc.c.SetReadDeadline(time.Now().Add(3 * time.Second))

	var b strings.Builder
	buf := make([]byte, 4096)
	for {
		n, err := nc.c.Read(buf)
		if n > 0 {
			b.Write(buf[:n])
		}
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				break
			}
			if b.Len() > 0 {
				break
			}
			return "", err
		}
		// Let the rest of a split reply arrive before deciding it has ended.
		nc.c.SetReadDeadline(time.Now().Add(400 * time.Millisecond))
	}
	out := b.String()
	if nc.verbose {
		fmt.Printf("  <- %s\n", strings.TrimSpace(clean(out)))
	}
	return out, nil
}

func (nc *conn) command(cmd string) (string, error) {
	if err := nc.write(cmd + "\r"); err != nil {
		return "", err
	}
	return nc.read()
}

func (nc *conn) close() {
	nc.write("BYE\r")
	nc.c.Close()
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

// routeLine matches the non-verbose ROUTES output, which DisplayRoute writes as
//
//	"%s %d %s %d %d%s\r"  - active, port, callsign, quality, nodes, locked
//
// where locked is "", "!" (by config), "!!" (by sysop) or "!!!" (both).
var routeLine = regexp.MustCompile(`^\s*>?\s*(\d+)\s+([A-Z0-9-]+)\s+(\d+)\s+(\d+)\s*(!*)\s*$`)

func (nc *conn) routes() ([]route, error) {
	out, err := nc.command("ROUTES")
	if err != nil {
		return nil, err
	}
	return parseRoutes(out), nil
}

func parseRoutes(out string) []route {
	var rs []route
	for _, line := range lines(out) {
		m := routeLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		port, _ := strconv.Atoi(m[1])
		qual, _ := strconv.Atoi(m[3])
		nodes, _ := strconv.Atoi(m[4])
		rs = append(rs, route{
			Port:     port,
			Callsign: m[2],
			Quality:  qual,
			Nodes:    nodes,
			Locked:   m[5] != "",
		})
	}
	return rs
}

// mheard returns the set of callsigns heard on a port. Entries are written as
//
//	"%-10s %s %s\r"  - callsign, timestamp, digipeater list
//
// under a "Heard List for Port N" header.
func (nc *conn) mheard(port int) (map[string]bool, error) {
	out, err := nc.command(fmt.Sprintf("MH %d", port))
	if err != nil {
		return nil, err
	}
	if strings.Contains(out, "MHEARD not enabled") {
		return nil, fmt.Errorf("MHEARD is not enabled on this port")
	}
	if strings.Contains(out, "Invalid Port") {
		return nil, errNoSuchPort
	}
	return parseMHeard(out), nil
}

func parseMHeard(out string) map[string]bool {
	calls := map[string]bool{}
	for _, line := range lines(out) {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		// The node prefixes its reply with an "ALIAS:CALL}" prompt, and the
		// list itself carries a header line.
		if strings.Contains(line, "Heard List") {
			continue
		}
		// A digipeated entry carries a trailing '*' on the callsign.
		call := strings.ToUpper(strings.TrimSuffix(fields[0], "*"))
		if validCall(call) {
			calls[call] = true
		}
	}
	return calls
}

// lines splits node output into trimmed lines. The node terminates lines with
// a bare CR, but replies can arrive with CRLF depending on the telnet path, so
// both are normalised here rather than at each call site.
func lines(s string) []string {
	s = clean(s)
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}

// lock sets the quality and turns the locked flag on. The flag is a toggle, so
// this is only ever sent for a route that is not already locked.
func (nc *conn) lock(call string, port, quality int) error {
	_, err := nc.command(fmt.Sprintf("ROUTES %s %d %d !", call, port, quality))
	return err
}

// unlock toggles the locked flag back off, leaving the route in place.
func (nc *conn) unlock(call string, port int) error {
	_, err := nc.command(fmt.Sprintf("ROUTES %s %d !", call, port))
	return err
}

func (nc *conn) saveNodes() error {
	_, err := nc.command("SAVENODES")
	return err
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func portsHearing(heard map[int]map[string]bool, call string) []int {
	var on []int
	for port, calls := range heard {
		if port == telnetPort {
			continue
		}
		if calls[call] {
			on = append(on, port)
		}
	}
	sort.Ints(on)
	return on
}

func find(rs []route, call string, port int) (route, bool) {
	for _, r := range rs {
		if r.Callsign == call && r.Port == port {
			return r, true
		}
	}
	return route{}, false
}

func sortedPorts(m map[string]int) []int {
	seen := map[int]bool{}
	var out []int
	for _, p := range m {
		if !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	sort.Ints(out)
	return out
}

func sortedCalls(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for c := range m {
		out = append(out, c)
	}
	sort.Strings(out)
	return out
}
