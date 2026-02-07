# TARPN Systemd Services

## Overview

TARPN installs 7 systemd services to manage various background processes. All services are configured with `Restart=always` and `RestartSec=2`.

## Service Hierarchy

```
                    ┌─────────────────┐
                    │  tarpn.service  │  Main orchestrator
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────────┐  ┌─────────────┐  ┌──────────────────┐
    │ runbpq.sh    │  │ TARPN Home  │  │ tarpn_mon.service│
    │ (LinBPQ)     │  │ (Web UI)    │  │ (Monitor)        │
    └──────────────┘  └─────────────┘  └──────────────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────────┐  ┌─────────────────┐  ┌────────────────┐
    │ statusmonitor│  │ rx_tarpnstat   │  │ neighbor_port  │
    │   .service   │  │   .service     │  │ _association   │
    └──────────────┘  └─────────────────┘  └────────────────┘
```

## Service Details

### tarpn.service

**Purpose:** Main TARPN background service - orchestrates everything

**Runs:** `/usr/local/sbin/tarpn_background.sh`

**Log:** `/var/log/tarpn_service.log`

**Responsibilities:**
- Starts and monitors `runbpq.sh` (LinBPQ)
- Coordinates with TARPN Home web interface
- Manages lifecycle of other services

**Key Functions:**
- Waits for `BACKGROUND:ON` in `/usr/local/etc/background.ini`
- Respects stop semaphore at `/tmp/stop_service_scripts.txt`

---

### tarpn_mon.service

**Purpose:** Runs tarpn-mon monitor application

**Runs:** `/usr/local/sbin/tarpnmon-runner.sh`

**Log:** `/var/log/tarpn_mon.log`

**Responsibilities:**
- Monitors LinBPQ status
- Starts `tarpn-mon` only when LinBPQ is running
- Kills `tarpn-mon` when LinBPQ stops

**Runner Script Logic:**
```
Loop:
  1. Check if BACKGROUND:ON
  2. Check if linbpq process running (pgrep -nf linbpq)
  3. If both true, fork tarpn-mon if not already running
  4. If linbpq not running, kill tarpn-mon
  5. Sleep and repeat
```

**Dependencies:**
- Requires LinBPQ to be running
- Requires `BACKGROUND:ON` in background.ini

---

### home.service

**Purpose:** TARPN Home web interface (Python/Tornado)

**Runs:** `/usr/local/sbin/home_background.sh`

**Log:** `/var/log/tarpn_home.log`

**Responsibilities:**
- Serves web interface on configured port
- Provides node status, configuration, and control
- Runs Python tornado-based web application

**Control Mechanism:**
- Controlled via `/tmp/tarpn/tarpn_home_go.flag`
- `runbpq.sh` creates/removes this flag to control startup

---

### pi_shutdown.service

**Purpose:** Handles graceful shutdown and GPIO-based power control

**Runs:** `/usr/local/sbin/pi_shutdown_background.sh`

**Log:** `/var/log/tarpn_control_panel.log`

**Responsibilities:**
- Monitors GPIO for shutdown button
- Handles graceful node shutdown
- Coordinates service stopping

---

### statusmonitor.service

**Purpose:** Monitors system and node status

**Runs:** `/usr/local/sbin/statusmonitor.sh`

**Log:** `/var/log/tarpn_statusmonitor.log`

**Responsibilities:**
- Periodically checks system health
- Reports status to log files
- May trigger alerts

---

### rx_tarpnstat.service

**Purpose:** Receives and processes TARPN statistics

**Runs:** `/usr/local/sbin/rx_tarpnstat.sh`

**Log:** `/var/log/tarpn_rx_tarpnstat_service.log`

**Responsibilities:**
- Receives statistics from network
- Processes and stores stat data
- Works with `rx_tarpnstatapp`

---

### neighbor_port_association.service

**Purpose:** Associates neighbors with physical ports

**Runs:** `/usr/local/sbin/npa.sh`

**Log:** `/var/log/tarpn_neighbor_port_association.log`

**Responsibilities:**
- Tracks which neighbors are reachable on which ports
- Maintains port-to-neighbor mappings
- Used for routing decisions

---

## Service Management Commands

```bash
# View service status
systemctl status tarpn.service
systemctl status tarpn_mon.service

# Start/stop services
sudo systemctl start tarpn.service
sudo systemctl stop tarpn.service

# Enable/disable on boot
sudo systemctl enable tarpn.service
sudo systemctl disable tarpn.service

# View logs
journalctl -u tarpn.service -f
journalctl -u tarpn_mon.service -f

# Restart service
sudo systemctl restart tarpn.service
```

## Service Control Flow

### Normal Startup

1. System boots
2. All TARPN services start (due to `WantedBy=multi-user.target`)
3. `tarpn.service` checks for `BACKGROUND:ON`
4. If enabled, starts `runbpq.sh`
5. `runbpq.sh` starts LinBPQ
6. `tarpnmon-runner.sh` detects LinBPQ, starts `tarpn-mon`
7. Other monitoring services activate

### During Update

1. `update.sh` creates `/tmp/stop_service_scripts.txt`
2. All service scripts check for this semaphore
3. Services gracefully stop
4. Update completes
5. Semaphore removed
6. Services restart via systemd

### Graceful Shutdown

1. Shutdown initiated (button or command)
2. `pi_shutdown_background.sh` coordinates shutdown
3. LinBPQ stopped gracefully
4. `tarpnmon-runner.sh` kills `tarpn-mon`
5. System shuts down

## Common Issues

### Service Won't Start

Check:
1. Log files for errors
2. Presence of required flag files
3. Semaphore file `/tmp/stop_service_scripts.txt`
4. `BACKGROUND:ON` in `/usr/local/etc/background.ini`

### tarpn-mon Not Running

Check:
1. LinBPQ is running: `pgrep -f linbpq`
2. `BACKGROUND:ON` is set
3. `/var/log/tarpn_mon.log` for errors

### Multiple Instances

The runner scripts use `pgrep` to check for running processes. If process names are similar, conflicts may occur.
