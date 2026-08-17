package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// Real output from a live node (WA2M-2 / MIKE), captured before any routes were
// locked. Two RF neighbours at the port's own QUALITY=1 with no lock marker and
// no nodes learned through them, and the tarpn-chat route locked by config.
const realRoutes = "MIKE:WA2M-2} Routes\r" +
	"> 2 N2IRZ-2   1 0\r" +
	"> 3 NF4L-2    1 0\r" +
	"> 32 WA2M-9    200 0!\r"

func TestParseRoutes(t *testing.T) {
	got := parseRoutes(realRoutes)

	want := []route{
		{Port: 2, Callsign: "N2IRZ-2", Quality: 1, Nodes: 0, Locked: false},
		{Port: 3, Callsign: "NF4L-2", Quality: 1, Nodes: 0, Locked: false},
		{Port: 32, Callsign: "WA2M-9", Quality: 200, Nodes: 0, Locked: true},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("parseRoutes:\n got %+v\nwant %+v", got, want)
	}
}

func TestParseRoutesLockMarkers(t *testing.T) {
	// DisplayRoute writes "!" for LOCKEDBYCONFIG, "!!" for LOCKEDBYSYSOP and
	// "!!!" for both. All three mean locked.
	in := "Routes\r" +
		"  1 AAA-1 200 3\r" +
		"> 2 BBB-2 200 3!\r" +
		"> 3 CCC-3 200 3!!\r" +
		"> 4 DDD-4 200 3!!!\r"

	got := parseRoutes(in)
	if len(got) != 4 {
		t.Fatalf("expected 4 routes, got %d (%+v)", len(got), got)
	}
	for i, wantLocked := range []bool{false, true, true, true} {
		if got[i].Locked != wantLocked {
			t.Errorf("route %s: locked = %v, want %v", got[i].Callsign, got[i].Locked, wantLocked)
		}
	}
}

func TestParseMHeard(t *testing.T) {
	// "%-10s %s %s\r" under a "Heard List for Port N" header.
	in := "MIKE:WA2M-2} Heard List for Port 2\r" +
		"N2IRZ-2    17-Aug-2026 08:21:31\r" +
		"N2IRZ-9    17-Aug-2026 08:19:02\r" +
		"K4XYZ-1*   17-Aug-2026 08:02:11 via N2IRZ-2*\r"

	got := parseMHeard(in)
	for _, want := range []string{"N2IRZ-2", "N2IRZ-9", "K4XYZ-1"} {
		if !got[want] {
			t.Errorf("expected %s in heard list, got %v", want, got)
		}
	}
	// The header must not be mistaken for a callsign.
	for _, bad := range []string{"MIKE:WA2M-2}", "HEARD", "LIST"} {
		if got[bad] {
			t.Errorf("header leaked into heard list as %q", bad)
		}
	}
}

func TestParseMHeardEmpty(t *testing.T) {
	got := parseMHeard("MIKE:WA2M-2} Heard List for Port 1\r")
	if len(got) != 0 {
		t.Fatalf("expected nothing heard, got %v", got)
	}
}

func TestCallsignFromPrompt(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"wa2m:", "WA2M"},
		{"\r\nwa2m:", "WA2M"},
		{"Welcome to MIKE\rwa2m:", "WA2M"},
		{"nothing", ""}, // no colon
		{"!!!!:", ""},   // not callsign-shaped
	} {
		if got := callsignFromPrompt(tc.in); got != tc.want {
			t.Errorf("callsignFromPrompt(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestReadNeighbours(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "node.conf")
	conf := `
# comment
NODE_CALL=WA2M-2
PORT_A_NEIGHBOR=N2IRZ-2
PORT_B_NEIGHBOR=NZ2Z-2
PORT_C_NEIGHBOR=NF4L-2
PORT_D_NEIGHBOR=
PORT_11_ENABLED=false
PORT_11_NEIGHBOR=W4ABC-2
PORT_12_ENABLED=true
PORT_12_NEIGHBOR=W4DEF-2
`
	if err := os.WriteFile(path, []byte(conf), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := readNeighbours(path)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]int{
		"N2IRZ-2": 1,
		"NZ2Z-2":  2,
		"NF4L-2":  3,
		"W4DEF-2": 12, // port 11 is disabled, so W4ABC-2 must not appear
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("readNeighbours:\n got %v\nwant %v", got, want)
	}
}

func TestPortsHearingSkipsTelnetPort(t *testing.T) {
	heard := map[int]map[string]bool{
		2:          {"N2IRZ-2": true},
		telnetPort: {"N2IRZ-2": true},
	}
	got := portsHearing(heard, "N2IRZ-2")
	if !reflect.DeepEqual(got, []int{2}) {
		t.Fatalf("portsHearing = %v, want [2]", got)
	}
}
