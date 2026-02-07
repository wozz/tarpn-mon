# send-routes-via-cq

A Go rewrite of the TARPN send-routes-via-cq utility for packet radio link status broadcasting.

## Overview

This program connects to a local G8BPQ packet radio node via Telnet (port 8010), retrieves the routes table using the "R R" command, parses it, and broadcasts link status information via CQ on each active port.

## Building

```bash
go build -o send-routes-via-cq
```

For cross-compilation (e.g., for Raspberry Pi):

```bash
# For Raspberry Pi (ARM)
GOOS=linux GOARCH=arm GOARM=7 go build -o send-routes-via-cq-arm

# For Raspberry Pi 4 (ARM64)  
GOOS=linux GOARCH=arm64 go build -o send-routes-via-cq-arm64
```

## Usage

```bash
# Run the program (no arguments needed, skips port 32 by default)
./send-routes-via-cq

# Show version
./send-routes-via-cq -v

# Show help
./send-routes-via-cq -h

# Skip specific ports (comma-separated)
./send-routes-via-cq --skip=32,33

# Don't skip any ports
./send-routes-via-cq --no-skip
```

## Changes from Original C Version

### Version 5 (Go Rewrite)
- Complete rewrite in Go for improved portability
- Support for new route format with double-locked routes (`!!`)
- Support for no space after chevron (e.g., `>32`)
- Higher port numbers (up to 32)
- Better error handling and timeout management
- Cleaner code structure with unit tests

### Key Differences in New Format Support

The original C code only supported single `!` for locked routes. The new format supports:

**Old format:**
```
> 1 AI4WV-2   200  20! 893  110  12% 0 0 19:33  1 200
> 2 KK4VBE-2  200  14! 876   21   2% 0 0 19:31  1 200
```

**New format (double-locked routes, no space after chevron):**
```
2 N2IRZ-2   200   0!!   0    0      0 0 00:00  0 0
> 3 NF4L-2    200   3!!  11    2  18% 0 0 15:03  0 200
> 1 NZ2Z-2    200   2!!   9    2  22% 0 0 00:00  0 0
>32 WA2M-9    200   1!   0    0      0 0 00:00  0 0 41430
```

Key changes handled:
- `!!` for double-locked routes (in addition to single `!`)
- No space between `>` and port number (e.g., `>32` instead of `> 32`)
- Higher port numbers (up to 32)
- Trailing data on lines is ignored

The `LockedRoutes` field now contains the count of `!` marks:
- `0` = not locked
- `1` = single locked (`!`)
- `2` = double locked (`!!`)

## Configuration

The following constants can be modified in `main.go`:

| Constant | Default | Description |
|----------|---------|-------------|
| `NodeAddress` | `127.0.0.1:8010` | Telnet address of the G8BPQ node |
| `LogFileName` | `/var/log/tarpn_linkstatus.log` | Path to the link status log file |
| `MaxRoutes` | `22` | Maximum number of routes to parse |
| `MaxPorts` | `32` | Maximum number of ports to check |

By default, port 32 (virtual TCP port) is skipped. Use `--skip=` to customize which ports to skip, or `--no-skip` to process all ports.

## Log Output

The program appends link status to the log file in the format:

```
2024-01-15 19:33:45 -- goodBAD!----good--------------------skip...
```

Where each 4-character block represents a port:
- `good` = Link is active (chevron present)
- `BAD!` = Link is configured but inactive (no chevron)
- `skip` = Port was skipped via --skip option
- `----` = No locked route on this port

## Running Tests

```bash
go test -v
```

## License

Based on original TARPN project code. See original C source for license terms.
