package main

import (
	"fmt"
	"strconv"
	"strings"
)

type tncData struct {
	FirmwareVersion          string `json:"firmwareVersion"`
	KAUP8R                   string `json:"kaup8r"`
	UptimeMillis             uint64 `json:"uptimeMillis"`
	BoardID                  uint64 `json:"boardId"`
	SwitchPositions          uint64 `json:"switchPositions"`
	ConfigMode               uint64 `json:"configMode"`
	AX25ReceivedPackets      uint64 `json:"ax25ReceivedPackets"`
	IL2PCorrectablePackets   uint64 `json:"il2pCorrectablePackets"`
	IL2PUncorrectablePackets uint64 `json:"il2pUncorrectablePackets"`
	TransmitPackets          uint64 `json:"transmitPackets"`
	PreambleWordCount        uint64 `json:"preambleWordCount"`
	MainLoopCycleCount       uint64 `json:"mainLoopCycleCount"`
	PTTOnTimeMillis          uint64 `json:"pttOnTimeMillis"`
	DCDOnTimeMillis          uint64 `json:"dcdOnTimeMillis"`
	ReceivedDataBytes        uint64 `json:"receivedDataBytes"`
	TransmitDataBytes        uint64 `json:"transmitDataBytes"`
	FECBytesCorrected        uint64 `json:"fecBytesCorrected"`
}

func parseTNCData(line string) (int, *tncData, error) {
	portNum := 1
	data := &tncData{}
	prefix, line, found := strings.Cut(line, " <UI C>:")
	if !found {
		return portNum, nil, fmt.Errorf("invalid TNC data")
	}
	portData := strings.Split(prefix, "=")
	if len(portData) == 2 {
		pn, err := strconv.Atoi(portData[1])
		if err == nil {
			portNum = pn
		}
	}

	parts := strings.Split(line, "=")
	if len(parts) < 2 {
		return portNum, nil, fmt.Errorf("invalid TNC data format")
	}

	for _, part := range parts[1:] {
		if len(part) < 3 {
			continue // Skip parts that are too short
		}

		id, err := strconv.ParseUint(part[:2], 16, 8)
		if err != nil {
			return portNum, nil, fmt.Errorf("invalid ID format in part: %s", part)
		}

		valueStr := part[3:] // Value starts after the ID and colon

		switch id {
		case 0x00:
			data.FirmwareVersion = valueStr
		case 0x01:
			data.KAUP8R = valueStr
		case 0x02:
			data.UptimeMillis, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x03:
			data.BoardID, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x04:
			data.SwitchPositions, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x06:
			data.ConfigMode, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x07:
			data.AX25ReceivedPackets, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x08:
			data.IL2PCorrectablePackets, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x09:
			data.IL2PUncorrectablePackets, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x0A:
			data.TransmitPackets, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x0B:
			data.PreambleWordCount, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x0C:
			data.MainLoopCycleCount, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x0D:
			data.PTTOnTimeMillis, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x0E:
			data.DCDOnTimeMillis, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x0F:
			data.ReceivedDataBytes, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x10:
			data.TransmitDataBytes, _ = strconv.ParseUint(valueStr, 16, 64)
		case 0x11:
			data.FECBytesCorrected, _ = strconv.ParseUint(valueStr, 16, 64)
		}
	}

	return portNum, data, nil
}
