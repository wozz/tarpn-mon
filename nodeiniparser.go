package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// searchNodeIni searches for a line matching the pattern "local-op-callsign:<callsign>" in ~/node.ini.
func searchNodeIni() (string, error) {
	homeDir := os.Getenv("HOME")
	filePath := homeDir + "/node.ini"

	file, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 && parts[0] == "local-op-callsign" {
			return parts[1], nil
		}
	}

	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("failed to read file: %w", err)
	}

	return "", fmt.Errorf("pattern not found in file")
}
