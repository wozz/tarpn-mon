package main

import (
	"fmt"
	"testing"
)

// Test data representing the old format (newline-separated, single !)
const oldFormatResponse = `FFVC:KA2DEW-3} Routes
> 1 AI4WV-2   200  20! 893  110  12% 0 0 19:33  1 200
> 2 KK4VBE-2  200  14! 876   21   2% 0 0 19:31  1 200
> 3 KV7D-2    200   4! 468   46   9% 0 0 19:41  1 200
> 4 KM4DLS-2    1  15  724  123  16% 0 0 19:33  18 156
`

// Test data representing the new format (with !! for double-locked, no space after > sometimes)
const newFormatResponse = `MIKE:WA2M-2} Routes
2 N2IRZ-2   200   0!!   0    0      0 0 00:00  0 0
> 3 NF4L-2    200   3!!  11    2  18% 0 0 15:03  0 200
> 1 NZ2Z-2    200   2!!   9    2  22% 0 0 00:00  0 0
>32 WA2M-9    200   1!   0    0      0 0 00:00  0 0 41430
`

func TestParseOldFormat(t *testing.T) {
	myCallsign, routes, err := parseRoutesTable(oldFormatResponse)
	if err != nil {
		t.Fatalf("Failed to parse old format: %v", err)
	}

	if myCallsign != "KA2DEW-3" {
		t.Errorf("Expected callsign KA2DEW-3, got %s", myCallsign)
	}

	if len(routes) != 4 {
		t.Errorf("Expected 4 routes, got %d", len(routes))
	}

	// Check first route
	if len(routes) > 0 {
		r := routes[0]
		if r.PortNumber != 1 {
			t.Errorf("Route 0: expected port 1, got %d", r.PortNumber)
		}
		if r.Callsign != "AI4WV-2" {
			t.Errorf("Route 0: expected callsign AI4WV-2, got %s", r.Callsign)
		}
		if !r.ChevronSet {
			t.Error("Route 0: expected chevron to be set")
		}
		if r.LockedRoutes != 1 {
			t.Errorf("Route 0: expected 1 locked route, got %d", r.LockedRoutes)
		}
		if r.Quality != 200 {
			t.Errorf("Route 0: expected quality 200, got %d", r.Quality)
		}
		if r.NumberOfNodes != 20 {
			t.Errorf("Route 0: expected 20 nodes, got %d", r.NumberOfNodes)
		}
		if r.InfoFramesSent != 893 {
			t.Errorf("Route 0: expected 893 info frames, got %d", r.InfoFramesSent)
		}
		if r.PercentRetries != 12 {
			t.Errorf("Route 0: expected 12%% retries, got %d", r.PercentRetries)
		}
	}

	// Check route 4 (has chevron, but quality=1 so QualityIsReal should be false)
	if len(routes) > 3 {
		r := routes[3]
		if r.PortNumber != 4 {
			t.Errorf("Route 3: expected port 4, got %d", r.PortNumber)
		}
		if !r.ChevronSet {
			t.Error("Route 3: expected chevron to be set")
		}
		if r.Quality != 1 {
			t.Errorf("Route 3: expected quality 1, got %d", r.Quality)
		}
		if r.QualityIsReal {
			t.Error("Route 3: expected QualityIsReal to be false for quality=1")
		}
		if r.LockedRoutes != 0 {
			t.Errorf("Route 3: expected 0 locked routes (no !), got %d", r.LockedRoutes)
		}
	}
}

func TestParseNewFormat(t *testing.T) {
	myCallsign, routes, err := parseRoutesTable(newFormatResponse)
	if err != nil {
		t.Fatalf("Failed to parse new format: %v", err)
	}

	if myCallsign != "WA2M-2" {
		t.Errorf("Expected callsign WA2M-2, got %s", myCallsign)
	}

	fmt.Printf("Parsed %d routes from new format\n", len(routes))
	for i, r := range routes {
		fmt.Printf("Route %d: port=%d callsign=%s quality=%d locked=%d chevron=%v\n",
			i, r.PortNumber, r.Callsign, r.Quality, r.LockedRoutes, r.ChevronSet)
	}

	// We expect 4 routes
	if len(routes) != 4 {
		t.Errorf("Expected 4 routes, got %d", len(routes))
	}

	// Check first route (no chevron, double locked)
	if len(routes) > 0 {
		r := routes[0]
		if r.PortNumber != 2 {
			t.Errorf("Route 0: expected port 2, got %d", r.PortNumber)
		}
		if r.Callsign != "N2IRZ-2" {
			t.Errorf("Route 0: expected callsign N2IRZ-2, got %s", r.Callsign)
		}
		if r.ChevronSet {
			t.Error("Route 0: expected chevron NOT to be set")
		}
		if r.LockedRoutes != 2 {
			t.Errorf("Route 0: expected 2 locked routes (!!), got %d", r.LockedRoutes)
		}
	}

	// Check that port 32 route exists (no space after >)
	foundPort32 := false
	for _, r := range routes {
		if r.PortNumber == 32 {
			foundPort32 = true
			if r.Callsign != "WA2M-9" {
				t.Errorf("Port 32 route: expected callsign WA2M-9, got %s", r.Callsign)
			}
			if !r.ChevronSet {
				t.Error("Port 32 route: expected chevron to be set")
			}
			if r.LockedRoutes != 1 {
				t.Errorf("Port 32 route: expected 1 locked route (!), got %d", r.LockedRoutes)
			}
			break
		}
	}
	if !foundPort32 {
		t.Error("Expected to find route for port 32")
	}

	// Check NF4L-2 route (has percent value)
	for _, r := range routes {
		if r.Callsign == "NF4L-2" {
			if r.PercentRetries != 18 {
				t.Errorf("NF4L-2 route: expected 18%% retries, got %d", r.PercentRetries)
			}
			if r.InfoFramesSent != 11 {
				t.Errorf("NF4L-2 route: expected 11 info frames, got %d", r.InfoFramesSent)
			}
			break
		}
	}
}

// Test data where nodes count and info frames run together with no space (e.g., "7!!1549")
const noSpaceAfterBangsResponse = `MIKE:WA2M-2} Routes
> 2 N2IRZ-2   200   7!!1549   39   2% 0 0 19:10  0 200
3 NF4L-2    200   6!!2014  561  27% 0 0 19:04  0 200
> 1 NZ2Z-2    200   7!!1433  125   8% 0 0 19:13  0 156
>32 WA2M-9    200   1!   0    0      0 0 00:00  0 0 47310
`

func TestParseNoSpaceAfterBangs(t *testing.T) {
	myCallsign, routes, err := parseRoutesTable(noSpaceAfterBangsResponse)
	if err != nil {
		t.Fatalf("Failed to parse: %v", err)
	}

	if myCallsign != "WA2M-2" {
		t.Errorf("Expected callsign WA2M-2, got %s", myCallsign)
	}

	if len(routes) != 4 {
		t.Fatalf("Expected 4 routes, got %d", len(routes))
	}

	// Check N2IRZ-2: "7!!1549" - nodes=7, infoframes=1549
	r := routes[0]
	if r.PortNumber != 2 {
		t.Errorf("Route 0: expected port 2, got %d", r.PortNumber)
	}
	if r.Callsign != "N2IRZ-2" {
		t.Errorf("Route 0: expected callsign N2IRZ-2, got %s", r.Callsign)
	}
	if !r.ChevronSet {
		t.Error("Route 0: expected chevron to be set")
	}
	if r.LockedRoutes != 2 {
		t.Errorf("Route 0: expected 2 locked routes, got %d", r.LockedRoutes)
	}
	if r.NumberOfNodes != 7 {
		t.Errorf("Route 0: expected 7 nodes, got %d", r.NumberOfNodes)
	}
	if r.InfoFramesSent != 1549 {
		t.Errorf("Route 0: expected 1549 info frames, got %d", r.InfoFramesSent)
	}
	if r.RetriesSent != 39 {
		t.Errorf("Route 0: expected 39 retries, got %d", r.RetriesSent)
	}
	if r.PercentRetries != 2 {
		t.Errorf("Route 0: expected 2%% retries, got %d", r.PercentRetries)
	}

	// Check NF4L-2: "6!!2014" - no chevron, nodes=6, infoframes=2014
	r = routes[1]
	if r.Callsign != "NF4L-2" {
		t.Errorf("Route 1: expected callsign NF4L-2, got %s", r.Callsign)
	}
	if r.ChevronSet {
		t.Error("Route 1: expected chevron NOT to be set")
	}
	if r.NumberOfNodes != 6 {
		t.Errorf("Route 1: expected 6 nodes, got %d", r.NumberOfNodes)
	}
	if r.InfoFramesSent != 2014 {
		t.Errorf("Route 1: expected 2014 info frames, got %d", r.InfoFramesSent)
	}
	if r.PercentRetries != 27 {
		t.Errorf("Route 1: expected 27%% retries, got %d", r.PercentRetries)
	}

	// Check NZ2Z-2: "7!!1433" - nodes=7, infoframes=1433
	r = routes[2]
	if r.NumberOfNodes != 7 {
		t.Errorf("Route 2: expected 7 nodes, got %d", r.NumberOfNodes)
	}
	if r.InfoFramesSent != 1433 {
		t.Errorf("Route 2: expected 1433 info frames, got %d", r.InfoFramesSent)
	}
	if r.BuffersToSend != 0 {
		t.Errorf("Route 2: expected 0 buffers, got %d", r.BuffersToSend)
	}
	if r.MysteryFigure3 != 156 {
		t.Errorf("Route 2: expected mystery3=156, got %d", r.MysteryFigure3)
	}
}

func TestExtractCallsign(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"\nKA2DEW-3:", "KA2DEW-3"},
		{"K1ABC:", "K1ABC"},
		{"N2IRZ-2:", "N2IRZ-2"},
		{"\r\n  W1AW:  ", "W1AW"},
	}

	for _, tt := range tests {
		result := extractCallsign(tt.input)
		if result != tt.expected {
			t.Errorf("extractCallsign(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}

func TestLockedRoutesCount(t *testing.T) {
	// Test single !
	line1 := "> 1 AI4WV-2   200  20! 893  110  12% 0 0 19:33  1 200"
	route1, ok := parseRouteLine(line1)
	if !ok {
		t.Fatal("Failed to parse line with single !")
	}
	if route1.LockedRoutes != 1 {
		t.Errorf("Expected 1 locked route for single !, got %d", route1.LockedRoutes)
	}

	// Test double !!
	line2 := "> 3 NF4L-2    200   3!!  11    2  18% 0 0 15:03  0 200"
	route2, ok := parseRouteLine(line2)
	if !ok {
		t.Fatal("Failed to parse line with double !!")
	}
	if route2.LockedRoutes != 2 {
		t.Errorf("Expected 2 locked routes for double !!, got %d", route2.LockedRoutes)
	}

	// Test no ! (unlocked route)
	line3 := "> 4 KM4DLS-2    1  15  724  123  16% 0 0 19:33  18 156"
	route3, ok := parseRouteLine(line3)
	if !ok {
		t.Fatal("Failed to parse line with no !")
	}
	if route3.LockedRoutes != 0 {
		t.Errorf("Expected 0 locked routes for no !, got %d", route3.LockedRoutes)
	}

	// Test no space after chevron (e.g., ">32" instead of "> 32")
	line4 := ">32 WA2M-9    200   1!   0    0      0 0 00:00  0 0 41430"
	route4, ok := parseRouteLine(line4)
	if !ok {
		t.Fatal("Failed to parse line with no space after chevron")
	}
	if route4.PortNumber != 32 {
		t.Errorf("Expected port 32, got %d", route4.PortNumber)
	}
	if !route4.ChevronSet {
		t.Error("Expected chevron to be set")
	}
	if route4.LockedRoutes != 1 {
		t.Errorf("Expected 1 locked route, got %d", route4.LockedRoutes)
	}

	// Test line without chevron
	line5 := "2 N2IRZ-2   200   0!!   0    0      0 0 00:00  0 0"
	route5, ok := parseRouteLine(line5)
	if !ok {
		t.Fatal("Failed to parse line without chevron")
	}
	if route5.ChevronSet {
		t.Error("Expected chevron NOT to be set")
	}
	if route5.LockedRoutes != 2 {
		t.Errorf("Expected 2 locked routes, got %d", route5.LockedRoutes)
	}
}
