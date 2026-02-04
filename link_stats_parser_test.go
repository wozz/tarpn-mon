package main

import (
	"strings"
	"testing"
)

// Real output from the user's LinBPQ node (WA2M-2)
const sampleSOutput = `MIKE:WA2M-2}
Uptime (Days Hours Mins)     00:00:13
Semaphore Get-Rel/Clashes           1      262
Buffers:Max/Cur/Min/Out/Wait      999      998      936        0        0
Known Nodes/Max Nodes               6      100
L4 Connects Sent/Rxed               0        0
L4 Frames TX/RX/Resent/Reseq        0        0        0        0
L3 Frames Relayed                   1
Port 01  Port 02  Port 03  Port 32
L2 Frames Digied        0        0        0        0
L2 Frames Heard        30       21       32        0
L2 Frames Rxed         14        0       10      149
L2 Frames Sent         21        6       17      294
L2 Timeouts             0        0        3        0
REJ Frames Rxed         0        0        0        0
RX out of Seq           0        0        0        0
L2 Resequenced          0        0        0        0
Undrun/Poll T/o         0        0        0        0
RX Overruns             0        0        0        0
RX CRC Errors           0        0        0        0
FRMRs Sent              0        0        0        0
FRMRs Received          0        0        0        0
Frames abandoned        0        0        0        0
Active(TX/Busy) %   0   0    0   0    0   0    0   0`

func TestParseRealSOutput(t *testing.T) {
	lines := strings.Split(sampleSOutput, "\n")
	snap, err := ParseSCommandOutput(lines)
	if err != nil {
		t.Fatalf("ParseSCommandOutput failed: %v", err)
	}

	// System stats
	sys := snap.System
	if sys.UptimeDays != 0 || sys.UptimeHours != 0 || sys.UptimeMins != 13 {
		t.Errorf("uptime: got %d:%d:%d, want 0:0:13", sys.UptimeDays, sys.UptimeHours, sys.UptimeMins)
	}
	if sys.SemGets != 1 {
		t.Errorf("SemGets: got %d, want 1", sys.SemGets)
	}
	if sys.SemClashes != 262 {
		t.Errorf("SemClashes: got %d, want 262", sys.SemClashes)
	}
	if sys.BuffersMax != 999 {
		t.Errorf("BuffersMax: got %d, want 999", sys.BuffersMax)
	}
	if sys.BuffersCur != 998 {
		t.Errorf("BuffersCur: got %d, want 998", sys.BuffersCur)
	}
	if sys.BuffersMin != 936 {
		t.Errorf("BuffersMin: got %d, want 936", sys.BuffersMin)
	}
	if sys.BuffersOut != 0 {
		t.Errorf("BuffersOut: got %d, want 0", sys.BuffersOut)
	}
	if sys.BuffersWait != 0 {
		t.Errorf("BuffersWait: got %d, want 0", sys.BuffersWait)
	}
	if sys.KnownNodes != 6 {
		t.Errorf("KnownNodes: got %d, want 6", sys.KnownNodes)
	}
	if sys.MaxNodes != 100 {
		t.Errorf("MaxNodes: got %d, want 100", sys.MaxNodes)
	}
	if sys.L4ConnSent != 0 || sys.L4ConnRxed != 0 {
		t.Errorf("L4Conn: got %d/%d, want 0/0", sys.L4ConnSent, sys.L4ConnRxed)
	}
	if sys.L4FramesTx != 0 || sys.L4FramesRx != 0 || sys.L4Resent != 0 || sys.L4Reseq != 0 {
		t.Errorf("L4Frames: got %d/%d/%d/%d, want 0/0/0/0",
			sys.L4FramesTx, sys.L4FramesRx, sys.L4Resent, sys.L4Reseq)
	}
	if sys.L3Relayed != 1 {
		t.Errorf("L3Relayed: got %d, want 1", sys.L3Relayed)
	}

	// Port stats
	if len(snap.Ports) != 4 {
		t.Fatalf("expected 4 ports, got %d", len(snap.Ports))
	}

	// Port 1
	p1 := snap.Ports[1]
	if p1 == nil {
		t.Fatal("port 1 missing")
	}
	if p1.L2Heard != 30 {
		t.Errorf("port 1 L2Heard: got %d, want 30", p1.L2Heard)
	}
	if p1.L2Rxed != 14 {
		t.Errorf("port 1 L2Rxed: got %d, want 14", p1.L2Rxed)
	}
	if p1.L2Sent != 21 {
		t.Errorf("port 1 L2Sent: got %d, want 21", p1.L2Sent)
	}

	// Port 2
	p2 := snap.Ports[2]
	if p2 == nil {
		t.Fatal("port 2 missing")
	}
	if p2.L2Heard != 21 {
		t.Errorf("port 2 L2Heard: got %d, want 21", p2.L2Heard)
	}
	if p2.L2Sent != 6 {
		t.Errorf("port 2 L2Sent: got %d, want 6", p2.L2Sent)
	}

	// Port 3
	p3 := snap.Ports[3]
	if p3 == nil {
		t.Fatal("port 3 missing")
	}
	if p3.L2Heard != 32 {
		t.Errorf("port 3 L2Heard: got %d, want 32", p3.L2Heard)
	}
	if p3.L2Rxed != 10 {
		t.Errorf("port 3 L2Rxed: got %d, want 10", p3.L2Rxed)
	}
	if p3.L2Sent != 17 {
		t.Errorf("port 3 L2Sent: got %d, want 17", p3.L2Sent)
	}
	if p3.L2Timeouts != 3 {
		t.Errorf("port 3 L2Timeouts: got %d, want 3", p3.L2Timeouts)
	}

	// Port 32 (NetROM virtual)
	p32 := snap.Ports[32]
	if p32 == nil {
		t.Fatal("port 32 missing")
	}
	if p32.L2Rxed != 149 {
		t.Errorf("port 32 L2Rxed: got %d, want 149", p32.L2Rxed)
	}
	if p32.L2Sent != 294 {
		t.Errorf("port 32 L2Sent: got %d, want 294", p32.L2Sent)
	}
}

func TestParseActivePercentages(t *testing.T) {
	// Test with non-zero activity percentages
	output := `Uptime (Days Hours Mins)     01:02:30
Buffers:Max/Cur/Min/Out/Wait      999      500      100        5        2
Known Nodes/Max Nodes              15      100
L4 Connects Sent/Rxed              10       20
L4 Frames TX/RX/Resent/Reseq     100      200       30       40
L3 Frames Relayed                 500
Port 01  Port 02
L2 Frames Digied        5        3
L2 Frames Heard      1000      800
L2 Frames Rxed        500      400
L2 Frames Sent        600      350
L2 Timeouts            20       10
REJ Frames Rxed         5        2
RX out of Seq           1        0
L2 Resequenced          0        0
Undrun/Poll T/o         0        0
RX Overruns             0        0
RX CRC Errors           3        1
FRMRs Sent              0        0
FRMRs Received          0        0
Frames abandoned        2        0
Active(TX/Busy) %   5  15    3  10`

	lines := strings.Split(output, "\n")
	snap, err := ParseSCommandOutput(lines)
	if err != nil {
		t.Fatalf("ParseSCommandOutput failed: %v", err)
	}

	// System stats
	if snap.System.UptimeDays != 1 || snap.System.UptimeHours != 2 || snap.System.UptimeMins != 30 {
		t.Errorf("uptime: got %d:%d:%d, want 1:2:30",
			snap.System.UptimeDays, snap.System.UptimeHours, snap.System.UptimeMins)
	}
	if snap.System.BuffersCur != 500 {
		t.Errorf("BuffersCur: got %d, want 500", snap.System.BuffersCur)
	}
	if snap.System.L3Relayed != 500 {
		t.Errorf("L3Relayed: got %d, want 500", snap.System.L3Relayed)
	}
	if snap.System.L4FramesTx != 100 {
		t.Errorf("L4FramesTx: got %d, want 100", snap.System.L4FramesTx)
	}

	// Port stats
	if len(snap.Ports) != 2 {
		t.Fatalf("expected 2 ports, got %d", len(snap.Ports))
	}

	p1 := snap.Ports[1]
	if p1.L2Heard != 1000 {
		t.Errorf("port 1 L2Heard: got %d, want 1000", p1.L2Heard)
	}
	if p1.L2Sent != 600 {
		t.Errorf("port 1 L2Sent: got %d, want 600", p1.L2Sent)
	}
	if p1.L2Timeouts != 20 {
		t.Errorf("port 1 L2Timeouts: got %d, want 20", p1.L2Timeouts)
	}
	if p1.RXCRCErrors != 3 {
		t.Errorf("port 1 RXCRCErrors: got %d, want 3", p1.RXCRCErrors)
	}
	if p1.FramesAbandoned != 2 {
		t.Errorf("port 1 FramesAbandoned: got %d, want 2", p1.FramesAbandoned)
	}
	if p1.ActiveTxPct != 5 {
		t.Errorf("port 1 ActiveTxPct: got %d, want 5", p1.ActiveTxPct)
	}
	if p1.ActiveBusyPct != 15 {
		t.Errorf("port 1 ActiveBusyPct: got %d, want 15", p1.ActiveBusyPct)
	}

	p2 := snap.Ports[2]
	if p2.L2Sent != 350 {
		t.Errorf("port 2 L2Sent: got %d, want 350", p2.L2Sent)
	}
	if p2.ActiveTxPct != 3 {
		t.Errorf("port 2 ActiveTxPct: got %d, want 3", p2.ActiveTxPct)
	}
	if p2.ActiveBusyPct != 10 {
		t.Errorf("port 2 ActiveBusyPct: got %d, want 10", p2.ActiveBusyPct)
	}
}

func TestParseSinglePort(t *testing.T) {
	output := `Uptime (Days Hours Mins)     00:01:00
Buffers:Max/Cur/Min/Out/Wait      100       90       80        0        0
Known Nodes/Max Nodes               1       50
L4 Connects Sent/Rxed               0        0
L4 Frames TX/RX/Resent/Reseq        0        0        0        0
L3 Frames Relayed                   0
Port 03
L2 Frames Digied        0
L2 Frames Heard       100
L2 Frames Rxed         50
L2 Frames Sent         60
L2 Timeouts             5
REJ Frames Rxed         1
RX out of Seq           0
L2 Resequenced          0
Undrun/Poll T/o         0
RX Overruns             0
RX CRC Errors           2
FRMRs Sent              0
FRMRs Received          0
Frames abandoned        0
Active(TX/Busy) %   2   8`

	lines := strings.Split(output, "\n")
	snap, err := ParseSCommandOutput(lines)
	if err != nil {
		t.Fatalf("ParseSCommandOutput failed: %v", err)
	}

	if len(snap.Ports) != 1 {
		t.Fatalf("expected 1 port, got %d", len(snap.Ports))
	}

	p3 := snap.Ports[3]
	if p3 == nil {
		t.Fatal("port 3 missing")
	}
	if p3.L2Heard != 100 {
		t.Errorf("L2Heard: got %d, want 100", p3.L2Heard)
	}
	if p3.L2Rxed != 50 {
		t.Errorf("L2Rxed: got %d, want 50", p3.L2Rxed)
	}
	if p3.L2Sent != 60 {
		t.Errorf("L2Sent: got %d, want 60", p3.L2Sent)
	}
	if p3.L2Timeouts != 5 {
		t.Errorf("L2Timeouts: got %d, want 5", p3.L2Timeouts)
	}
	if p3.REJRxed != 1 {
		t.Errorf("REJRxed: got %d, want 1", p3.REJRxed)
	}
	if p3.RXCRCErrors != 2 {
		t.Errorf("RXCRCErrors: got %d, want 2", p3.RXCRCErrors)
	}
	if p3.ActiveTxPct != 2 {
		t.Errorf("ActiveTxPct: got %d, want 2", p3.ActiveTxPct)
	}
	if p3.ActiveBusyPct != 8 {
		t.Errorf("ActiveBusyPct: got %d, want 8", p3.ActiveBusyPct)
	}
}

func TestParseEmptyOutput(t *testing.T) {
	snap, err := ParseSCommandOutput([]string{})
	if err != nil {
		t.Fatalf("ParseSCommandOutput failed: %v", err)
	}
	if len(snap.Ports) != 0 {
		t.Errorf("expected 0 ports, got %d", len(snap.Ports))
	}
}

func TestParseLargeValues(t *testing.T) {
	output := `Uptime (Days Hours Mins)     99:23:59
Buffers:Max/Cur/Min/Out/Wait      999      500      100        5        2
Known Nodes/Max Nodes              50      100
L4 Connects Sent/Rxed            1000     2000
L4 Frames TX/RX/Resent/Reseq   50000    60000     1000      500
L3 Frames Relayed              123456
Port 01
L2 Frames Digied   100000
L2 Frames Heard    500000
L2 Frames Rxed     250000
L2 Frames Sent     300000
L2 Timeouts          5000
REJ Frames Rxed      1000
RX out of Seq         500
L2 Resequenced        100
Undrun/Poll T/o        50
RX Overruns            10
RX CRC Errors         200
FRMRs Sent              5
FRMRs Received          3
Frames abandoned      100
Active(TX/Busy) %  45  80`

	lines := strings.Split(output, "\n")
	snap, err := ParseSCommandOutput(lines)
	if err != nil {
		t.Fatalf("ParseSCommandOutput failed: %v", err)
	}

	if snap.System.UptimeDays != 99 {
		t.Errorf("UptimeDays: got %d, want 99", snap.System.UptimeDays)
	}
	if snap.System.L3Relayed != 123456 {
		t.Errorf("L3Relayed: got %d, want 123456", snap.System.L3Relayed)
	}

	p1 := snap.Ports[1]
	if p1 == nil {
		t.Fatal("port 1 missing")
	}
	if p1.L2Heard != 500000 {
		t.Errorf("L2Heard: got %d, want 500000", p1.L2Heard)
	}
	if p1.L2Sent != 300000 {
		t.Errorf("L2Sent: got %d, want 300000", p1.L2Sent)
	}
	if p1.ActiveTxPct != 45 {
		t.Errorf("ActiveTxPct: got %d, want 45", p1.ActiveTxPct)
	}
	if p1.ActiveBusyPct != 80 {
		t.Errorf("ActiveBusyPct: got %d, want 80", p1.ActiveBusyPct)
	}
}

func TestSystemStatsOnly(t *testing.T) {
	// Test parsing just system stats (no port table)
	output := `Uptime (Days Hours Mins)     05:12:30
Semaphore Get-Rel/Clashes        1000     5000
Buffers:Max/Cur/Min/Out/Wait      999      800      600       10        3
Known Nodes/Max Nodes              25      100
L4 Connects Sent/Rxed              50       75
L4 Frames TX/RX/Resent/Reseq    1000     2000      100       50
L3 Frames Relayed                5000`

	lines := strings.Split(output, "\n")
	snap, err := ParseSCommandOutput(lines)
	if err != nil {
		t.Fatalf("ParseSCommandOutput failed: %v", err)
	}

	sys := snap.System
	if sys.UptimeDays != 5 || sys.UptimeHours != 12 || sys.UptimeMins != 30 {
		t.Errorf("uptime: got %d:%d:%d, want 5:12:30", sys.UptimeDays, sys.UptimeHours, sys.UptimeMins)
	}
	if sys.SemGets != 1000 || sys.SemClashes != 5000 {
		t.Errorf("sem: got %d/%d, want 1000/5000", sys.SemGets, sys.SemClashes)
	}
	if sys.L4FramesTx != 1000 || sys.L4FramesRx != 2000 {
		t.Errorf("L4Frames: got %d/%d, want 1000/2000", sys.L4FramesTx, sys.L4FramesRx)
	}
	if sys.L4Resent != 100 || sys.L4Reseq != 50 {
		t.Errorf("L4Resent/Reseq: got %d/%d, want 100/50", sys.L4Resent, sys.L4Reseq)
	}
	if len(snap.Ports) != 0 {
		t.Errorf("expected 0 ports, got %d", len(snap.Ports))
	}
}
