package main

import (
	"reflect"
	"testing"
)

func TestParseTNCData(t *testing.T) {
	tests := []struct {
		name    string
		line    string
		portNum int
		want    *tncData
		wantErr bool
	}{
		{
			name:    "Valid Data",
			line:    "16:34:33R TNC>USB Port=1 <UI C>:=00:2.76=01:13FAAAAut=02:0010FB70=03:00000001=04:00000002=06:00000001=07:00000000=08:00000011=09:00000000=0A:00000022=0B:00000012=0C:02157BDF=0D:0000064B=0E:00000000=0F:00000000=10:000002B6=11:00000000",
			portNum: 1,
			want: &tncData{
				FirmwareVersion:          "2.76",
				KAUP8R:                   "13FAAAAut",
				UptimeMillis:             1112944,
				Uptime:                   "18m",
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
				PTTOnTime:                "1s",
				DCDOnTimeMillis:          0,
				DCDOnTime:                "0s",
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
			line:    "TNC>USB Port=2 <UI C>:=00:2.76=01:13FAA",
			want:    &tncData{FirmwareVersion: "2.76", KAUP8R: "13FAA"},
			portNum: 2,
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
			line: `16:34:33R TNC>USB Port=12 <UI C>:
=00:3.42=01:=02:00104121=03:00000004=04:00000002=06:000000B0=07:00000000=08:00000000=09:00000000=0A:00000008=0B:00000016=0C:00D93A73=0D:0000064B=0E:00000000=0F:00000000=10:000002B6=11:00000000`,
			want: &tncData{
				FirmwareVersion:          "3.42",
				KAUP8R:                   "",
				UptimeMillis:             0x104121,
				Uptime:                   "17m",
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
				PTTOnTime:                "1s",
				DCDOnTimeMillis:          0,
				DCDOnTime:                "0s",
				ReceivedDataBytes:        0,
				TransmitDataBytes:        0x2b6,
				FECBytesCorrected:        0,
			},
			portNum: 12,
			wantErr: false,
		},
		{
			name: "More Valid Data",
			line: `16:06:28R TNC>USB Port=1 <UI C>:
=00:3.42=01:=02:04D4C607=03:00000004=04:00000002=06:000000B0=07:00000000=08:0000132C=09:00000000=0A:000013CE=0B:00000016=0C:3F97A532=0D:00082DDD=0E:000A7A1A=0F:0002FFDB=10:0003A09E=11:000007ED`,
			want: &tncData{
				FirmwareVersion:          "3.42",
				KAUP8R:                   "",
				UptimeMillis:             81053191,
				Uptime:                   "22h30m",
				BoardID:                  4,
				SwitchPositions:          2,
				ConfigMode:               176,
				AX25ReceivedPackets:      0,
				IL2PCorrectablePackets:   4908,
				IL2PUncorrectablePackets: 0,
				TransmitPackets:          5070,
				PreambleWordCount:        22,
				MainLoopCycleCount:       1066902834,
				PTTOnTimeMillis:          536029,
				PTTOnTime:                "8m56s",
				DCDOnTimeMillis:          686618,
				DCDOnTime:                "11m26s",
				ReceivedDataBytes:        196571,
				TransmitDataBytes:        237726,
				FECBytesCorrected:        2029,
			},
			portNum: 1,
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			portNum, got, err := parseTNCData(tt.line)
			if (err != nil) != tt.wantErr {
				t.Errorf("parseTNCData() error = %v, wantErr %v", err, tt.wantErr)
				return
			} else if !tt.wantErr && portNum != tt.portNum {
				t.Errorf("parseTNCData() unexpected port: %d, expected: %d", portNum, tt.portNum)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("parseTNCData() = %v, want %v", got, tt.want)
			}
		})
	}
}
