# TARPN Installation Flow

## Overview

TARPN installation is a multi-stage process that runs across two reboots. The scripts are designed for Raspberry Pi running Raspberry Pi OS Bullseye (32-bit).

## Prerequisites

- Raspberry Pi (various models supported, see `tarpn_start1.sh` for complete list)
- Raspberry Pi OS Bullseye (32-bit only)
- User must be `pi` (hardcoded requirement)
- Internet connection

## Installation Stages

### Stage 1: Bootstrap (`w`)

**File:** `w.sh` (downloaded from `https://tarpn.net/w`)

**Purpose:** Entry point for installation

**Actions:**
1. Validates user is `pi`
2. Validates running from `/home/pi`
3. Checks for duplicate `w*` files
4. Validates 32-bit OS
5. Checks if already installed (flag file)
6. Downloads and executes `tarpn_start1.sh`

**Environment Variables Set:**
- `SOURCE_URL=https://tarpn.net/bullseye2021`

---

### Stage 2: Environment Validation (`tarpn_start1.sh`)

**File:** `tarpn_start1.sh`

**Purpose:** Validate hardware and OS, download main installer

**Actions:**
1. Validates user is `pi`
2. Checks Raspberry Pi hardware revision (whitelist of ~40 revisions)
3. Validates OS is Bullseye 11
4. Checks sudo access
5. Saves `SOURCE_URL` to `/usr/local/sbin/source_url.txt`
6. Installs `iputils-ping`
7. Downloads utility scripts:
   - `tarpnget.sh` → `/usr/local/sbin/`
   - `sleep_with_count.sh` → `/usr/local/sbin/`
8. Downloads and executes `tarpn_start1dl.sh`

**Files Created:**
- `/usr/local/sbin/source_url.txt`
- `/usr/local/sbin/tarpnget.sh`
- `/usr/local/sbin/sleep_with_count.sh`
- `/usr/local/etc/sudoerstest.txt`

---

### Stage 3: Main Installation (`tarpn_start1dl.sh`)

**File:** `tarpn_start1dl.sh` (~2000 lines)

**Purpose:** Install all TARPN software and prepare for post-reboot config

**Major Actions:**

1. **Create Log Files:**
   - `/var/log/tarpn_startstop.log`
   - `/var/log/tarpn_command.log`
   - `/var/log/tarpn_neighbor_port_association.log`
   - `/var/log/tarpn_rx_tarpnstat_service.log`
   - `/var/log/tarpn_runbpq.log`
   - `/var/log/tarpn_mon.log`
   - `/var/log/tarpn_statusmonitor.log`

2. **Download Post-Reboot Script:**
   - `tarpn_start2.sh` → `/usr/local/sbin/`

3. **Create BPQ Directory:**
   - Creates `/home/pi/bpq/`
   - Downloads `runbpq.sh` → `/usr/local/sbin/`
   - Downloads `make_local_bpq.sh` → `/home/pi/bpq/`
   - Downloads `boilerplate.cfg` → `/home/pi/bpq/`

4. **Install LinBPQ:**
   - Downloads `bpq_6_0_21_40_mar_2021.zip`
   - Extracts `pilinbpq.dms` → `linbpq`
   - Sets capabilities: `CAP_NET_RAW=ep CAP_NET_BIND_SERVICE=ep`
   - Copies HTML pages to `/home/pi/bpq/`

5. **Install Minicom:**
   - Downloads and extracts `piminicom.zip`
   - Creates symlinks in `/dev/` for com ports
   - Configures `/home/pi/minicom/` directory

6. **Install QtTermTCP:**
   - Downloads `piqttermtcp.dms` → Desktop
   - Configures `QtTermTCP.ini`

7. **Install TARPN Home Web Interface:**
   - Downloads `TARPN_Home_Latest.zip`
   - Installs Python dependencies (tornado, configparser)
   - Sets up `home.service`
   - Installs to `/usr/local/sbin/home_web_app/`

8. **Install NinoTNC Support:**
   - Downloads `latest_ninotnc.zip`
   - Installs flash tools and version readers
   - Installs `flashtnc.py`, `get_tnc_version.py`

9. **Install Neighbor Port Association:**
   - Downloads `npa.zip`
   - Sets up `neighbor_port_association.service`

10. **Install TARPN Command:**
    - Downloads `tarpn` script → `/usr/local/sbin/`
    - Downloads `configure_node_ini.sh` → `/usr/local/sbin/`
    - Downloads BPQ command extensions

11. **Install tarpn-mon:**
    - Downloads `tarpn-mon.linux-arm32.zip`
    - Extracts binary → `/usr/local/sbin/tarpn-mon`
    - Sets up `tarpn_mon.service`
    - Installs `tarpnmon-runner.sh`

12. **System Updates:**
    - Runs `apt-get update`
    - Runs `apt-get dist-upgrade`

13. **Finalize:**
    - Creates `/usr/local/sbin/tarpn_start1_finished.flag`
    - Creates `/forcefsck` (forces filesystem check on reboot)
    - Reboots system

---

### Stage 4: Post-Reboot Configuration (`tarpn_start2.sh`)

**File:** `tarpn_start2.sh` (run manually after reboot)

**Purpose:** Complete installation, set up services, configure system

**Major Actions:**

1. **Verify Stage 3 Completed:**
   - Checks for `/usr/local/sbin/tarpn_start1_finished.flag`

2. **System Updates:**
   - Runs `apt-get update` and `apt-get dist-upgrade` again

3. **Install TARPN Service:**
   - Downloads `tarpn-service.txt` → `tarpn.service`
   - Enables and starts `tarpn.service`

4. **Install PI Shutdown Service:**
   - Downloads `pi_shutdown_background.sh`
   - Downloads `pi_shutdown-service.txt`
   - Sets up `pi_shutdown.service`

5. **Install Status Monitor:**
   - Downloads `statusmonitor.sh`
   - Sets up `statusmonitor.service`

6. **Install RX TARPN Stat:**
   - Downloads `rx_tarpnstat.sh`
   - Downloads `rx_tarpnstatapp.zip`
   - Sets up `rx_tarpnstat.service`

7. **Install Additional Tools:**
   - Downloads `bbs_checker.zip`
   - Downloads `linktest.zip`
   - Downloads `listen.zip`
   - Downloads `sendroutestocq.zip`
   - Downloads `g8bpq_link_stress.zip`
   - Downloads `logfiletruncate.sh`

8. **Install GPIO Control Panel:**
   - Downloads `gpio_for_controlpanel.sh`

9. **Install Midori Browser:**
   - `apt-get install midori`

10. **Set Desktop Wallpaper:**
    - Downloads `ncpacket-wallpaper.gif`

11. **Finalize:**
    - Creates `/usr/local/etc/tarpn_start2_top.txt`
    - Creates `/forcefsck`
    - Reboots system

---

## Post-Installation

After the second reboot, the user runs:
```bash
tarpn config
```

This launches `configure_node_ini.sh` which guides the user through setting up `node.ini` with their callsign, port configurations, and other settings.

## Runtime Flow

After installation, services are managed automatically:

1. **On Boot:**
   - `tarpn.service` starts `tarpn_background.sh`
   - `pi_shutdown.service` starts `pi_shutdown_background.sh`
   - Various monitoring services start

2. **Background Service (`tarpn_background.sh`):**
   - Starts `runbpq.sh`
   - Manages LinBPQ lifecycle
   - Coordinates with TARPN Home

3. **tarpn-mon Service:**
   - `tarpnmon-runner.sh` monitors LinBPQ
   - Only starts `tarpn-mon` when LinBPQ is running
   - Kills `tarpn-mon` when LinBPQ stops

## Flag Files

| File | Purpose |
|------|---------|
| `/usr/local/sbin/tarpn_start1dl.flag` | Marks start1dl has begun |
| `/usr/local/sbin/tarpn_start1_finished.flag` | Marks start1dl completed |
| `/usr/local/sbin/tarpn_start2.flag` | Used during start2 |
| `/usr/local/etc/tarpn_start2_top.txt` | Marks start2 completed |
| `/usr/local/etc/background.ini` | Contains `BACKGROUND:ON` when node runs automatically |
| `/tmp/stop_service_scripts.txt` | Semaphore to stop all services (for updates) |

## Diagram

```
User downloads 'w' from tarpn.net
        │
        ▼
    ┌───────┐
    │   w   │  Validates environment
    └───┬───┘  Downloads tarpn_start1.sh
        │
        ▼
┌───────────────┐
│ tarpn_start1  │  Validates hardware/OS
└───────┬───────┘  Downloads tarpn_start1dl.sh
        │
        ▼
┌───────────────┐
│tarpn_start1dl │  Main installation
└───────┬───────┘  Installs everything
        │          REBOOTS
        ▼
    [REBOOT 1]
        │
        ▼
┌───────────────┐
│ tarpn_start2  │  Installs services
└───────┬───────┘  Completes setup
        │          REBOOTS
        ▼
    [REBOOT 2]
        │
        ▼
┌───────────────┐
│ tarpn config  │  User configuration
└───────┬───────┘  Creates node.ini
        │
        ▼
    ┌───────┐
    │ DONE  │  Node is operational
    └───────┘
```
