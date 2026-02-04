# LinBPQ Analysis

This directory contains a clone of the [LinBPQ source code](https://github.com/g8bpq/linbpq) and analysis documentation for understanding the packet node software used by TARPN.

## 64-bit Build Status

**Good news**: LinBPQ can be built for 64-bit. The makefile uses standard gcc with no architecture-specific flags:

```makefile
CC = gcc
LDFLAGS = -Xlinker -Map=output.map -lrt
CFLAGS = -DLINBPQ -MMD -g -fcommon -fasynchronous-unwind-tables
```

### Dependencies for Building

```bash
# Required packages for building on Debian/Ubuntu
sudo apt install build-essential libminiupnpc-dev libjansson-dev \
    libpaho-mqtt3a-dev libconfig-dev libpcap-dev zlib1g-dev
```

### Build Commands

```bash
cd linbpq
make           # Standard build with MQTT
make nomqtt    # Build without MQTT support
make noi2c     # Build without I2C support
```

---

## AX.25 Layer 2 Parameters

LinBPQ implements a full AX.25 Layer 2 (L2) stack. Key parameters for link optimization:

### Per-Port Parameters (bpq32.cfg)

| Parameter | TARPN Default | Description | Code Reference |
|-----------|---------------|-------------|----------------|
| `MAXFRAME` | 1 | Outstanding I-frames before ACK required (1-7) | `PORTWINDOW` in asmstrucs.h:656 |
| `FRACK` | 9000 | Frame Acknowledge timeout in ms (T1 timer) | `PORTT1` in asmstrucs.h:663 |
| `RESPTIME` | 40 | Delayed ACK timer in ms (T2 timer) | `PORTT2` in asmstrucs.h:664 |
| `RETRIES` | 20 | Max retransmissions before disconnect (N2) | `PORTN2` in asmstrucs.h:665 |
| `PACLEN` | 136 | Maximum packet data length | `PORTPACLEN` in asmstrucs.h:666 |
| `TXDELAY` | varies | TX key-up delay in ms | `PORTTXDELAY` in asmstrucs.h:657 |
| `PERSIST` | 205 | CSMA persistence (256/(# of transmitters)) | `PORTPERSISTANCE` in asmstrucs.h:658 |
| `SLOTTIME` | 50 | CSMA slot time in ms | `PORTSLOTTIME` in asmstrucs.h:661 |
| `TXTAIL` | 1 | TX tail time in ms | `PORTTAILTIME` in asmstrucs.h:662 |

### Global Parameters

| Parameter | TARPN Default | Description |
|-----------|---------------|-------------|
| `T3` | 180 | Link validation timer (seconds) - sends RR if no traffic |
| `IDLETIME` | 1800 | Idle link shutdown timer (seconds) |
| `L4TIMEOUT` | 120 | Layer 4 (NetROM) timeout in seconds |
| `L4RETRIES` | 2 | Layer 4 retry count |
| `L4WINDOW` | 3 | Layer 4 window size |

---

## Dedicated Point-to-Point Link Optimization

For TARPN's dedicated point-to-point links (where you know the neighbor is present), the current defaults may be suboptimal.

### Current TARPN Defaults Analysis

```
MAXFRAME=1       # Very conservative - only 1 frame in flight
FRACK=9000       # 9 seconds before retry
RETRIES=20       # 20 retries = 3+ minutes before disconnect
```

### Potential Optimizations for Dedicated Links

For links where the neighbor is always available (wired or stable RF):

```ini
# More aggressive for dedicated links
MAXFRAME=4       # Allow 4 frames in flight for higher throughput
FRACK=5000       # 5 second timeout (faster retry on loss)
RETRIES=60       # Higher retry count - we know neighbor is there
RESPTIME=100     # Slightly longer delayed ACK for batching
```

**Rationale**:
- `MAXFRAME=4`: With dedicated links, we can pipeline more frames
- Higher `RETRIES`: Since we know the link exists, retry longer before giving up
- Lower `FRACK`: Faster recovery from packet loss
- Higher `RESPTIME`: Allow more I-frames to arrive before ACKing (piggyback efficiency)

---

## Per-Neighbor Configuration (ROUTES Section)

LinBPQ allows per-neighbor tuning in the `ROUTES:` section. This is **much more powerful** than the current TARPN usage suggests.

### ROUTES Syntax

From `config.c:1620-1720`, the route entry parser supports:

```
CALL,QUALITY,PORT[,MAXFRAME,FRACK,PACLEN,INP3Enable]
```

Or the newer keyword format:
```
CALL=N0CALL PORT=1 QUALITY=200 MAXFRAME=4 FRACK=5000 PACLEN=236 NOKEEPALIVES=0
```

### Available Per-Neighbor Parameters

| Parameter | Type | Description | Code Reference |
|-----------|------|-------------|----------------|
| `CALL` | string | Neighbor callsign | `NEIGHBOUR_CALL` |
| `PORT` | int | Port number | `NEIGHBOUR_PORT` |
| `QUALITY` | int | Route quality (1-255) | `NEIGHBOUR_QUAL` |
| `MAXFRAME` | int | Window size override (1-7) | `NBOUR_MAXFRAME` |
| `FRACK` | int | Timeout override in ms | `NBOUR_FRACK` |
| `PACLEN` | int | Packet length override | `NBOUR_PACLEN` |
| `WINDOW` | int | Alias for MAXFRAME | `NBOUR_MAXFRAME` |
| `FARQUALITY` | int | Quality other end should use | config.c:1665 |
| `INP3` | 0/1 | Enable INP3 protocol | `INP3Node` |
| `NOKEEPALIVES` | 0/1/2 | Suppress keepalive probes | `NoKeepAlive` |
| `NOV2.2` | 0/1 | Force AX.25 v2.0 connect | `noV2point2` |
| `TCP` | host:port | NetROM over TCP | `TCPHost`, `TCPPort` |

### How Overrides Work

From `L2Code.c:1902-1914`:

```c
// IF ROUTE HAS A FRACK, SET IT
if (ROUTE->NBOUR_FRACK)
    FRACK = ROUTE->NBOUR_FRACK;
else
    FRACK = PORT->PORTT1;

// IF ROUTE HAS A MAXFRAME, SET IT
if (ROUTE->NBOUR_MAXFRAME)
    LINK->LINKWINDOW = ROUTE->NBOUR_MAXFRAME;
```

Per-neighbor settings **override** port defaults for that specific neighbor.

### Current TARPN Usage (Underutilized)

TARPN's boilerplate.cfg only uses basic routes:
```
ROUTES:
q~neighbor11~q,200,11
q~neighbor12~q,200,12
***
```

This sets only CALL, QUALITY, and PORT. **No per-neighbor tuning!**

### Recommended Enhanced Routes for TARPN

```ini
ROUTES:
; High-quality dedicated link - aggressive settings
N0CALL,200,1,4,5000,236
;       │   │ │ │    └── PACLEN=236 (larger packets)
;       │   │ │ └────── FRACK=5000 (5 sec timeout)
;       │   │ └──────── MAXFRAME=4 (4 frames in flight)
;       │   └────────── PORT=1
;       └────────────── QUALITY=200

; Or using keyword syntax (clearer):
N0CALL-2 PORT=2 QUALITY=200 MAXFRAME=4 FRACK=3000 PACLEN=236

; Marginal RF link - conservative
W1ABC PORT=3 QUALITY=150 MAXFRAME=1 FRACK=15000 PACLEN=128

; Suppress keepalives on very stable link
K1DEF PORT=4 QUALITY=200 NOKEEPALIVES=1
***
```

### NOKEEPALIVES Values

From the code, `NOKEEPALIVES` can be:
- `0`: Normal keepalive behavior (default)
- `1`: Suppress outgoing keepalive probes
- `2`: Suppress all keepalive processing for this neighbor

For dedicated always-on links, `NOKEEPALIVES=1` reduces unnecessary traffic.

### What's NOT Per-Neighbor (Limitation)

**RETRIES (N2) is port-level only**, not per-neighbor. From `L2Code.c:3746`:
```c
if (LINK->L2RETRIES >= PORT->PORTN2)  // Always uses port's N2
```

This means you can't say "retry 100 times for this neighbor but only 10 for that one."

**Workaround**: If you need different retry counts, put neighbors on different ports (different NinoTNC ports could have different RETRIES values).

### Statistics Tracked Per-Neighbor

The `ROUTE` structure tracks per-neighbor statistics:
```c
int NBOUR_IFRAMES;   // I-frames sent/received
int NBOUR_RETRIES;   // Retransmissions to this neighbor (counter, not config)
```

These are visible in the web interface and via the `ROUTES` node command.

---

## Timeout Behavior (L2Code.c)

The L2 timeout logic is in `L2Code.c:3726-3850`:

```c
VOID L2TIMEOUT(struct _LINKTABLE * LINK, struct PORTCONTROL * PORT)
{
    PORT->L2TIMEOUTS++;     // For stats

    LINK->L2RETRIES++;
    if (LINK->L2RETRIES >= PORT->PORTN2)
    {
        // Max retries exceeded - disconnect
        // ...
    }
    // Retransmit frame
}
```

Key observations:
1. Each timeout increments `L2RETRIES`
2. When `L2RETRIES >= PORTN2`, the link is disconnected
3. Timer value is `PORTT1` (FRACK), extended by `2 * PORTT1` per digipeater

### Digi Extension

From `L2Code.c:1709`:
```c
LINK->L2TIME += PORT->PORTT1;  // Adjust timeout for digis
```

Each digipeater in the path adds one FRACK interval to the timeout.

---

## Code Structure

### Key Source Files

| File | Lines | Purpose |
|------|-------|---------|
| `L2Code.c` | 4900 | AX.25 Layer 2 implementation |
| `L3Code.c` | 900 | NET/ROM Layer 3 routing |
| `L4Code.c` | 1800 | NET/ROM Layer 4 transport |
| `config.c` | 2400 | Configuration file parser |
| `kiss.c` | 1700 | KISS TNC interface |
| `cMain.c` | 2900 | Main loop and initialization |
| `LinBPQ.c` | 1100 | Linux-specific code |
| `bpqchat.c` | 1100 | Chat server |
| `ChatUtils.c` | 500 | Chat utilities (SSID stripping here) |
| `HTTPcode.c` | 5000 | Web interface |
| `TelnetV6.c` | 4800 | Telnet server |

### Data Structures

- `PORTCONTROL` (asmstrucs.h:575): Per-port configuration and state
- `_LINKTABLE`: Per-link state (connection, sequence numbers, retries)
- `TRANSPORTENTRY`: Layer 4 session state
- `ROUTE`: Neighbor/routing information

---

## KISS Protocol Modes

From `kiss.c`:

```c
#define CHECKSUM 1          // Add checksum byte
#define POLLINGKISS 2       // Polling mode
#define ACKMODE 4           // ACK required frames
#define POLLEDKISS 8        // Other end is polling us
#define D700 16             // D700 Mode (Escape "C" chars)
#define TNCX 32             // TNC-X Mode
#define PITNC 64            // PITNC Mode - can reset TNC with FEND 15 2
#define NOPARAMS 128        // Don't send SETPARAMS frame
#define FLDIGI 256          // Support FLDIGI command frames
#define TRACKER 512         // SCS Tracker - need to set KISS Mode
#define FASTI2C 1024        // Blocked I2C reads
#define DRATS 2048          // D-RATS mode
```

---

## Web Interface Ports

Default port assignments (from HTTPcode.c and TelnetV6.c):

| Port | Service |
|------|---------|
| 8008 | HTTP Web Interface |
| 8010 | Telnet Node Access |
| 8011 | Monitor Port |

---

## Recommendations for TARPN

### 1. Higher RETRIES for Dedicated Links

Since TARPN links are dedicated (neighbor is always there), increase `RETRIES` significantly:
```ini
RETRIES=60    # or higher
```

This prevents unnecessary disconnects during temporary RF issues while still detecting true failures.

### 2. Consider MAXFRAME > 1

For higher throughput on good links:
```ini
MAXFRAME=2    # or 4 for very stable links
```

Trade-off: More retransmission on loss, but higher throughput overall.

### 3. Per-Link Tuning

Use the ROUTES section to tune per-neighbor:
```ini
ROUTES:
; Very stable wired link - aggressive settings
LOCKEDROUTE PORT=1 CALL=STABLE QUALITY=200 MAXFRAME=4 FRACK=3000

; Marginal RF link - conservative settings
LOCKEDROUTE PORT=2 CALL=MARGINAL QUALITY=150 MAXFRAME=1 FRACK=15000
```

### 4. T3 Timer Consideration

`T3=180` (3 minutes) means RR frames are sent every 3 minutes on idle links. For always-up links, this could be longer to reduce overhead:
```ini
T3=600    # 10 minutes
```

---

## Building for 64-bit Raspberry Pi OS

```bash
# On 64-bit Raspberry Pi OS (Bookworm)
cd linbpq
make

# Set capabilities (required for raw socket access)
sudo setcap "CAP_NET_ADMIN=ep CAP_NET_RAW=ep CAP_NET_BIND_SERVICE=ep" linbpq
```

The makefile already handles this in the build target.

---

## KISS TNC vs LinBPQ: Layer Responsibilities

Understanding what the TNC does vs what LinBPQ does is critical for tuning.

### What the KISS TNC Does (Physical/MAC Layer)

The NinoTNC (or any KISS TNC) handles:
- **Modem**: FSK modulation/demodulation (1200 baud AFSK, 9600 baud, etc.)
- **PTT Control**: Key the radio transmitter
- **TXDELAY**: Hold PTT before sending data (set via KISS command, stored in TNC)
- **TXTAIL**: Hold PTT after data (set via KISS command, stored in TNC)
- **Carrier Detect**: DCD signal for CSMA
- **KISS Framing**: FEND/FESC encoding

The TNC is a "dumb pipe" - it sends whatever frames LinBPQ gives it.

### What LinBPQ Does (Data Link Layer - AX.25 L2)

LinBPQ handles **all** AX.25 protocol logic:
- **Frame Construction**: I, RR, REJ, SABM, DISC, UA, DM, FRMR frames
- **Sequence Numbers**: N(S), N(R), window management
- **Acknowledgments**: Sending RR/REJ, processing incoming ACKs
- **Timeouts (FRACK/T1)**: Retransmit timer - entirely in LinBPQ
- **Retries (N2)**: Retry counter - entirely in LinBPQ
- **RESPTIME (T2)**: Delayed ACK timer - entirely in LinBPQ
- **T3**: Link validation timer - entirely in LinBPQ
- **MAXFRAME (Window)**: Outstanding frames allowed - entirely in LinBPQ
- **PACLEN**: Packet fragmentation - entirely in LinBPQ
- **CSMA (PERSIST/SLOTTIME)**: Sent to TNC as KISS commands, but LinBPQ decides values

### Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         LinBPQ                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Layer 4 (NetROM Transport) - Sessions, L4 retries           ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ Layer 3 (NetROM Routing) - NODES broadcasts, INP3           ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ Layer 2 (AX.25) - FRACK, RETRIES, MAXFRAME, PACLEN          ││
│  │   I-frames, RR, REJ, SABM/UA, sequence numbers              ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                         KISS frames                              │
│                              ▼                                   │
└─────────────────────────────────────────────────────────────────┘
                               │
                          Serial/USB
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        NinoTNC                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ KISS decode, PTT, TXDELAY, TXTAIL, Modem, DCD               ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                               │
                            Radio
                               ▼
```

### Settings That Must Match Both Ends vs One-Sided

| Setting | Must Coordinate? | Notes |
|---------|------------------|-------|
| **FRACK** | No | Each end manages its own timeout independently |
| **RETRIES** | No | Each end has its own retry limit |
| **MAXFRAME** | Partially | Receiver must handle sender's window, but usually OK |
| **PACLEN** | No | Each end fragments its own data |
| **RESPTIME** | No | Each end delays its own ACKs |
| **PERSIST/SLOTTIME** | No* | Each end does its own CSMA |
| **TXDELAY** | No | Each radio/TNC combo needs its own value |

*For CSMA, both ends using similar values helps fairness, but isn't required.

**Key insight**: Almost all L2 parameters can be set **independently** on each end. You can change your FRACK, MAXFRAME without coordinating with your neighbor.

**Important exception - RETRIES**: While technically independent, the **lower retry count dominates** in practice:
- If A has RETRIES=100 and B has RETRIES=10
- When trouble occurs, B gives up after 10 retries and sends DISC
- A receives DISC and the link drops - A's 100 retries were pointless
- For high-retry strategies to work, **both sides need high retries**

High retries on only one side helps when:
- The other node is completely dead (crashed, no DISC sent)
- That side should be the "primary" that re-establishes the link

---

## One Neighbor Per Port (TARPN Architecture)

TARPN's architecture uses **one dedicated radio link per neighbor**. This simplifies some things:

### Implications

1. **No CSMA needed**: With only one neighbor, there's no channel contention
   - `PERSIST=255` (always transmit immediately)
   - `SLOTTIME=1` (minimal, doesn't matter)
   - Full-duplex behavior even on half-duplex radio

2. **Port settings = Neighbor settings**: Since port:neighbor is 1:1
   - `RETRIES` on the port **is** the retry count for that neighbor
   - No need for per-neighbor RETRIES override (which doesn't exist anyway)

3. **Simplified tuning**: Tune the port for that specific link's characteristics

### Optimal Settings for Dedicated Point-to-Point

```ini
; Port definition for a dedicated link to neighbor
PORT
PORTNUM=1
ID=Link to N0CALL
TYPE=ASYNC
PROTOCOL=KISS
COMPORT=/dev/ttyUSB0
SPEED=57600

; Since dedicated link - no CSMA contention
PERSIST=255          ; Always TX immediately
SLOTTIME=1           ; Minimal (doesn't matter)
FULLDUPLEX=0         ; Radio is half-duplex, but acts like full

; Tuned for reliable dedicated link
MAXFRAME=4           ; 4 frames in flight - higher throughput
FRACK=5000           ; 5 second timeout - faster retry
RETRIES=100          ; Very high - we KNOW neighbor is there
RESPTIME=100         ; Batch ACKs for efficiency
PACLEN=236           ; Larger packets OK on reliable link

; Standard TARPN settings
QUALITY=1
MINQUAL=50
IGNOREUNLOCKEDROUTES=1
NONORMALIZE=1
ENDPORT

ROUTES:
N0CALL,200,1,4,5000,236   ; Per-neighbor tuning
***
```

---

## INP3 Protocol Analysis

INP3 (InterNode Protocol version 3) is an enhancement to NetROM routing.

### What INP3 Does

From `BPQINP3.c`, INP3 provides:

1. **Round-Trip Time (RTT) Measurement**
   - Nodes exchange RTT probe messages
   - Measures actual path latency, not just hop count
   - Updates routing based on real performance

2. **RIF (Routing Information Frame) Updates**
   - Triggered updates when routes change significantly
   - More responsive than periodic NODES broadcasts
   - Includes RTT/latency information

3. **Smoothed RTT (SRTT)**
   ```c
   Route->SRTT = ((Route->SRTT * 80)/100) + ((RTT * 20)/100);
   ```
   - 80% old value + 20% new measurement
   - Prevents route flapping from momentary issues

### When INP3 Helps

- **Multi-path networks**: When there are multiple routes to a destination
- **Varying link quality**: Routes can adapt to congestion/interference
- **Large networks**: Better scaling than flooding NODES broadcasts

### TARPN Network Topology Considerations

**Important distinction**: L2 links are point-to-point, but L3 network graphs can be complex.

```
       B -------- C
      / \        / \
     /   \      /   \
    A     \    /     E
     \     \  /     /
      \     D     /
       \         /
        ----F----
```

In this topology:
- Each RF link is dedicated point-to-point (L2)
- But A→E has multiple paths: A-B-C-E, A-B-D-C-E, A-F-E, etc.
- INP3 could dynamically select the fastest path

### When INP3 Helps TARPN

- **Mesh connectivity**: Any network with multiple paths between nodes
- **Varying link quality**: One path might be congested or degraded
- **Failure recovery**: Quickly route around a down link
- **Load balancing**: Distribute traffic across available paths

### When INP3 Doesn't Help

- **Linear/tree topologies**: Only one path exists anyway
- **Very small networks**: Overhead may exceed benefit
- **Tightly controlled routing**: If you want manual path control

### INP3 Configuration

```ini
; Global settings
MAXHOPS=6        ; INP3 hop limit
MAXRTT=90        ; Max acceptable RTT in seconds

; Per-port
ALLOWINP3=1      ; Accept INP3 if offered
ENABLEINP3=1     ; Proactively send INP3 RTT probes
INP3ONLY=0       ; 1 = Disable legacy NODES broadcasts

; Per-neighbor in ROUTES:
N0CALL PORT=1 QUALITY=200 INP3=1
```

### Recommendation for TARPN

**Consider INP3 if your network has**:
- Multiple paths between any nodes (mesh connectivity)
- Links with variable quality that might benefit from dynamic routing
- Growth plans toward mesh topology

**Skip INP3 if your network is**:
- Purely linear (A-B-C-D chain)
- Tree-shaped with no redundant paths
- Very small (3-4 nodes)

For networks with any mesh connectivity, INP3's RTT-based routing could improve performance by automatically selecting faster paths.

### INP3 Statistics and Data

INP3 provides rich per-neighbor statistics, tracked in the `ROUTE` structure (`asmstrucs.h:227-245`):

```c
int NBOUR_IFRAMES;      // I-frames sent/received (cumulative)
int NBOUR_RETRIES;      // Retransmissions (cumulative)
int SRTT;               // Smoothed Round-Trip Time (in 10ms units)
int NeighbourSRTT;      // Other end's SRTT (exchanged via INP3)
int RTTIncrement;       // Average of ours and neighbor's SRTT
```

**Accessing this data**:
1. **ROUTES command**: `ROUTES` node command shows per-neighbor I-frames, Retries, retry %, SRTT
2. **Web interface**: `HTTPcode.c:3937-3953` displays stats in HTML tables
3. **Programmatic**: Could be accessed via telnet API or BPQ host mode

**Data available from LinBPQ ROUTES command** (`Cmd.c:1921-1943`):
- Callsign and port
- I-frames count
- Retries count
- Retry percentage
- Queue depth
- Remote quality
- SRTT (if INP3 enabled)
- Neighbor's SRTT (if INP3 enabled)

### Comparison: LinBPQ Stats vs TARPNstat

| Data Point | LinBPQ ROUTES | TARPNstat (rx_tarpnstatapp) |
|------------|---------------|------------------------------|
| I-frames (tx) | ✓ NBOUR_IFRAMES | ✓ tx |
| Retries | ✓ NBOUR_RETRIES | ✓ ret |
| Retry % | ✓ (calculated) | - (calculated in UI) |
| Buffer/queue | ✓ Queued | ✓ buf |
| RTT/latency | ✓ SRTT (INP3) | ✗ |
| Remote RTT | ✓ NeighbourSRTT (INP3) | ✗ |
| Quality | ✓ | ✗ |
| Last heard | ✓ | ✗ |

### How TARPNstat Works (Bilateral Stats via RF)

The TARPNstat system provides **bilateral link statistics** by having each node broadcast its local stats:

```
Node A                                    Node B
┌─────────────────┐                      ┌─────────────────┐
│ rx_tarpnstatapp │                      │ rx_tarpnstatapp │
│ reads LinBPQ    │                      │ reads LinBPQ    │
│ ROUTES stats    │                      │ ROUTES stats    │
└────────┬────────┘                      └────────┬────────┘
         │                                        │
         ▼                                        ▼
   CQ broadcast:                           CQ broadcast:
   [TARPNstat V2]~A~>~tx500~ret10~buf2~   [TARPNstat V2]~B~>~tx480~ret5~buf1~
         │                                        │
         └──────────────► RF ◄────────────────────┘
                          │
                          ▼
              Monitor port sees BOTH broadcasts
              ─────────────────────────────────
              A sees: A's stats + B's stats
              B sees: B's stats + A's stats
```

**Key insight**: Each node broadcasts its **local** ROUTES statistics (from LinBPQ's NBOUR_IFRAMES, NBOUR_RETRIES, queue depth) as CQ/UI frames. The monitor port receives **both** local and neighbor broadcasts, giving a bilateral view of link health.

This is clever because:
- No direct node-to-node connections needed
- Uses existing RF infrastructure
- Each node only needs to know its own stats
- Bilateral view emerges from monitoring both directions

**What `rx_tarpnstatapp` does**:
1. Queries LinBPQ for local ROUTES statistics
2. Formats as `[TARPNstat V2]~CALLSIGN~>~txINT~retINT~bufINT~`
3. Broadcasts on each port as CQ/UI frame

**What our monitor does** (`tarpn_stat.go`):
1. Parses all TARPNstat broadcasts from the monitor stream
2. Both our own (local stats) and neighbors' (remote stats)
3. Builds up bilateral view of each link

**Note**: `rx_tarpnstatapp` source is not currently published but is available from the TARPN maintainer on request. It provides unique bilateral stats functionality that LinBPQ alone doesn't offer.

---

## NetROM over TCP

LinBPQ supports tunneling NetROM (Layer 3) over TCP/IP.

### How It Works

From `config.c:1698-1712`:
```c
else if (strcmp(ptr, "TCP") == 0)
{
    Route->tcphost = _strdup(val);
    Route->tcpport = atoi(port);  // Default 53119
}
```

### Configuration

```ini
ROUTES:
; Normal RF neighbor
N0CALL PORT=1 QUALITY=200

; NetROM over TCP to remote node
W1ABC TCP=w1abc.example.com:53119 QUALITY=150
***
```

### Use Cases

1. **Internet linking**: Connect distant TARPN networks over Internet
2. **Backup paths**: TCP tunnel as fallback if RF fails
3. **Testing**: Connect nodes without radios for development

### Considerations for TARPN

- **Purist approach**: TARPN is "Terrestrial Amateur Radio" - no Internet by philosophy
- **Practical use**: Could be useful for:
  - Initial testing before radios are set up
  - Linking isolated TARPN islands
  - Development and testing

---

## References

- [LinBPQ Documentation](http://www.cantab.net/users/john.wiseman/Documents/)
- [BPQ32 Configuration Guide](http://www.cantab.net/users/john.wiseman/Documents/BPQ32%20Configuration.html)
- [AX.25 Specification](https://www.tapr.org/pub_ax25.html)

---

*Analysis Date: January 2026*
