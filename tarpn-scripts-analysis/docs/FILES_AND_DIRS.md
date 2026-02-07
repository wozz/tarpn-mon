# TARPN Files and Directories

## Directory Structure

### `/home/pi/`

The main user directory containing BPQ and configuration files.

| Path | Type | Purpose |
|------|------|---------|
| `/home/pi/bpq/` | Dir | LinBPQ installation directory |
| `/home/pi/bpq/linbpq` | Exec | LinBPQ executable |
| `/home/pi/bpq/bpq32.cfg` | Config | Generated BPQ configuration |
| `/home/pi/bpq/boilerplate.cfg` | Config | Template for bpq32.cfg |
| `/home/pi/bpq/make_local_bpq.sh` | Script | Generates bpq32.cfg from node.ini |
| `/home/pi/bpq/Files/` | Dir | BBS file storage |
| `/home/pi/bpq/HTMLPages/` | Dir | BPQ web interface pages |
| `/home/pi/node.ini` | Config | Node configuration (callsign, ports, etc.) |
| `/home/pi/minicom/` | Dir | Minicom serial terminal configs |
| `/home/pi/minicom/com4` | Symlink | → `/dev/tty8` |
| `/home/pi/minicom/com7` | Symlink | Serial port link |
| `/home/pi/ringfolder/` | Dir | Ring tone audio files |
| `/home/pi/Desktop/QtTermTCP` | Exec | Qt terminal application |
| `/home/pi/TARPN_Home.ini` | Config | TARPN Home web interface config |
| `/home/pi/tarpn-home-colors.json` | Config | TARPN Home color scheme |

### `/usr/local/sbin/`

System scripts and executables installed by TARPN.

| Path | Purpose | Source |
|------|---------|--------|
| `tarpn` | Main TARPN command-line tool | `tarpn` |
| `tarpn-mon` | Monitor application binary | `tarpn-mon.linux-arm32.zip` |
| `runbpq.sh` | LinBPQ launcher script | `runbpq.sh` |
| `tarpnmon-runner.sh` | tarpn-mon service script | `tarpnmon-runner.sh` |
| `configure_node_ini.sh` | Node configuration wizard | `configure_node_ini.sh` |
| `make_local_bpq.sh` | Generates bpq32.cfg | `make_local_bpq.sh` |
| `tarpnget.sh` | File downloader utility | `tarpnget.sh` |
| `sleep_with_count.sh` | Sleep with countdown utility | `sleep_with_count.sh` |
| `test_internet.sh` | Internet connectivity test | `test_internet.sh` |
| `update.sh` | TARPN update script | `update.sh` |
| `tarpn_background.sh` | Main background service | `tarpn_background.sh` |
| `pi_shutdown_background.sh` | Shutdown handling | `pi_shutdown_background.sh` |
| `statusmonitor.sh` | Status monitoring | `statusmonitor.sh` |
| `rx_tarpnstat.sh` | TARPN statistics receiver | `rx_tarpnstat.sh` |
| `npa.sh` | Neighbor port association | `npa.sh` |
| `node_calls_linktest.sh` | Link testing utility | `node_calls_linktest.sh` |
| `logfiletruncate.sh` | Log file management | `logfiletruncate.sh` |
| `tinfo.sh` | TNC info utility | `tinfo.sh` |
| `gpio_for_controlpanel.sh` | GPIO control panel | `gpio_for_controlpanel.sh` |
| `flashtnc.py` | NinoTNC flash utility | `flashtnc.py` |
| `get_tnc_version.py` | TNC version reader | `get_tnc_version.py` |
| `getver.py` | Version utility | `getver.py` |
| `source_url.txt` | TARPN update URL | Generated |
| `home_web_app/` | Dir - TARPN Home web app | `TARPN_Home_Latest.zip` |

### `/usr/local/etc/`

Configuration and state files.

| Path | Purpose |
|------|---------|
| `background.ini` | Contains `BACKGROUND:ON` when node runs on boot |
| `node_start_time.txt` | Timestamp of last node start |
| `tarpn_start2_top.txt` | Flag that start2 completed |
| `sudoerstest.txt` | Sudo access verification |

### `/var/log/`

Log files created by TARPN.

| Path | Purpose |
|------|---------|
| `tarpn_startstop.log` | Service start/stop events |
| `tarpn_command.log` | tarpn command execution log |
| `tarpn_runbpq.log` | LinBPQ startup log |
| `tarpn_mon.log` | tarpn-mon service log |
| `tarpn_home.log` | TARPN Home web interface log |
| `tarpn_service.log` | Main service log |
| `tarpn_neighbor_port_association.log` | NPA service log |
| `tarpn_rx_tarpnstat_service.log` | Stats receiver log |
| `tarpn_statusmonitor.log` | Status monitor log |
| `tarpn_controlpanel.log` | Control panel log |

### `/etc/systemd/system/`

Systemd service files.

| Path | Purpose | Runs |
|------|---------|------|
| `tarpn.service` | Main TARPN service | `tarpn_background.sh` |
| `tarpn_mon.service` | tarpn-mon service | `tarpnmon-runner.sh` |
| `home.service` | TARPN Home web interface | `home_background.sh` |
| `pi_shutdown.service` | Shutdown handling | `pi_shutdown_background.sh` |
| `statusmonitor.service` | Status monitoring | `statusmonitor.sh` |
| `rx_tarpnstat.service` | Stats receiver | `rx_tarpnstat.sh` |
| `neighbor_port_association.service` | Port association | `npa.sh` |

### `/dev/`

Device symlinks created by TARPN.

| Path | Target | Purpose |
|------|--------|---------|
| `/dev/tty8` | Physical device | Virtual serial for minicom |
| `/dev/tty8a` | Created symlink | Alternate serial port |

## Flag Files

Flag files control installation state and script flow.

| Path | Created By | Checked By | Purpose |
|------|------------|------------|---------|
| `/usr/local/sbin/tarpn_start1dl.flag` | start1dl | w, start1 | Prevents re-running installer |
| `/usr/local/sbin/tarpn_start1_finished.flag` | start1dl | start2 | Confirms start1dl completed |
| `/usr/local/sbin/tarpn_start1dl_starttime.txt` | start1dl | start1dl | Install start timestamp |
| `/usr/local/etc/tarpn_start2_top.txt` | start2 | start2 | Confirms start2 completed |
| `/tmp/stop_service_scripts.txt` | update.sh | All services | Stops all services for update |
| `/tmp/tarpn/tarpn_home_go.flag` | runbpq.sh | home_background.sh | Controls TARPN Home startup |

## Zip Files Downloaded

These zip files are downloaded and extracted during installation:

| File | Contents | Destination |
|------|----------|-------------|
| `bpq_6_0_21_40_mar_2021.zip` | LinBPQ binary + HTML pages | `/home/pi/bpq/` |
| `piminicom.zip` | Minicom configurations | `/home/pi/minicom/` |
| `TARPN_Home_Latest.zip` | TARPN Home web app | `/usr/local/sbin/home_web_app/` |
| `latest_ninotnc.zip` | NinoTNC tools | Various |
| `npa.zip` | Neighbor port association app | `/home/pi/neighbor_port_association.app/` |
| `tarpn-mon.linux-arm32.zip` | tarpn-mon binary | `/usr/local/sbin/` |
| `ringnoises.zip` | Ring tone audio files | `/home/pi/ringfolder/` |
| `rx_tarpnstatapp.zip` | Stats receiver app | `/home/pi/` |
| `bbs_checker.zip` | BBS checker app | `/home/pi/bbs_checker/` |
| `linktest.zip` | Link test app | `/home/pi/linktest-app/` |
| `listen.zip` | Listen app | `/home/pi/listen/` |
| `sendroutestocq.zip` | Route sender app | `/home/pi/sendroutestocq/` |
| `g8bpq_link_stress.zip` | Link stress test | `/home/pi/` |

## Configuration Files

### node.ini

Primary configuration file created by `tarpn config`. Contains:
- Node callsign
- SSID
- Port configurations (TNC types, baud rates)
- Neighbor definitions
- BBS settings

### bpq32.cfg

Generated by `make_local_bpq.sh` from:
- `boilerplate.cfg` (template)
- `node.ini` (user config)
- `chatconfig.cfg` (chat settings)

### TARPN_Home.ini

TARPN Home web interface configuration:
- Port number
- Authentication settings
- Display options
