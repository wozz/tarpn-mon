package main

import (
	"fmt"
	"math/rand"
	"strings"
	"testing"
)

// ============================================================================
// CQ Tests
// ============================================================================

func TestCQRoundTrip(t *testing.T) {
	ps := &PortStats{
		PortNum:         3,
		L2Rxed:          1400,
		L2Sent:          2100,
		L2Timeouts:      30,
		REJRxed:         5,
		RXCRCErrors:     2,
		FramesAbandoned: 0,
		ActiveTxPct:     5,
		ActiveBusyPct:   15,
	}

	encoded := EncodeCQ("WA2M-2", ps)
	t.Logf("Encoded CQ: %s (len=%d)", encoded, len(encoded))

	decoded, err := DecodeCQ(encoded)
	if err != nil {
		t.Fatalf("DecodeCQ failed: %v", err)
	}

	if decoded.Callsign != "WA2M-2" {
		t.Errorf("Callsign: got %q, want %q", decoded.Callsign, "WA2M-2")
	}
	if decoded.PortNum != 3 {
		t.Errorf("PortNum: got %d, want %d", decoded.PortNum, 3)
	}
	if decoded.L2Rxed != 1400 {
		t.Errorf("L2Rxed: got %d, want %d", decoded.L2Rxed, 1400)
	}
	if decoded.L2Sent != 2100 {
		t.Errorf("L2Sent: got %d, want %d", decoded.L2Sent, 2100)
	}
	if decoded.L2Timeouts != 30 {
		t.Errorf("L2Timeouts: got %d, want %d", decoded.L2Timeouts, 30)
	}
	if decoded.REJRxed != 5 {
		t.Errorf("REJRxed: got %d, want %d", decoded.REJRxed, 5)
	}
	if decoded.RXCRCErrors != 2 {
		t.Errorf("RXCRCErrors: got %d, want %d", decoded.RXCRCErrors, 2)
	}
	if decoded.Abandoned != 0 {
		t.Errorf("Abandoned: got %d, want %d", decoded.Abandoned, 0)
	}
	if decoded.ActiveTxPct != 5 {
		t.Errorf("ActiveTxPct: got %d, want %d", decoded.ActiveTxPct, 5)
	}
	if decoded.ActiveBusyPct != 15 {
		t.Errorf("ActiveBusyPct: got %d, want %d", decoded.ActiveBusyPct, 15)
	}
}

func TestCQMaxLength(t *testing.T) {
	// Worst case: 9-char callsign, max counter values
	ps := &PortStats{
		PortNum:         32,
		L2Rxed:          250000,
		L2Sent:          300000,
		L2Timeouts:      5000,
		REJRxed:         1000,
		RXCRCErrors:     200,
		FramesAbandoned: 100,
		ActiveTxPct:     100,
		ActiveBusyPct:   100,
	}

	encoded := EncodeCQ("WA2MMM-15", ps)
	t.Logf("Worst-case CQ: %s (len=%d)", encoded, len(encoded))

	if len(encoded) > 77 {
		t.Errorf("CQ message exceeds 77-byte limit: %d bytes", len(encoded))
	}

	decoded, err := DecodeCQ(encoded)
	if err != nil {
		t.Fatalf("DecodeCQ failed: %v", err)
	}
	if decoded.L2Rxed != 250000 {
		t.Errorf("L2Rxed: got %d, want %d", decoded.L2Rxed, 250000)
	}
}

func TestCQTypicalLength(t *testing.T) {
	ps := &PortStats{
		PortNum:         1,
		L2Rxed:          1400,
		L2Sent:          2100,
		L2Timeouts:      30,
		REJRxed:         5,
		RXCRCErrors:     2,
		FramesAbandoned: 0,
		ActiveTxPct:     5,
		ActiveBusyPct:   15,
	}

	encoded := EncodeCQ("WA2M-2", ps)
	t.Logf("Typical CQ: %s (len=%d)", encoded, len(encoded))
	t.Logf("Headroom: %d bytes remaining", 77-len(encoded))
}

func TestCQDecodeErrors(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{"no prefix", "~CALL~1~1,2,3,4,5,6,7,8~"},
		{"too few parts", "[LS1]~CALL~"},
		{"bad port", "[LS1]~CALL~abc~1,2,3,4,5,6,7,8~"},
		{"too few values", "[LS1]~CALL~1~1,2,3~"},
		{"bad value", "[LS1]~CALL~1~abc,2,3,4,5,6,7,8~"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := DecodeCQ(tt.input)
			if err == nil {
				t.Error("expected error, got nil")
			}
		})
	}
}

// ============================================================================
// Bit-packing Tests
// ============================================================================

func TestBitsNeeded(t *testing.T) {
	tests := []struct {
		input uint16
		want  byte
	}{
		{0, 0}, {1, 1}, {2, 2}, {3, 2}, {4, 3}, {7, 3}, {8, 4},
		{15, 4}, {16, 5}, {255, 8}, {256, 9}, {500, 9}, {1023, 10}, {65535, 16},
	}

	for _, tt := range tests {
		got := bitsNeeded(tt.input)
		if got != tt.want {
			t.Errorf("bitsNeeded(%d) = %d, want %d", tt.input, got, tt.want)
		}
	}
}

func TestPackUnpackBitsRoundTrip(t *testing.T) {
	tests := []struct {
		name   string
		values []uint16
		bw     byte
	}{
		{"1-bit", []uint16{0, 1, 1, 0, 1, 0, 0, 1}, 1},
		{"4-bit", []uint16{0, 5, 15, 3, 8, 12, 0, 7}, 4},
		{"8-bit", []uint16{0, 128, 255, 1, 200, 50}, 8},
		{"9-bit", []uint16{0, 256, 500, 100, 300, 450}, 9},
		{"10-bit", []uint16{0, 512, 1023, 100, 800, 999}, 10},
		{"16-bit", []uint16{0, 32768, 65535, 1, 50000}, 16},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			packed := packBits(tt.values, tt.bw)
			unpacked := unpackBits(packed, tt.bw, len(tt.values))
			for i, v := range tt.values {
				if unpacked[i] != v {
					t.Errorf("value[%d]: got %d, want %d", i, unpacked[i], v)
				}
			}
		})
	}
}

func TestPackBitsLargeRoundTrip(t *testing.T) {
	// Test with 1440 values (1-min intervals over 24h)
	rng := rand.New(rand.NewSource(42))
	values := make([]uint16, 1440)
	for i := range values {
		values[i] = uint16(rng.Intn(500))
	}

	bw := bitsNeeded(500)
	packed := packBits(values, bw)
	unpacked := unpackBits(packed, bw, len(values))

	for i, v := range values {
		if unpacked[i] != v {
			t.Errorf("value[%d]: got %d, want %d", i, unpacked[i], v)
		}
	}

	t.Logf("1440 values, max=500, %d bits/val, packed=%d bytes (vs %d bytes uint16)",
		bw, len(packed), len(values)*2)
}

// ============================================================================
// Bulletin Round-Trip Tests
// ============================================================================

func TestBulletinColumnBinaryRoundTrip(t *testing.T) {
	sys, ports := generateSyntheticBulletin(4, 24, "medium", 42)

	bin, err := encodeColumnBinary(sys, ports, 60)
	if err != nil {
		t.Fatalf("encodeColumnBinary failed: %v", err)
	}

	decoded, err := decodeColumnBinary(bin)
	if err != nil {
		t.Fatalf("decodeColumnBinary failed: %v", err)
	}

	verifyBulletinRoundTrip(t, sys, ports, 60, decoded)
}

func TestBulletinFullRoundTrip(t *testing.T) {
	// Test through EncodeBulletin → DecodeBulletin (full dynamic selection path)
	sys, ports := generateSyntheticBulletin(4, 24, "medium", 42)

	encoded := EncodeBulletin(sys, ports, 60)
	t.Logf("Full bulletin encoded: %d bytes, tag=%c", len(encoded), encoded[5])

	decoded, err := DecodeBulletin(encoded)
	if err != nil {
		t.Fatalf("DecodeBulletin failed: %v", err)
	}

	verifyBulletinRoundTrip(t, sys, ports, 60, decoded)
}

func TestBulletinBothEncodingsRoundTrip(t *testing.T) {
	// Verify each encoding individually through encode → decode
	sys, ports := generateSyntheticBulletin(3, 24, "high", 123)

	encodings := []struct {
		tag  byte
		name string
	}{
		{'C', "ColBin+A85"},
		{'Z', "ColBrotli+A85"},
	}

	for _, enc := range encodings {
		t.Run(enc.name, func(t *testing.T) {
			colBin, _ := encodeColumnBinary(sys, ports, 60)

			var payload string
			switch enc.tag {
			case 'C':
				payload = encodeAscii85(colBin)
			case 'Z':
				compressed, _ := brotliCompress(colBin)
				payload = encodeAscii85(compressed)
			}

			full := fmt.Sprintf("%s%c%s", bulletinPrefix, enc.tag, payload)
			decoded, err := DecodeBulletin(full)
			if err != nil {
				t.Fatalf("DecodeBulletin(%s) failed: %v", enc.name, err)
			}
			verifyBulletinRoundTrip(t, sys, ports, 60, decoded)
		})
	}
}

func TestBulletinIdleRoundTrip(t *testing.T) {
	sys, ports := generateSyntheticBulletin(4, 24, "idle", 0)

	encoded := EncodeBulletin(sys, ports, 60)
	t.Logf("Idle bulletin: %d bytes, tag=%c", len(encoded), encoded[5])

	decoded, err := DecodeBulletin(encoded)
	if err != nil {
		t.Fatalf("DecodeBulletin failed: %v", err)
	}

	verifyBulletinRoundTrip(t, sys, ports, 60, decoded)
}

func TestBulletinLargeIntervalCount(t *testing.T) {
	// Test 1-min intervals over 24h = 1440 intervals (exceeds uint8)
	sys, ports := generateSyntheticBulletinIntervals(4, 1440, "medium", 1, 42)

	encoded := EncodeBulletin(sys, ports, 1)
	t.Logf("1-min/24h bulletin: %d bytes, tag=%c, frames=%d",
		len(encoded), encoded[5], (len(encoded)+235)/236)

	decoded, err := DecodeBulletin(encoded)
	if err != nil {
		t.Fatalf("DecodeBulletin failed: %v", err)
	}

	verifyBulletinRoundTrip(t, sys, ports, 1, decoded)
}

func TestBulletinAutoSelect(t *testing.T) {
	// For small data, C should win; for large data, Z should win
	tests := []struct {
		name         string
		ports        int
		intervals    int
		traffic      string
		intervalMins int
	}{
		{"small-idle", 4, 24, "idle", 60},
		{"small-med", 4, 24, "medium", 60},
		{"large-med", 4, 1440, "medium", 1},
		{"large-high", 7, 288, "high", 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sys, ports := generateSyntheticBulletinIntervals(tt.ports, tt.intervals, tt.traffic, tt.intervalMins, 42)

			encoded := EncodeBulletin(sys, ports, tt.intervalMins)
			tag := encoded[5]
			t.Logf("%s: tag=%c, size=%d bytes, frames=%d",
				tt.name, tag, len(encoded), (len(encoded)+235)/236)

			// Verify round-trip regardless of which tag was selected
			decoded, err := DecodeBulletin(encoded)
			if err != nil {
				t.Fatalf("DecodeBulletin failed: %v", err)
			}
			verifyBulletinRoundTrip(t, sys, ports, tt.intervalMins, decoded)
		})
	}
}

// ============================================================================
// SafeDelta Tests
// ============================================================================

func TestSafeDelta(t *testing.T) {
	tests := []struct {
		first, last int64
		want        int64
	}{
		{0, 100, 100},
		{100, 200, 100},
		{1000, 1500, 500},
		{1000, 50, 50},    // rebooted, 50 is delta since reset
		{50000, 0, 0},     // rebooted, no traffic since
		{50000, 100, 100}, // rebooted, 100 since reset
	}

	for _, tt := range tests {
		got := safeDelta(tt.first, tt.last)
		if got != tt.want {
			t.Errorf("safeDelta(%d, %d) = %d, want %d", tt.first, tt.last, got, tt.want)
		}
	}
}

// ============================================================================
// Encoding Size Benchmark
// ============================================================================

func TestEncodingSizeComparison(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping size comparison in short mode")
	}

	type scenario struct {
		name         string
		ports        int
		intervals    int
		traffic      string
		intervalMins int
	}

	scenarios := []scenario{
		{"4p-hourly-idle", 4, 24, "idle", 60},
		{"4p-hourly-med", 4, 24, "medium", 60},
		{"4p-hourly-high", 4, 24, "high", 60},
		{"4p-5min-med", 4, 288, "medium", 5},
		{"4p-5min-high", 4, 288, "high", 5},
		{"7p-hourly-med", 7, 24, "medium", 60},
		{"7p-5min-med", 7, 288, "medium", 5},
		{"4p-1min-med", 4, 1440, "medium", 1},
	}

	fmt.Println()
	fmt.Println("=== Final Encoding Sizes (ColBin+A85 vs ColBrotli+A85) ===")
	fmt.Printf("%-18s | %8s %10s %12s | %4s %6s\n",
		"Scenario", "ColRaw", "ColBin+A85", "ColBrot+A85", "Tag", "Frames")
	fmt.Println(strings.Repeat("-", 72))

	for _, s := range scenarios {
		sys, ports := generateSyntheticBulletinIntervals(s.ports, s.intervals, s.traffic, s.intervalMins, 42)

		colBin, _ := encodeColumnBinary(sys, ports, s.intervalMins)
		colA85 := len(bulletinPrefix) + 1 + len(encodeAscii85(colBin))

		brotComp, _ := brotliCompress(colBin)
		brotA85 := len(bulletinPrefix) + 1 + len(encodeAscii85(brotComp))

		// What EncodeBulletin would pick
		encoded := EncodeBulletin(sys, ports, s.intervalMins)
		tag := encoded[5]
		frames := (len(encoded) + 235) / 236

		fmt.Printf("%-18s | %8d %10d %12d | %4c %6d\n",
			s.name, len(colBin), colA85, brotA85, tag, frames)
	}
	fmt.Println()
}

// ============================================================================
// Synthetic Data Generators
// ============================================================================

func generateSyntheticBulletin(numPorts, numHours int, traffic string, seed int64) (BulletinSystemStats, map[int][]BulletinInterval) {
	return generateSyntheticBulletinIntervals(numPorts, numHours, traffic, 60, seed)
}

func generateSyntheticBulletinIntervals(numPorts, numIntervals int, traffic string, intervalMins int, seed int64) (BulletinSystemStats, map[int][]BulletinInterval) {
	rng := rand.New(rand.NewSource(seed))

	sys := BulletinSystemStats{
		UptimeMins: 1440,
		BuffersCur: 998,
		KnownNodes: 6,
		L4FramesTx: 500,
		L4FramesRx: 480,
		L4Resent:   10,
		L3Relayed:  200,
	}

	portNumbers := []int{1, 2, 3, 32}
	if numPorts > 4 {
		portNumbers = append(portNumbers, 4, 5, 6, 7)
	}
	portNumbers = portNumbers[:numPorts]

	ports := make(map[int][]BulletinInterval)

	for _, pn := range portNumbers {
		intervals := make([]BulletinInterval, numIntervals)
		scale := float64(intervalMins) / 60.0

		for i := range intervals {
			switch traffic {
			case "idle":
				// All zeros
			case "low":
				intervals[i] = BulletinInterval{
					DeltaRxed:     uint16(float64(rng.Intn(50)) * scale),
					DeltaSent:     uint16(float64(rng.Intn(50)) * scale),
					DeltaTimeouts: uint16(float64(rng.Intn(3)) * scale),
				}
			case "medium":
				intervals[i] = BulletinInterval{
					DeltaRxed:      uint16(float64(50+rng.Intn(450)) * scale),
					DeltaSent:      uint16(float64(50+rng.Intn(450)) * scale),
					DeltaTimeouts:  uint16(float64(5+rng.Intn(15)) * scale),
					DeltaRej:       uint8(float64(rng.Intn(6)) * scale),
					DeltaCRC:       uint8(float64(rng.Intn(3)) * scale),
					DeltaAbandoned: uint8(float64(rng.Intn(2)) * scale),
					AvgTxPct:       uint8(3 + rng.Intn(15)),
					AvgBusyPct:     uint8(5 + rng.Intn(25)),
				}
			case "high":
				intervals[i] = BulletinInterval{
					DeltaRxed:      uint16(float64(500+rng.Intn(4500)) * scale),
					DeltaSent:      uint16(float64(500+rng.Intn(4500)) * scale),
					DeltaTimeouts:  uint16(float64(20+rng.Intn(80)) * scale),
					DeltaRej:       uint8(float64(5+rng.Intn(45)) * scale),
					DeltaCRC:       uint8(float64(2+rng.Intn(18)) * scale),
					DeltaAbandoned: uint8(float64(rng.Intn(10)) * scale),
					AvgTxPct:       uint8(10 + rng.Intn(40)),
					AvgBusyPct:     uint8(20 + rng.Intn(50)),
				}
			}
		}
		ports[pn] = intervals
	}

	return sys, ports
}

func verifyBulletinRoundTrip(t *testing.T, origSys BulletinSystemStats, origPorts map[int][]BulletinInterval, intervalMins int, decoded *BulletinData) {
	t.Helper()

	if decoded.IntervalMins != intervalMins {
		t.Errorf("IntervalMins: got %d, want %d", decoded.IntervalMins, intervalMins)
	}

	if decoded.System != origSys {
		t.Errorf("System stats mismatch:\n  got:  %+v\n  want: %+v", decoded.System, origSys)
	}

	if len(decoded.Ports) != len(origPorts) {
		t.Fatalf("Port count: got %d, want %d", len(decoded.Ports), len(origPorts))
	}

	for pn, origIntervals := range origPorts {
		decIntervals, ok := decoded.Ports[pn]
		if !ok {
			t.Errorf("Port %d missing from decoded", pn)
			continue
		}
		if len(decIntervals) != len(origIntervals) {
			t.Errorf("Port %d: got %d intervals, want %d", pn, len(decIntervals), len(origIntervals))
			continue
		}
		for i, orig := range origIntervals {
			dec := decIntervals[i]
			if dec != orig {
				t.Errorf("Port %d interval %d: got %+v, want %+v", pn, i, dec, orig)
			}
		}
	}
}
