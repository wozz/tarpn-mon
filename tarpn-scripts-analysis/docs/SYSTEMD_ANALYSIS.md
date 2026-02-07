# TARPN Scripts: Systemd Replacement Analysis

This document analyzes which wrapper scripts could be replaced or simplified by leveraging native systemd features.

---

## Executive Summary

The current TARPN architecture uses 7 systemd services, but each service simply runs a bash script that re-implements features systemd provides natively:

| Current Pattern | Systemd Native Solution |
|-----------------|------------------------|
| Polling loops checking if linbpq is running | `BindsTo=` / `After=` / `Requires=` |
| Repeated sleep calls to "waste time" | `Restart=on-failure` + `RestartSec=` |
| Flag files for enable/disable | `ConditionPathExists=` |
| `killall` to stop processes | `ExecStop=` and proper process management |
| `check_process()` function | Systemd's native process tracking |
| Semaphore files to stop services | `systemctl stop` / dependency chains |

**Potential reduction**: ~2,000+ lines of shell script could be replaced with ~100 lines of systemd unit configuration.

---

## Current Service Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Current (Wasteful) Architecture                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   tarpn.service          home.service          tarpn_mon.service            │
│        │                      │                       │                      │
│        ▼                      ▼                       ▼                      │
│   tarpn_background.sh    home_background.sh    tarpnmon-runner.sh           │
│        │                      │                       │                      │
│   ┌────┴────────────────┐     │                       │                      │
│   │ while true; do      │     │                       │                      │
│   │   check linbpq      │◄────┼───────────────────────┤                      │
│   │   check flag files  │     │                       │                      │
│   │   sleep 5-30 sec    │     │ (same pattern)        │ (same pattern)       │
│   │ done                │     │                       │                      │
│   └─────────────────────┘     └───────────────────────┘                      │
│                                                                              │
│   Problem: 7 scripts all polling for the same conditions!                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Detailed Analysis by Service

### 1. `tarpn.service` → `runbpq.sh` (LinBPQ Launcher)

**Current behavior** (`runbpq.sh` - 491 lines):
- Checks for flag files (`/tmp/stop_service_scripts.txt`)
- Stops tarpn_home if running
- Downloads boilerplate.cfg and make_local_bpq.sh
- Generates bpq32.cfg from node.ini
- Runs `linbpq` (blocking)

**What can be replaced with systemd**:
- Flag file checking → `ConditionPathExists=!/tmp/stop_service_scripts.txt`
- Stopping other services → `Conflicts=` or explicit `ExecStartPre=systemctl stop`
- The actual linbpq execution is fine as-is

**Proposed systemd unit**:
```ini
[Unit]
Description=LinBPQ Packet Node
ConditionPathExists=/home/pi/node.ini
ConditionPathExists=!/tmp/stop_service_scripts.txt
ConditionPathExists=/usr/local/sbin/source_url.txt
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/bpq
ExecStartPre=/usr/local/sbin/prepare_bpq_config.sh
ExecStart=/home/pi/bpq/linbpq
ExecStopPost=/bin/rm -f /usr/local/etc/node_start_time.txt
Restart=on-failure
RestartSec=30
StandardOutput=append:/var/log/tarpn_runbpq.log
StandardError=append:/var/log/tarpn_runbpq.log

[Install]
WantedBy=multi-user.target
```

**Lines eliminated**: ~300 (keeping only config generation in `prepare_bpq_config.sh`)

---

### 2. `tarpn_mon.service` → `tarpnmon-runner.sh` (346 lines!)

**Current behavior** - This is the most egregious example:

```bash
# Lines 179-224: Repeat function call 45 times instead of using a loop!
waste_time_if_node_ini_missing 0
waste_time_if_node_ini_missing 0
waste_time_if_node_ini_missing 0
# ... 42 more times!

# Lines 278-304: Repeat 26 more times
waste_time_if_node_not_up 0
waste_time_if_node_not_up 0
# ... 24 more times!

# Lines 309-340: Repeat 31 more times
waste_time_if_node_not_service 0
waste_time_if_node_not_service 0
# ... 29 more times!
```

**What it actually does**:
1. Wait for linbpq to start
2. Wait for BACKGROUND:ON in `/usr/local/etc/background.ini`
3. If both true, start tarpn-mon
4. If linbpq stops, **kill tarpn-mon** ← This is wrong!

**Why the current approach is problematic**:
- Killing tarpn-mon when linbpq stops loses all buffered data in the monitor
- tarpn-mon (and our replacement, tarpn-terminal) can handle reconnection internally
- There's no technical requirement to stop the monitor when the node stops
- The monitor should simply show "disconnected" and reconnect when available

**Proposed systemd unit** (for tarpn-terminal, our replacement):
```ini
[Unit]
Description=TARPN Terminal Monitor
# NO dependency on linbpq - we handle reconnection ourselves
After=network.target

[Service]
Type=simple
User=pi
# tarpn-terminal reads callsign from /home/pi/node.ini automatically
ExecStart=/usr/local/sbin/tarpn-terminal
Restart=always
RestartSec=5
StandardOutput=append:/var/log/tarpn_mon.log
StandardError=append:/var/log/tarpn_mon.log

[Install]
WantedBy=multi-user.target
```

**Lines eliminated**: ~340 (entire script!)

**Key insight**: The monitor should be **independent** of linbpq:
- It maintains its own connection and buffers
- It can display historical data even when disconnected
- It reconnects automatically when linbpq becomes available
- Killing it throws away valuable packet history

---

### 3. `home.service` → `home_background.sh` (555 lines!)

**Current behavior**:
- 150+ lines of `waste_time_if_not_running 0` calls
- Polls for linbpq process
- Polls for BACKGROUND:ON flag
- Manages tarpn_home.pyc lifecycle

**Same pattern - replace with**:
```ini
[Unit]
Description=TARPN Home Web Interface
BindsTo=linbpq.service
After=linbpq.service
ConditionPathExists=/usr/local/sbin/home_web_app/dateinstalled.txt
ConditionPathExists=!/tmp/stop_service_scripts.txt

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/sbin/home_web_app
ExecStartPre=/bin/sh -c 'grep -q "BACKGROUND:ON" /usr/local/etc/home.ini'
ExecStartPre=/bin/sh -c 'grep -q "BACKGROUND:ON" /usr/local/etc/background.ini'
ExecStartPre=/bin/mkdir -p /tmp/tarpn && chmod 777 /tmp/tarpn
ExecStartPre=/bin/touch /tmp/tarpn/tarpn_home_go.flag
ExecStart=/usr/bin/python3 tarpn_home.pyc
ExecStopPost=/bin/rm -f /tmp/tarpn/tarpn_home_go.flag
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/tarpn_home_webapp_copylog.log
StandardError=append:/var/log/tarpn_home_webapp_copylog.log

[Install]
WantedBy=linbpq.service
```

**Lines eliminated**: ~550

---

### 4. `neighbor_port_association.service` → `npa.sh` (373 lines)

**Current behavior**:
- Deeply nested if/else checking for node.ini (6 levels deep!)
- Polls for linbpq process
- Creates /tmp/tarpn/tnpa directory
- Runs neighbor_port_association.app in a loop

**Lines 118-153 - nested node.ini check**:
```bash
if [ -f $NODE_INIT ]; then
   echo -n;
else
   sleep 180
   if [ -f $NODE_INIT ]; then
      echo -n;
   else
      sleep 180
      if [ -f $NODE_INIT ]; then
         # ... 4 more levels!
```

**Replace with**:
```ini
[Unit]
Description=TARPN Neighbor Port Association
BindsTo=linbpq.service
After=linbpq.service
ConditionPathExists=/home/pi/node.ini
ConditionPathExists=/usr/local/sbin/neighbor_port_association.app
ConditionPathExists=!/tmp/stop_service_scripts.txt

[Service]
Type=simple
User=pi
ExecStartPre=/bin/mkdir -p /tmp/tarpn/tnpa
ExecStartPre=/bin/chmod 777 /tmp/tarpn/tnpa
ExecStart=/usr/local/sbin/npa_loop.sh
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/tarpn_neighbor_port_association.log

[Install]
WantedBy=linbpq.service
```

Where `npa_loop.sh` is simplified to ~20 lines:
```bash
#!/bin/bash
counter=0
while true; do
    /usr/local/sbin/neighbor_port_association.app
    counter=$((counter + 1))
    if [ $counter -lt 40 ]; then
        sleep 10
    else
        sleep 180
    fi
done
```

**Lines eliminated**: ~350

---

### 5. `pi_shutdown.service` → `pi_shutdown_background.sh` (733 lines)

**Current behavior**:
- GPIO pin manipulation for control panel
- Polls for shutdown/reboot button presses
- Blinks status LEDs
- Monitors linbpq status for LED indication

**This one is harder to replace** because:
- GPIO manipulation requires active polling
- LED blinking requires timing loops
- Button debouncing requires active polling

**Recommendation**: Keep most of this script, but:
- Remove the `check_process()` function - use systemd's `is-active` instead
- Remove semaphore file checking - use systemd conditions
- Extract GPIO functions to a shared library

**Modest improvement possible**: ~100 lines

---

### 6. `rx_tarpnstat.service` → Similar pattern

Should also use `BindsTo=linbpq.service` for automatic lifecycle management.

---

## Proposed New Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Proposed (Clean) Architecture                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                          linbpq.service                                      │
│                               │                                              │
│              ┌────────────────┼────────────────┐                            │
│              │                │                │                            │
│              ▼                ▼                ▼                            │
│     tarpn_mon.service   home.service    npa.service                        │
│     (BindsTo=linbpq)    (BindsTo=linbpq) (BindsTo=linbpq)                  │
│              │                │                │                            │
│              ▼                ▼                ▼                            │
│         tarpn-mon        python3          npa.app                          │
│       (direct exec)    tarpn_home.pyc    (simple loop)                     │
│                                                                              │
│   No polling! Systemd handles all process lifecycle!                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary of Changes

| Script | Current Lines | Proposed Lines | Reduction |
|--------|---------------|----------------|-----------|
| runbpq.sh | 491 | ~100 (config gen only) | 80% |
| tarpnmon-runner.sh | 346 | 0 (eliminated) | 100% |
| home_background.sh | 555 | 0 (eliminated) | 100% |
| npa.sh | 373 | ~20 | 95% |
| pi_shutdown_background.sh | 733 | ~633 | 14% |
| **Total** | **2,498** | **~753** | **~70%** |

---

## Implementation Notes

### 1. Dependency Chain
The key insight is that most services depend on linbpq. Using `BindsTo=` creates an automatic dependency that:
- Waits for linbpq to start before starting dependent services
- Automatically stops dependent services when linbpq stops
- Eliminates all the polling loops

### 2. Condition Checking
Instead of:
```bash
if [ -f /home/pi/node.ini ]; then
    # run
else
    sleep 180
    # check again...
fi
```

Use:
```ini
ConditionPathExists=/home/pi/node.ini
```

Systemd will simply not start the service until the condition is met.

### 3. Flag Files
The `BACKGROUND:ON` pattern in `.ini` files could be replaced with:
- Enabling/disabling the systemd service directly
- `systemctl enable/disable tarpn_mon.service`

This is more standard and doesn't require custom flag files.

### 4. Semaphore File Pattern
The `/tmp/stop_service_scripts.txt` semaphore is used by update.sh to pause all services. This could be replaced with:
```bash
# In update.sh
systemctl stop tarpn_mon.service home.service npa.service
# ... do update ...
systemctl start tarpn_mon.service home.service npa.service
```

---

## Benefits of Refactoring

1. **Reliability**: Systemd's process supervision is battle-tested
2. **Visibility**: `systemctl status` shows clear dependency tree
3. **Logging**: `journalctl` provides unified logging with timestamps
4. **Resource efficiency**: No polling loops consuming CPU
5. **Maintainability**: ~70% less shell script code to maintain
6. **Debugging**: Clear service states, no mysterious "waste_time" loops
7. **Boot speed**: Services start in parallel where dependencies allow

---

## Backward Compatibility

To maintain backward compatibility with existing `tarpn` commands:
- The `tarpn service on/off` commands could be mapped to `systemctl enable/disable`
- Flag files could be kept as an interface, with systemd watching them via `PathChanged=`

---

*Analysis Date: January 2026*
