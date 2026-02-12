package main

import (
	"reflect"
	"testing"
)

func TestParseFrameControl(t *testing.T) {
	tests := []struct {
		name    string
		message string
		want    *ParsedFrame
	}{
		{
			name:    "I-frame command",
			message: `N0CALL>W5ABC <I C P R1 S2 pid=CF Len=100>`,
			want:    &ParsedFrame{FrameType: "I", NS: 2, NR: 1, PID: "CF", IsCommand: true, InfoLen: 100},
		},
		{
			name:    "I-frame response",
			message: `W5ABC>N0CALL <I R F R3 S4 pid=F0 Len=50>`,
			want:    &ParsedFrame{FrameType: "I", NS: 4, NR: 3, PID: "F0", IsCommand: false, InfoLen: 50},
		},
		{
			name:    "SABM command",
			message: `N0CALL>W5ABC <SABM C P>`,
			want:    &ParsedFrame{FrameType: "SABM", NS: -1, NR: -1, IsCommand: true},
		},
		{
			name:    "DISC command",
			message: `N0CALL>W5ABC <DISC C P>`,
			want:    &ParsedFrame{FrameType: "DISC", NS: -1, NR: -1, IsCommand: true},
		},
		{
			name:    "UA response",
			message: `W5ABC>N0CALL <UA R F>`,
			want:    &ParsedFrame{FrameType: "UA", NS: -1, NR: -1, IsCommand: false},
		},
		{
			name:    "DM response",
			message: `W5ABC>N0CALL <DM R F>`,
			want:    &ParsedFrame{FrameType: "DM", NS: -1, NR: -1, IsCommand: false},
		},
		{
			name:    "RR supervisory",
			message: `N0CALL>W5ABC <RR C P R5>`,
			want:    &ParsedFrame{FrameType: "RR", NS: -1, NR: 5, IsCommand: true},
		},
		{
			name:    "RNR supervisory",
			message: `W5ABC>N0CALL <RNR R F R2>`,
			want:    &ParsedFrame{FrameType: "RNR", NS: -1, NR: 2, IsCommand: false},
		},
		{
			name:    "REJ supervisory",
			message: `N0CALL>W5ABC <REJ C P R1>`,
			want:    &ParsedFrame{FrameType: "REJ", NS: -1, NR: 1, IsCommand: true},
		},
		{
			name:    "FRMR response",
			message: `W5ABC>N0CALL <FRMR R F>`,
			want:    &ParsedFrame{FrameType: "FRMR", NS: -1, NR: -1, IsCommand: false},
		},
		{
			name:    "UI frame",
			message: `N0CALL>CQ <UI C pid=FF Len=45>[TARPNstat V2]~CALL~>~tx500~ret10~buf2~`,
			want:    &ParsedFrame{FrameType: "UI", NS: -1, NR: -1, PID: "FF", IsCommand: true, InfoLen: 45},
		},
		{
			name:    "no control field",
			message: `some random text without control field`,
			want:    nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ParseFrameControl(tt.message)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("ParseFrameControl() = %+v, want %+v", got, tt.want)
			}
		})
	}
}
