package main

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
)

// hashCallsign takes a callsign and returns an HSL color as a string
func hashCallsign(callsign string) string {
	hash := md5.Sum([]byte(callsign))
	hexHash := hex.EncodeToString(hash[:6])
	var hue int
	fmt.Sscanf(hexHash, "%x", &hue)
	if hue > 360 {
		hue = hue % 360
	}
	saturation := 60 // %
	lightness := 67  // %

	return fmt.Sprintf("hsl(%d, %d%%, %d%%)", hue, saturation, lightness)
}
