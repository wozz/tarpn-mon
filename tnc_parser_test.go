package main

import (
	"reflect"
	"testing"
)

func TestParseTNCData(t *testing.T) {
	tests := []struct {
		name    string
		line    string
		want    *tncData
		wantErr bool
	}{
		{
			name: "Valid Data",
			line: "16:34:33R TNC>USB Port=1 <UI C>:=00:2.76=01:13FAAAAut=02:0010FB70=03:00000001=04:00000002=06:00000001=07:00000000=08:00000011=09:00000000=0A:00000022=0B:00000012=0C:02157BDF=0D:0000064B=0E:00000000=0F:00000000=10:000002B6=11:00000000",
			want: &tncData{
				FirmwareVersion:          "2.76",
				KAUP8R:                   "13FAAAAut",
				UptimeMillis:             1112944,
				BoardID:                  1,
				SwitchPositions:          2,
				ConfigMode:               1,
				AX25ReceivedPackets:      0,
				IL2PCorrectablePackets:   17,
				IL2PUncorrectablePackets: 0,
				TransmitPackets:          34,
				PreambleWordCount:        18,
				MainLoopCycleCount:       0x02157BDF,
				PTTOnTimeMillis:          1611,
				DCDOnTimeMillis:          0,
				ReceivedDataBytes:        0,
				TransmitDataBytes:        694,
				FECBytesCorrected:        0,
			},
			wantErr: false,
		},
		{
			name:    "Empty String",
			line:    "",
			want:    nil,
			wantErr: true,
		},
		{
			name:    "Invalid Format",
			line:    "This is not a TNC data line",
			want:    nil,
			wantErr: true,
		},
		{
			name:    "Incomplete Data",
			line:    "TNC>USB Port=1 <UI C>:=00:2.76=01:13FAA",
			want:    &tncData{FirmwareVersion: "2.76", KAUP8R: "13FAA"},
			wantErr: false,
		},
		{
			name:    "Invalid ID",
			line:    "TNC>USB Port=1 <UI C>:=ZZ:INVALID",
			want:    nil,
			wantErr: true,
		},
		{
			name: "Valid Data",
			line: `16:34:33R TNC>USB Port=1 <UI C>:
=00:3.42=01:=02:00104121=03:00000004=04:00000002=06:000000B0=07:00000000=08:00000000=09:00000000=0A:00000008=0B:00000016=0C:00D93A73=0D:0000064B=0E:00000000=0F:00000000=10:000002B6=11:00000000`,
			want: &tncData{
				FirmwareVersion:          "3.42",
				KAUP8R:                   "",
				UptimeMillis:             0x104121,
				BoardID:                  4,
				SwitchPositions:          2,
				ConfigMode:               0xb0,
				AX25ReceivedPackets:      0,
				IL2PCorrectablePackets:   0,
				IL2PUncorrectablePackets: 0,
				TransmitPackets:          8,
				PreambleWordCount:        0x16,
				MainLoopCycleCount:       0x0D93A73,
				PTTOnTimeMillis:          0x64b,
				DCDOnTimeMillis:          0,
				ReceivedDataBytes:        0,
				TransmitDataBytes:        0x2b6,
				FECBytesCorrected:        0,
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseTNCData(tt.line)
			if (err != nil) != tt.wantErr {
				t.Errorf("parseTNCData() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseTNCData() = %v, want %v", got, tt.want)
			}
		})
	}
}