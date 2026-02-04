package main

import (
	"fmt"
	"strconv"
	"strings"
)

type TARPNStat struct {
	Callsign string `json:"callsign"`
	Tx       int    `json:"tx"`
	Ret      int    `json:"ret"`
	Buf      int    `json:"buf"`
}

// Parse string: [TARPNstat V2]~CALLSIGN-SID~>~txINT~retINT~bufINT~
func parseTARPNStat(content string) (*TARPNStat, error) {
	if !strings.Contains(content, "[TARPNstat V2]") {
		return nil, fmt.Errorf("not a TARPNstat message")
	}

	// Find the start of the relevant data
	startIdx := strings.Index(content, "[TARPNstat V2]~")
	if startIdx == -1 {
		return nil, fmt.Errorf("invalid TARPNstat format prefix")
	}

	// Cut everything before "~" (inclusive of first tilde after V2])
	// Actually, the user said format is `[TARPNstat V2]~CALLSIGN-SID~>~txINT~retINT~bufINT~`
	// So let's look for `~` delimiters.

	// substring starting after `[TARPNstat V2]~`
	dataStr := content[startIdx+len("[TARPNstat V2]~"):]

	// Split by `~`
	parts := strings.Split(dataStr, "~")
	// Expected parts:
	// 0: CALLSIGN-SID
	// 1: > (separator?)
	// 2: txINT
	// 3: retINT
	// 4: bufINT
	// 5: empty (trailing ~)

	if len(parts) < 5 {
		return nil, fmt.Errorf("not enough parts in TARPNstat message: %d", len(parts))
	}

	stat := &TARPNStat{
		Callsign: parts[0],
	}

	// Validate parts[1] is ">" (or maybe ignore if it varies)
	// Format is: CALLSIGN~>~tx500~ret10~buf2~
	// Parts[2] = "tx500", parts[3] = "ret10", parts[4] = "buf2"

	var err error

	// Parse tx value (format: "tx123" or just "123")
	txStr := parts[2]
	if strings.HasPrefix(txStr, "tx") {
		txStr = txStr[2:]
	}
	stat.Tx, err = strconv.Atoi(txStr)
	if err != nil {
		return nil, fmt.Errorf("invalid tx value %q: %v", parts[2], err)
	}

	// Parse ret value (format: "ret123" or just "123")
	retStr := parts[3]
	if strings.HasPrefix(retStr, "ret") {
		retStr = retStr[3:]
	}
	stat.Ret, err = strconv.Atoi(retStr)
	if err != nil {
		return nil, fmt.Errorf("invalid ret value %q: %v", parts[3], err)
	}

	// Parse buf value (format: "buf123" or just "123")
	bufStr := parts[4]
	if strings.HasPrefix(bufStr, "buf") {
		bufStr = bufStr[3:]
	}
	stat.Buf, err = strconv.Atoi(bufStr)
	if err != nil {
		return nil, fmt.Errorf("invalid buf value %q: %v", parts[4], err)
	}

	return stat, nil
}
