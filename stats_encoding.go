package main

import (
	"bytes"
	"encoding/ascii85"
	"encoding/binary"
	"fmt"
	"io"
	"math/bits"
	"sort"
	"strconv"
	"strings"

	"github.com/andybalholm/brotli"
)

// ============================================================================
// CQ Encoding: [LS1]~CALLSIGN~PP~rxed,sent,timeouts,rej,crc,abandoned,tx%,busy%~
// ============================================================================

// LinkStatCQMessage represents a decoded CQ link stats broadcast
type LinkStatCQMessage struct {
	Callsign      string
	PortNum       int
	L2Rxed        int64
	L2Sent        int64
	L2Timeouts    int64
	REJRxed       int64
	RXCRCErrors   int64
	Abandoned     int64
	ActiveTxPct   int
	ActiveBusyPct int
}

const cqPrefix = "[LS1]"

// EncodeCQ encodes port stats into a CQ broadcast message body.
// Returns the message body (without "CQ " prefix); caller adds that.
func EncodeCQ(callsign string, ps *PortStats) string {
	return fmt.Sprintf("%s~%s~%d~%d,%d,%d,%d,%d,%d,%d,%d~",
		cqPrefix, callsign, ps.PortNum,
		ps.L2Rxed, ps.L2Sent, ps.L2Timeouts,
		ps.REJRxed, ps.RXCRCErrors, ps.FramesAbandoned,
		ps.ActiveTxPct, ps.ActiveBusyPct)
}

// DecodeCQ decodes a CQ link stats message body.
func DecodeCQ(content string) (*LinkStatCQMessage, error) {
	content = strings.TrimSpace(content)
	if !strings.HasPrefix(content, cqPrefix) {
		return nil, fmt.Errorf("missing %s prefix", cqPrefix)
	}

	// Split on ~ : [LS1], callsign, port, csv_values, (trailing empty)
	parts := strings.Split(content, "~")
	if len(parts) < 4 {
		return nil, fmt.Errorf("expected at least 4 tilde-separated parts, got %d", len(parts))
	}

	msg := &LinkStatCQMessage{
		Callsign: parts[1],
	}

	portNum, err := strconv.Atoi(parts[2])
	if err != nil {
		return nil, fmt.Errorf("invalid port number %q: %w", parts[2], err)
	}
	msg.PortNum = portNum

	// Parse CSV values
	vals := strings.Split(parts[3], ",")
	if len(vals) != 8 {
		return nil, fmt.Errorf("expected 8 CSV values, got %d", len(vals))
	}

	parseInt := func(s string) (int64, error) {
		return strconv.ParseInt(s, 10, 64)
	}
	parseIntSmall := func(s string) (int, error) {
		return strconv.Atoi(s)
	}

	if msg.L2Rxed, err = parseInt(vals[0]); err != nil {
		return nil, fmt.Errorf("invalid L2Rxed: %w", err)
	}
	if msg.L2Sent, err = parseInt(vals[1]); err != nil {
		return nil, fmt.Errorf("invalid L2Sent: %w", err)
	}
	if msg.L2Timeouts, err = parseInt(vals[2]); err != nil {
		return nil, fmt.Errorf("invalid L2Timeouts: %w", err)
	}
	if msg.REJRxed, err = parseInt(vals[3]); err != nil {
		return nil, fmt.Errorf("invalid REJRxed: %w", err)
	}
	if msg.RXCRCErrors, err = parseInt(vals[4]); err != nil {
		return nil, fmt.Errorf("invalid RXCRCErrors: %w", err)
	}
	if msg.Abandoned, err = parseInt(vals[5]); err != nil {
		return nil, fmt.Errorf("invalid Abandoned: %w", err)
	}
	if msg.ActiveTxPct, err = parseIntSmall(vals[6]); err != nil {
		return nil, fmt.Errorf("invalid ActiveTxPct: %w", err)
	}
	if msg.ActiveBusyPct, err = parseIntSmall(vals[7]); err != nil {
		return nil, fmt.Errorf("invalid ActiveBusyPct: %w", err)
	}

	return msg, nil
}

// safeDelta computes the delta between two counter values, handling rollover.
// If last < first, a counter reset occurred; treat last as the delta since reset.
func safeDelta(first, last int64) int64 {
	if last >= first {
		return last - first
	}
	return last // counter reset to 0, so last IS the delta since reset
}

// ============================================================================
// BBS Bulletin Encoding
// ============================================================================

const bulletinPrefix = "LS1D:"

// BulletinData represents the decoded contents of a BBS stats bulletin
type BulletinData struct {
	System       BulletinSystemStats
	Ports        map[int][]BulletinInterval // port -> time-ordered intervals
	IntervalMins int
}

// BulletinSystemStats is a subset of SystemStats for bulletin encoding
type BulletinSystemStats struct {
	UptimeMins int64
	BuffersCur int64
	KnownNodes int64
	L4FramesTx int64
	L4FramesRx int64
	L4Resent   int64
	L3Relayed  int64
}

// BulletinInterval represents one time interval of stats for a port
type BulletinInterval struct {
	DeltaRxed      uint16
	DeltaSent      uint16
	DeltaTimeouts  uint16
	DeltaRej       uint8
	DeltaCRC       uint8
	DeltaAbandoned uint8
	AvgTxPct       uint8
	AvgBusyPct     uint8
}

// Number of counters per port in bulletin encoding
const bulletinCountersPerPort = 8

// Bulletin encoding tags:
//   C = column-oriented binary + ascii85 (best for small/medium data)
//   Z = column-oriented binary + brotli + ascii85 (best for large data)
const (
	tagColumnBinary = 'C'
	tagColumnBrotli = 'Z'
)

// EncodeBulletin encodes stats into the most compact format available.
// Uses column-oriented binary encoding, optionally with brotli compression.
// Returns the complete bulletin string with LS1D: prefix and encoding byte.
func EncodeBulletin(sys BulletinSystemStats, ports map[int][]BulletinInterval, intervalMins int) string {
	colBin, err := encodeColumnBinary(sys, ports, intervalMins)
	if err != nil {
		// Fallback: return empty bulletin (shouldn't happen with valid data)
		return bulletinPrefix
	}

	rawA85 := encodeAscii85(colBin)
	bestTag := byte(tagColumnBinary)
	bestPayload := rawA85

	// Try brotli — may or may not beat raw column binary
	compressed, err := brotliCompress(colBin)
	if err == nil {
		compA85 := encodeAscii85(compressed)
		if len(compA85) < len(bestPayload) {
			bestTag = tagColumnBrotli
			bestPayload = compA85
		}
	}

	return fmt.Sprintf("%s%c%s", bulletinPrefix, bestTag, bestPayload)
}

// DecodeBulletin decodes a bulletin string back to structured data.
func DecodeBulletin(data string) (*BulletinData, error) {
	if !strings.HasPrefix(data, bulletinPrefix) {
		return nil, fmt.Errorf("missing %s prefix", bulletinPrefix)
	}
	rest := data[len(bulletinPrefix):]
	if len(rest) < 1 {
		return nil, fmt.Errorf("missing encoding byte")
	}
	tag := rest[0]
	payload := rest[1:]

	switch tag {
	case tagColumnBinary:
		bin, err := decodeAscii85(payload)
		if err != nil {
			return nil, fmt.Errorf("ascii85 decode failed: %w", err)
		}
		return decodeColumnBinary(bin)

	case tagColumnBrotli:
		bin, err := decodeAscii85(payload)
		if err != nil {
			return nil, fmt.Errorf("ascii85 decode failed: %w", err)
		}
		raw, err := brotliDecompress(bin)
		if err != nil {
			return nil, fmt.Errorf("brotli decompress failed: %w", err)
		}
		return decodeColumnBinary(raw)

	default:
		return nil, fmt.Errorf("unknown encoding byte %q", tag)
	}
}

// ============================================================================
// Column-Oriented Binary Encoding (TSDB-Inspired)
// ============================================================================

// Column encoding types
const (
	colTypeAllZero   = 0x00 // no data follows
	colTypeConstant  = 0x01 // 1 uint16 follows
	colTypeBitPacked = 0x02 // next byte = bit width, then packed data
	colTypeVarint    = 0x03 // num_intervals varints follow
)

func encodeColumnBinary(sys BulletinSystemStats, ports map[int][]BulletinInterval, intervalMins int) ([]byte, error) {
	portNums := sortedPortNums(ports)
	if len(portNums) == 0 {
		return nil, fmt.Errorf("no ports")
	}
	numIntervals := len(ports[portNums[0]])

	var buf bytes.Buffer

	// Header [6 bytes]
	buf.WriteByte(2) // version 2 = column-oriented
	buf.WriteByte(byte(len(portNums)))
	writeU16(&buf, uint16(numIntervals)) // uint16 to support >255 intervals (1-min × 24h = 1440)
	buf.WriteByte(byte(intervalMins))
	buf.WriteByte(0) // reserved

	// System block [14 bytes]
	writeU16(&buf, uint16(sys.UptimeMins))
	writeU16(&buf, uint16(sys.BuffersCur))
	writeU16(&buf, uint16(sys.KnownNodes))
	writeU16(&buf, uint16(sys.L4FramesTx))
	writeU16(&buf, uint16(sys.L4FramesRx))
	writeU16(&buf, uint16(sys.L4Resent))
	writeU16(&buf, uint16(sys.L3Relayed))

	// Port directory
	for _, pn := range portNums {
		buf.WriteByte(byte(pn))
	}

	// Column data: for each port, for each counter, encode all intervals
	for _, pn := range portNums {
		intervals := ports[pn]
		columns := extractColumns(intervals)
		for _, col := range columns {
			encodeColumn(&buf, col)
		}
	}

	return buf.Bytes(), nil
}

// extractColumns extracts 8 counter columns from interval data.
// Returns columns in order: rxed, sent, timeouts, rej, crc, abandoned, tx%, busy%
func extractColumns(intervals []BulletinInterval) [bulletinCountersPerPort][]uint16 {
	var cols [bulletinCountersPerPort][]uint16
	n := len(intervals)
	for i := 0; i < bulletinCountersPerPort; i++ {
		cols[i] = make([]uint16, n)
	}
	for j, iv := range intervals {
		cols[0][j] = iv.DeltaRxed
		cols[1][j] = iv.DeltaSent
		cols[2][j] = iv.DeltaTimeouts
		cols[3][j] = uint16(iv.DeltaRej)
		cols[4][j] = uint16(iv.DeltaCRC)
		cols[5][j] = uint16(iv.DeltaAbandoned)
		cols[6][j] = uint16(iv.AvgTxPct)
		cols[7][j] = uint16(iv.AvgBusyPct)
	}
	return cols
}

func encodeColumn(buf *bytes.Buffer, values []uint16) {
	// Check for all zeros
	allZero := true
	for _, v := range values {
		if v != 0 {
			allZero = false
			break
		}
	}
	if allZero {
		buf.WriteByte(colTypeAllZero)
		return
	}

	// Check for constant value
	allSame := true
	first := values[0]
	for _, v := range values[1:] {
		if v != first {
			allSame = false
			break
		}
	}
	if allSame {
		buf.WriteByte(colTypeConstant)
		writeU16(buf, first)
		return
	}

	// Find max value to determine bit width
	var maxVal uint16
	for _, v := range values {
		if v > maxVal {
			maxVal = v
		}
	}

	bw := bitsNeeded(maxVal)
	if bw <= 16 {
		buf.WriteByte(colTypeBitPacked)
		buf.WriteByte(bw)
		packed := packBits(values, bw)
		buf.Write(packed)
	} else {
		// Fallback to varint (shouldn't happen for uint16)
		buf.WriteByte(colTypeVarint)
		for _, v := range values {
			writeUvarint(buf, uint64(v))
		}
	}
}

func decodeColumnBinary(data []byte) (*BulletinData, error) {
	if len(data) < 6 {
		return nil, fmt.Errorf("data too short for header")
	}
	r := bytes.NewReader(data)

	version, _ := r.ReadByte()
	if version != 2 {
		return nil, fmt.Errorf("unsupported column version %d", version)
	}
	numPorts, _ := r.ReadByte()
	numIntervals := readU16(r)
	intervalMins, _ := r.ReadByte()
	r.ReadByte() // reserved

	result := &BulletinData{
		Ports:        make(map[int][]BulletinInterval),
		IntervalMins: int(intervalMins),
	}

	// System block
	result.System.UptimeMins = int64(readU16(r))
	result.System.BuffersCur = int64(readU16(r))
	result.System.KnownNodes = int64(readU16(r))
	result.System.L4FramesTx = int64(readU16(r))
	result.System.L4FramesRx = int64(readU16(r))
	result.System.L4Resent = int64(readU16(r))
	result.System.L3Relayed = int64(readU16(r))

	// Port directory
	portNums := make([]int, numPorts)
	for i := range portNums {
		b, _ := r.ReadByte()
		portNums[i] = int(b)
	}

	// Decode columns for each port
	for _, pn := range portNums {
		var cols [bulletinCountersPerPort][]uint16
		for i := 0; i < bulletinCountersPerPort; i++ {
			col, err := decodeColumnData(r, int(numIntervals))
			if err != nil {
				return nil, fmt.Errorf("port %d counter %d: %w", pn, i, err)
			}
			cols[i] = col
		}

		// Reconstruct intervals from columns
		intervals := make([]BulletinInterval, numIntervals)
		for j := 0; j < int(numIntervals); j++ {
			intervals[j] = BulletinInterval{
				DeltaRxed:      cols[0][j],
				DeltaSent:      cols[1][j],
				DeltaTimeouts:  cols[2][j],
				DeltaRej:       uint8(cols[3][j]),
				DeltaCRC:       uint8(cols[4][j]),
				DeltaAbandoned: uint8(cols[5][j]),
				AvgTxPct:       uint8(cols[6][j]),
				AvgBusyPct:     uint8(cols[7][j]),
			}
		}
		result.Ports[pn] = intervals
	}

	return result, nil
}

func decodeColumnData(r *bytes.Reader, numIntervals int) ([]uint16, error) {
	colType, err := r.ReadByte()
	if err != nil {
		return nil, fmt.Errorf("read column type: %w", err)
	}

	switch colType {
	case colTypeAllZero:
		return make([]uint16, numIntervals), nil

	case colTypeConstant:
		val := readU16(r)
		result := make([]uint16, numIntervals)
		for i := range result {
			result[i] = val
		}
		return result, nil

	case colTypeBitPacked:
		bw, err := r.ReadByte()
		if err != nil {
			return nil, fmt.Errorf("read bit width: %w", err)
		}
		packedLen := (int(bw)*numIntervals + 7) / 8
		packed := make([]byte, packedLen)
		if _, err := io.ReadFull(r, packed); err != nil {
			return nil, fmt.Errorf("read packed data: %w", err)
		}
		return unpackBits(packed, bw, numIntervals), nil

	case colTypeVarint:
		result := make([]uint16, numIntervals)
		for i := range result {
			v, err := binary.ReadUvarint(r)
			if err != nil {
				return nil, fmt.Errorf("read varint %d: %w", i, err)
			}
			result[i] = uint16(v)
		}
		return result, nil

	default:
		return nil, fmt.Errorf("unknown column type 0x%02x", colType)
	}
}

// ============================================================================
// Bit-packing helpers
// ============================================================================

// bitsNeeded returns the minimum number of bits to represent maxVal.
// Returns 0 for maxVal == 0 (caller should use allZero encoding).
func bitsNeeded(maxVal uint16) byte {
	if maxVal == 0 {
		return 0
	}
	return byte(bits.Len16(maxVal))
}

// packBits packs values into a byte slice using bw bits per value.
// Values are packed MSB-first (big-endian bit order).
func packBits(values []uint16, bw byte) []byte {
	totalBits := int(bw) * len(values)
	result := make([]byte, (totalBits+7)/8)

	bitPos := 0
	for _, v := range values {
		for b := int(bw) - 1; b >= 0; b-- {
			if v&(1<<uint(b)) != 0 {
				byteIdx := bitPos / 8
				bitIdx := 7 - (bitPos % 8)
				result[byteIdx] |= 1 << uint(bitIdx)
			}
			bitPos++
		}
	}

	return result
}

// unpackBits unpacks count values from packed data, each bw bits wide.
func unpackBits(data []byte, bw byte, count int) []uint16 {
	result := make([]uint16, count)

	bitPos := 0
	for i := 0; i < count; i++ {
		var v uint16
		for b := int(bw) - 1; b >= 0; b-- {
			byteIdx := bitPos / 8
			bitIdx := 7 - (bitPos % 8)
			if byteIdx < len(data) && data[byteIdx]&(1<<uint(bitIdx)) != 0 {
				v |= 1 << uint(b)
			}
			bitPos++
		}
		result[i] = v
	}

	return result
}

// ============================================================================
// Encoding helpers: ascii85, brotli, binary I/O
// ============================================================================

func encodeAscii85(data []byte) string {
	buf := make([]byte, ascii85.MaxEncodedLen(len(data)))
	n := ascii85.Encode(buf, data)
	return string(buf[:n])
}

func decodeAscii85(s string) ([]byte, error) {
	// ascii85 'z' abbreviation: 1 char → 4 bytes, so output can be up to 4× input
	buf := make([]byte, 4*len(s))
	ndst, _, err := ascii85.Decode(buf, []byte(s), true)
	if err != nil {
		return nil, err
	}
	return buf[:ndst], nil
}

func brotliCompress(data []byte) ([]byte, error) {
	var buf bytes.Buffer
	w := brotli.NewWriterLevel(&buf, brotli.BestCompression)
	if _, err := w.Write(data); err != nil {
		return nil, err
	}
	if err := w.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func brotliDecompress(data []byte) ([]byte, error) {
	r := brotli.NewReader(bytes.NewReader(data))
	return io.ReadAll(r)
}

func writeU16(buf *bytes.Buffer, v uint16) {
	b := [2]byte{}
	binary.BigEndian.PutUint16(b[:], v)
	buf.Write(b[:])
}

func readU16(r *bytes.Reader) uint16 {
	b := [2]byte{}
	r.Read(b[:])
	return binary.BigEndian.Uint16(b[:])
}

func readByte(r *bytes.Reader) uint8 {
	b, _ := r.ReadByte()
	return b
}

func writeUvarint(buf *bytes.Buffer, v uint64) {
	b := [binary.MaxVarintLen64]byte{}
	n := binary.PutUvarint(b[:], v)
	buf.Write(b[:n])
}

func sortedPortNums(ports map[int][]BulletinInterval) []int {
	nums := make([]int, 0, len(ports))
	for k := range ports {
		nums = append(nums, k)
	}
	sort.Ints(nums)
	return nums
}
