# TARPN Bookworm2024 Install Scripts Analysis

Analysis of the `bookworm2024` release scripts downloaded from `https://tarpn.net/bookworm2024/`.
This is a work-in-progress port of the TARPN install system to Debian 12 "Bookworm", still 32-bit only.

**Scripts analyzed**: 48 files (shell scripts, Python scripts, config files, systemd units)
**Date of analysis**: 2026-02-07

---

## 1. Install Chain Overview

The installation proceeds through a chain of scripts:

```
w.sh                    User downloads and runs manually
  └─► tarpn_start1.sh   Platform checks, downloads tarpn_start1dl.sh
        └─► tarpn_start1dl.sh   Main installer (~2000 lines): downloads all binaries,
        │                        configs, services, and scripts
        └─► tarpn_start2.sh     Final setup: systemd services, apt upgrades, reboot
```

**Update path**: `tarpn update` → `update.sh` (~2850 lines)

### What Each Script Does

| Script | Purpose |
|--------|---------|
| `w.sh` | Entry point. Checks user=pi, 32-bit OS, downloads tarpn_start1.sh |
| `tarpn_start1.sh` | Platform validation (Pi model, OS version), downloads tarpn_start1dl.sh |
| `tarpn_start1dl.sh` | Bulk installer: creates dirs, installs binaries, configs, Python packages |
| `tarpn_start2.sh` | Post-install: apt upgrade, systemd service installation, reboot |
| `update.sh` | Update existing install: stops services, downloads new files, restarts |
| `tarpn_background.sh` | Main runtime orchestrator: starts LinBPQ, monitors processes |
| `runbpq.sh` | LinBPQ launcher with retry logic |
| `tarpnget.sh` | Download helper with 5-attempt retry and HTML error detection |
| `sleep_with_count.sh` | Visual countdown sleep functions |
| `configure_node_ini.sh` | Interactive node.ini configuration |
| `tarpn` | CLI command for operators (`tarpn update`, `tarpn info`, etc.) |
| `statusmonitor.sh` | TNC status monitoring background service |
| `home_background.sh` | TARPN HOME web app launcher |
| `npa.sh` | Neighbor-port-association discovery service |
| `rx_tarpnstat.sh` | TARPNstat receiver service launcher |
| `tarpnmon-runner.sh` | tarpn-mon application launcher |
| `pi_shutdown_background.sh` | Power/shutdown button monitor |
| `logfiletruncate.sh` | Log file size management |
| `update.sh` | `tarpn update` implementation |

### Runtime Services (systemd)

| Service File | Runs | Purpose |
|-------------|------|---------|
| `tarpn-service.txt` | `tarpn_background.sh` | Main orchestrator |
| `home-service.txt` | `home_background.sh` | TARPN HOME web app |
| `statusmonitor-service.txt` | `statusmonitor.sh` | TNC status display |
| `rx_tarpnstat-service.txt` | `rx_tarpnstat.sh` | TARPNstat receiver |
| `neighbor_port_association-service.txt` | `npa.sh` | Neighbor discovery |
| `pi_shutdown-service.txt` | `pi_shutdown_background.sh` | Power button |
| `tarpn-mon-service.txt` | `tarpnmon-runner.sh` | Monitoring app |

---

## 2. 32-bit / Architecture Checks

### 2.1 Explicit 32-bit OS Check -- Severity: Critical

**File**: `w.sh:71-78`
```bash
var=$(file /usr/bin/ls | grep 32-bit | wc -l)
good=1
if [ $var -ne $good ]; then
   echo "##### ERROR 1.1   32-bit not found in OS description"
   exit 1
fi
```

This blocks installation on any 64-bit OS immediately.

### 2.2 32-bit LinBPQ Binary -- Severity: Critical

**File**: `tarpn_start1dl.sh:905`
```bash
latest_bpq_zipfile="bpq_6_0_21_40_mar_2021"
```

The distributed LinBPQ binary (`pilinbpq.dms`) is a 32-bit ARM ELF. On 64-bit
Raspberry Pi OS, this requires armhf multilib support or a 64-bit rebuild from
the G8BPQ GitHub source.

### 2.3 32-bit tarpn-mon Binary -- Severity: Major

**File**: `tarpn_start1dl.sh:1925`
```bash
tarpnget tarpn-mon.linux-arm32.zip
```

The tarpn-mon binary is distributed as a 32-bit ARM build. This is built from
our own codebase and can be cross-compiled for arm64.

### 2.4 32-bit rx_tarpnstatapp Binary -- Severity: Critical

**File**: `tarpn_start2.sh` and `update.sh`
```bash
tarpnget rx_tarpnstatapp.zip
```

The rx_tarpnstatapp is a closed-source 32-bit binary. Source is available
on request from the author.

### 2.5 Other 32-bit Binaries -- Severity: Major

Several additional binaries are distributed as 32-bit only:
- `bbs_checker_bw` (BBS checker application)
- `sendroutestocq` (route broadcasting)
- `linktest` (link testing)
- `listen` (AX.25 listener)
- `g8bpq_link_stress` (link stress tester)

### 2.6 Bypass Mechanism

**File**: `tarpn_start1.sh:346-350`
```bash
if [ -f /usr/tarpn/etc/bypass-platform-checks.txt ];
then
   echo "Platform checks are bypassed"
   _version_ok=1
fi
```

The file `/usr/tarpn/etc/bypass-platform-checks.txt` bypasses both hardware
and OS version checks. However, this only bypasses the *checks* -- the 32-bit
binaries will still fail to execute on a pure 64-bit system.

---

## 3. Hardcoded Paths and Username

### 3.1 "pi" Username Requirement -- Severity: Major

The username "pi" is enforced in four places and assumed everywhere else:

| File | Line | Check |
|------|------|-------|
| `w.sh` | 38 | `if [ $(whoami) != "pi" ]` |
| `tarpn_start1.sh` | 128 | `if [ $(whoami) != "pi" ]` |
| `runbpq.sh` | 83 | `if [ $(whoami) == "pi" ]` |
| `update.sh` | 233 | `if [ $(whoami) != "pi" ]` |

### 3.2 Hardcoded /home/pi Paths -- Severity: Major

The path `/home/pi` is used pervasively across all scripts. A non-exhaustive list:

| File | Lines | Usage |
|------|-------|-------|
| `tarpn_start1.sh` | 53, 123, 143, 157 | `cd /home/pi`, temp file paths |
| `tarpn_start1dl.sh` | 176, 212, 442-452, 503, 549, 568, 746 | Directory checks, cd, file paths |
| `tarpn_start2.sh` | 7, 201 | `cd ~`, symlink creation |
| `tarpn_background.sh` | 75, 340-341 | `NODE_INIT="/home/pi/node.ini"` |
| `runbpq.sh` | 96, 193, 217, 224, 248-249, 383-390 | `cd /home/pi/bpq`, file paths |
| `update.sh` | 244, 282, 327, 422, 456, 531-533, 549, 558, 602 | Throughout |
| `tarpnmon-runner.sh` | 84 | `NODE_INIT="/home/pi/node.ini"` |
| `npa.sh` | 61 | `NODE_INIT="/home/pi/node.ini"` |
| `fix-vnc-headless.sh` | 41 | `TEMP_PARSING_FILE="/home/pi/temp.txt"` |

### 3.3 Hardcoded /usr/tarpn Paths -- Severity: Minor

All scripts use `/usr/tarpn/sbin` and `/usr/tarpn/etc` consistently. This is an
improvement over the prior `/usr/local/sbin` and `/usr/local/etc` convention, but
the paths are still hardcoded rather than derived from a variable.

---

## 4. OS Version Checks

### 4.1 Bookworm Version Check -- Severity: Minor

**File**: `tarpn_start1.sh:378`
```bash
cat /etc/*-release | grep "VERSION" | grep "12 (bookworm)" > $temp_parsing_file
```

This check correctly looks for Debian 12 (Bookworm). It will block installation on
Debian 13 (Trixie) or later when those become available.

### 4.2 Hardware Revision Whitelist -- Severity: Minor

**File**: `tarpn_start1.sh:212-368`

Approximately 35 Raspberry Pi hardware revision codes are explicitly whitelisted
using individual if-statements. New Pi models require a script update to be
supported. The latest addition is Pi 5 `c04170` (4GB model).

This pattern is fragile because each new Pi revision requires a code change.
A better approach would be to parse the revision code format (which encodes
the board type, memory size, and manufacturer) rather than whitelisting
specific values.

---

## 5. Security Concerns

### 5.1 chmod 777 on Application Directories -- Severity: Major

**File**: `tarpn_start1dl.sh:1370`
```bash
sudo chmod 777 home_web_app
```

**File**: `tarpn_background.sh:162-165`
```bash
sudo chmod 777 /tmp/tarpn
sudo chmod 777 /tmp/tarpn/temp
```

**File**: `npa.sh:219,244`
```bash
sudo chmod 777 tnpa
sudo chmod 777 $OURDIR
```

**File**: `runbpq.sh:231`
```bash
sudo chmod 777 Files
```

World-writable directories allow any user or process to modify the contents.

### 5.2 Log Files Created with chmod 666 -- Severity: Minor

**File**: `tarpn_start1dl.sh:266` (and 13 more identical blocks through line 426)
```bash
sudo chmod 666 $START_STOP_LOGFILE
```

**File**: `tarpn_background.sh:199`
```bash
sudo chmod 666 /var/log/tarpn*.log
```

All log files are world-writable.

### 5.3 pip install --break-system-packages -- Severity: Major

**File**: `tarpn_start1dl.sh:231`
```bash
sudo python3 -m pip install --break-system-packages telnetlib3
```

This bypasses the Bookworm system package protection (PEP 668) and installs a Python
package system-wide as root. The standard library `telnetlib` was removed in Python
3.12 (Bookworm ships Python 3.11, but this is future-proofing).

### 5.4 killall python -- Severity: Critical

**File**: `tarpn_background.sh:63`
```bash
sudo killall python
```

**File**: `runbpq.sh:60`, `update.sh:1895`
```bash
sudo killall python
```

This kills ALL Python processes on the system, not just the TARPN HOME process.
Any other Python application running on the system would be terminated.

### 5.5 Service Runs as Root Without User= Directive -- Severity: Major

**File**: `tarpn-service.txt:4-7`
```
[Service]
ExecStart=/usr/tarpn/sbin/tarpn_background.sh
Restart=always
RestartSec=2
```

The systemd unit file does not specify `User=` or `Group=`, so the service runs
as root. The background script then uses `sudo -u pi` to drop privileges for
LinBPQ, but all the surrounding script logic runs as root unnecessarily.

### 5.6 Overwriting System Files -- Severity: Major

**File**: `tarpn_start1dl.sh:1766-1769`
```bash
cp /etc/services /home/pi/services-copy
sudo cat /home/pi/custom-bpq-commands-services.003 >> /home/pi/services-copy
sudo mv /home/pi/services-copy /etc/services
```

**File**: `tarpn_start1dl.sh:1785-1788`
```bash
sudo mv /home/pi/custom-bpq-commands-inetd.005 /home/pi/inetdconf-copy
sudo mv /home/pi/inetdconf-copy /etc/inetd.conf
```

The install script replaces `/etc/inetd.conf` entirely (not appending) and appends
to `/etc/services`.

### 5.7 wget Without Verification -- Severity: Minor

All downloads use `wget -o /dev/null` with no certificate pinning or checksum
verification. The `tarpnget()` function checks for HTML error pages but does not
verify file integrity.

---

## 6. Fragile Patterns

### 6.1 Repeated Function Calls Instead of Loops -- Severity: Major

**File**: `tarpn_background.sh:422-505`
```bash
waste_time_if_not_running 0
waste_time_if_not_running 0
waste_time_if_not_running 0
... (84 total calls)
waste_time_if_not_running 0
```

**File**: `tarpnmon-runner.sh:185-210` (26 calls), `tarpnmon-runner.sh:215-245` (31 calls)

Each `waste_time_if_not_running()` call includes a 5-second sleep, so 84 calls
produces approximately a 7-minute polling delay. Changing the delay would require
adding or removing copy-pasted lines. A simple `for` or `while` loop would suffice.

### 6.2 Copy-Pasted Log File Initialization -- Severity: Major

**File**: `tarpn_start1dl.sh:263-426`

Fifteen identical blocks initialize log files, each following this pattern:
```bash
VARNAME="/var/log/tarpn_something.log"
echo "tarpn-start-installer" > tempname.log
sudo mv tempname.log $VARNAME
sudo chmod 666 $VARNAME
sudo chown root $VARNAME
echo -ne $(date) "" > $VARNAME
echo "Created" $VARNAME >> $VARNAME
```

A single function taking the log file path as a parameter would replace
approximately 160 lines of code with about 15 lines.

### 6.3 Nested Retry Logic Without Loops -- Severity: Minor

**File**: `tarpnget.sh:56-171`

The `tarpnget()` function implements 5 retry attempts using deeply nested
if/else blocks rather than a loop. The `startget()` function in
`tarpn_start1.sh:6-34` has a 3-level version.

### 6.4 Deeply Nested Polling in npa.sh -- Severity: Minor

**File**: `npa.sh:88-137`

Waiting for node.ini to appear is implemented as 6 levels of nested if/else
blocks with `sleep 180` at each level (18 minutes total). Similarly, the
LinBPQ startup check at lines 176-212 is 5 nested levels with `sleep 10`.

### 6.5 Process Check Function Returns Inverted Results -- Severity: Minor

**File**: `tarpn_background.sh:14-18`
```bash
check_process() {
  [ "$1" = "" ]  && return 0
  [ `pgrep -nf $1` ] && return 1 || return 0
}
```

Returns 1 when the process IS running and 0 when it is NOT, opposite of Unix
convention. Defined identically in 4 files: `tarpn_background.sh:14`,
`runbpq.sh:30`, `tarpnmon-runner.sh:3`, `update.sh:40`.

---

## 7. Incomplete Bookworm Migration

### 7.1 Wrong /boot/config.txt Path -- Severity: Critical

On Bookworm, boot configuration moved from `/boot/config.txt` to
`/boot/firmware/config.txt`. The scripts still use the old path:

**File**: `tarpn_start1dl.sh:437`
```bash
sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt
```

**File**: `update.sh:1554`
```bash
sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt
```

On Bookworm, `/boot/config.txt` may exist as a symlink to
`/boot/firmware/config.txt`, in which case `sed` would work. But this is
not guaranteed.

Note: `fix-vnc-headless.sh` correctly handles both paths (lines 49, 57)
by checking the OS version first, suggesting awareness of this issue but
incomplete migration.

### 7.2 Wrong /boot/cmdline.txt Path -- Severity: Major

**File**: `tarpn_start1dl.sh:1101`
```bash
sudo sed -i "s~console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 ~~" /boot/cmdline.txt
```

Same path issue. On Bookworm this should be `/boot/firmware/cmdline.txt`.

### 7.3 Outdated LinBPQ Binary (March 2021) -- Severity: Major

**File**: `tarpn_start1dl.sh:905`
```bash
latest_bpq_zipfile="bpq_6_0_21_40_mar_2021"
```

The LinBPQ binary dates from March 2021 (version 6.0.21.40). The comment history
shows a newer version was briefly used but reverted. Users are running nearly
5-year-old node software.

### 7.4 /temp/tarpn Typo -- Severity: Minor

**File**: `tarpn_background.sh:150`
```bash
sudo rm -rf /temp/tarpn
```

Should be `/tmp/tarpn`. The `/temp` directory does not exist on standard Linux,
so this command silently does nothing. The correct path is used elsewhere.

### 7.5 Bookworm-Specific Version Strings Still Active -- Severity: Minor

Several scripts have been updated for Bookworm but retain version histories
stretching back to Jessie (2015), Stretch (2017), Buster (2019), and Bullseye
(2021). The version strings in headers are current (e.g., `Bookworm053` in
`tarpn_start2.sh`), but the changelog comments span 10+ years of incremental
modifications.

---

## 8. Error Handling

### 8.1 Inconsistent resume_services in update.sh -- Severity: Major

The `update.sh` script defines `resume_services()` at lines 47-84 to restart
all stopped services on error. However, numerous error paths call `exit 1`
WITHOUT calling `resume_services` first:

- `update.sh:237` (wrong user check)
- `update.sh:292` (source URL not found)
- `update.sh:311` (Internet test download fail)
- `update.sh:381` (tarpnget download fail)
- Many error paths in service installation sections (lines 2232, 2257, 2269,
  2300, 2377, 2384, 2436, 2444, 2451)

When these paths are hit, services remain stopped and the node is offline
until manual intervention.

### 8.2 Install Scripts Exit Without Cleanup -- Severity: Major

In `tarpn_start1dl.sh`, all error exits use `exit 1` without any cleanup.
The script may have already modified system files (`/boot/config.txt`,
`/etc/services`, `/etc/inetd.conf`) before the error occurs, leaving
the system in a partially configured state.

### 8.3 File Existence as Download Success Indicator -- Severity: Minor

**File**: `tarpnget.sh:76-77`
```bash
wget -o /dev/null $_source_url/$1
if [ -f $1 ];
```

The wget return code (`$?`) is never examined. A zero-byte file or truncated
download would pass the existence check.

### 8.4 Long Sleeps on Error -- Severity: Minor

Several error conditions introduce long delays before exiting:

| File | Line | Sleep Duration | Condition |
|------|------|---------------|-----------|
| `tarpn_background.sh` | 234 | 180s (3 min) | Source URL not found |
| `runbpq.sh` | 180-181 | 90s | Source URL not found |
| `tarpnmon-runner.sh` | 122 | 900s (15 min) | tarpn-mon executable not found |

Combined with `Restart=always` and `RestartSec=2` in the service files,
these create cycles of long waits followed by restarts.

---

## 9. Process Management

### 9.1 killall Instead of systemctl -- Severity: Major

Despite all services being managed by systemd, the scripts use `killall` and
`check_process` (pgrep) instead of `systemctl stop` and `systemctl is-active`
for runtime process management:

| File | Line | Command | Concern |
|------|------|---------|---------|
| `tarpn_background.sh` | 63, 419 | `sudo killall python` | Kills ALL Python |
| `runbpq.sh` | 60 | `sudo killall python` | Kills ALL Python |
| `update.sh` | 426 | `sudo killall linbpq` | Correct, only one expected |
| `update.sh` | 1585 | `sudo killall rx_tarpnstatapp` | Correct |
| `update.sh` | 1895 | `sudo killall python` | Kills ALL Python |
| `npa.sh` | 312 | `sudo killall rx_tarpnstatapp` | Cross-service kill |

The `update.sh` script does correctly use `systemctl stop` for services
(lines 407-502), but the runtime scripts do not.

### 9.2 Three-Level Nested Kill Retries -- Severity: Minor

**File**: `tarpnmon-runner.sh:12-35`
```bash
stop_tarpnmon() {
    check_process "tarpn-mon"
    if [ $? -ge 1 ]; then
        sudo killall tarpn-mon
        sleep 5
        check_process "tarpn-mon"
        if [ $? -ge 1 ]; then
            sudo killall tarpn-mon
            sleep 5
            ...
```

Three nested levels of kill attempts with 5-second waits. SIGKILL is never
attempted as an escalation.

### 9.3 Polling-Based TARPN HOME Shutdown -- Severity: Minor

**File**: `update.sh:1868-1909`

Stops `tarpn_home.pyc` by deleting a go-flag file, then polling at 5, 20, 40,
60, and 80 seconds. If still running after 80 seconds, calls `killall python`.
This could be replaced by `systemctl stop home.service`.

---

## 10. Redundancy

### 10.1 check_process() Defined in Four Files -- Severity: Minor

The identical (inverted) function is defined in:
- `tarpn_background.sh:14-18`
- `runbpq.sh:30-35`
- `tarpnmon-runner.sh:3-7`
- `update.sh:40-44`

Should be in a shared library sourced by all scripts.

### 10.2 Duplicate Log File Variable Definitions -- Severity: Minor

Log file paths are defined independently in multiple scripts:

| Variable | Defined In |
|----------|-----------|
| `RUNBPQLOG` | tarpn_background.sh, runbpq.sh, tarpnmon-runner.sh |
| `HOME_LOGFILE` | tarpn_background.sh, runbpq.sh, update.sh |
| `TARPN_SERVICE_LOG` | tarpn_background.sh, update.sh |
| `START_STOP_LOGFILE` | tarpn_background.sh, runbpq.sh, tarpnmon-runner.sh |

### 10.3 Duplicate Downloads in Install vs Update -- Severity: Minor

Many files are downloaded in both `tarpn_start1dl.sh` / `tarpn_start2.sh`
(fresh installs) and `update.sh` (updates), with essentially duplicate code:
- `tarpnget.sh`, `sleep_with_count.sh` -- downloaded in all three scripts
- `npa.sh`, `npa.zip` -- installed in both install and update
- Service file installation logic duplicated between install and update

### 10.4 Duplicate tarpn-mon Installation Code -- Severity: Minor

The tarpn-mon setup appears in three places with slightly different logic:
- `tarpn_start1dl.sh:1891-1999` (fresh install)
- `tarpn_start2.sh` (service installation)
- `update.sh:796-999` (update path)

---

## 11. Notable Improvements from Prior Versions

### 11.1 HTTPS Throughout

**File**: `w.sh:17`
```bash
SOURCE_URL=https://tarpn.net/bookworm2024;
```

All source URLs now use HTTPS.

### 11.2 Dedicated /usr/tarpn Directory

Uses `/usr/tarpn/sbin` and `/usr/tarpn/etc` instead of `/usr/local/sbin` and
`/usr/local/etc`, avoiding conflicts with other software.

### 11.3 Pi 5 Support Added

**File**: `tarpn_start1.sh:245`
```bash
_value5B4g="c04170"  #### Raspberry PI 5 Model B 4GB
```

### 11.4 Python 3 Throughout

All Python references use Python 3 packages and `python3` command.
`telnetlib3` replaces the removed stdlib `telnetlib`.

### 11.5 tarpn-mon Integration

WA2M's tarpn-mon monitoring application is now installed as part of
the standard TARPN setup with its own systemd service.

### 11.6 Bypass Platform Checks

The `/usr/tarpn/etc/bypass-platform-checks.txt` file allows bypassing
both hardware and OS version checks for testing.

### 11.7 Log File Truncation

`logfiletruncate.sh` prevents log files from filling the SD card.

### 11.8 tarpnget() Retry Logic

5-attempt retry with HTML error page detection is more robust than
raw `wget` calls in earlier versions.

### 11.9 fix-vnc-headless.sh Handles Both OS Paths

Correctly detects Bullseye vs Bookworm and uses the appropriate
`/boot/` vs `/boot/firmware/` path for cmdline.txt (but this awareness
is not applied consistently to other scripts).

---

## Summary of Issues by Severity

### Critical (blocks functionality or security)

| # | Issue | Section |
|---|-------|---------|
| 1 | 32-bit OS check blocks 64-bit installation | 2.1 |
| 2 | 32-bit LinBPQ binary | 2.2 |
| 3 | 32-bit rx_tarpnstatapp binary | 2.4 |
| 4 | `killall python` kills all Python processes | 5.4 |
| 5 | /boot/config.txt wrong path for Bookworm (may work via symlink) | 7.1 |

### Major (significant impact on reliability, security, or maintainability)

| # | Issue | Section |
|---|-------|---------|
| 1 | 32-bit tarpn-mon binary | 2.3 |
| 2 | Other 32-bit binaries (5 apps) | 2.5 |
| 3 | Hardcoded "pi" username checks | 3.1 |
| 4 | Pervasive /home/pi paths | 3.2 |
| 5 | chmod 777 on directories | 5.1 |
| 6 | pip --break-system-packages | 5.3 |
| 7 | Service runs as root without User= | 5.5 |
| 8 | Overwriting /etc/services and /etc/inetd.conf | 5.6 |
| 9 | 84 copy-pasted waste_time calls instead of loop | 6.1 |
| 10 | 15 copy-pasted log init blocks | 6.2 |
| 11 | /boot/cmdline.txt wrong path | 7.2 |
| 12 | Outdated LinBPQ binary (March 2021) | 7.3 |
| 13 | Inconsistent resume_services in error paths | 8.1 |
| 14 | Install scripts exit without cleanup | 8.2 |
| 15 | killall instead of systemctl for process management | 9.1 |

### Minor (code quality, maintainability)

| # | Issue | Section |
|---|-------|---------|
| 1 | OS version check will block future Debian versions | 4.1 |
| 2 | Hardware revision whitelist requires manual updates | 4.2 |
| 3 | Log files chmod 666 | 5.2 |
| 4 | wget without checksum verification | 5.7 |
| 5 | Nested retry logic without loops | 6.3 |
| 6 | Deeply nested polling in npa.sh | 6.4 |
| 7 | Inverted check_process return convention | 6.5 |
| 8 | /temp/tarpn typo (should be /tmp/tarpn) | 7.4 |
| 9 | File existence as download success indicator | 8.3 |
| 10 | Long sleeps on error conditions | 8.4 |
| 11 | Three-level nested kill retries | 9.2 |
| 12 | Polling-based shutdown instead of systemctl | 9.3 |
| 13 | check_process defined in 4 files | 10.1 |
| 14 | Duplicate log variable definitions | 10.2 |
| 15 | Duplicate install/update code | 10.3, 10.4 |
