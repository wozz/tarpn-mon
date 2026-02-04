# TARPN Scripts: Bookworm and 64-bit Compatibility Analysis

This document identifies specific blockers preventing TARPN from running on Debian 12 "Bookworm" and 64-bit Raspberry Pi OS.

---

## Executive Summary

| Blocker | Severity | Fix Complexity |
|---------|----------|----------------|
| **Explicit 32-bit OS check** | Critical | Trivial (remove check) |
| **Explicit Bullseye version check** | Critical | Trivial (update check) |
| **LinBPQ 32-bit binary** | Critical | Needs 64-bit build from upstream |
| **rx_tarpnstatapp 32-bit binary** | Critical | Needs 64-bit build or armhf compat |
| **Boot config paths** | High | Simple path update |
| **Python 2 packages** | Medium | Already mostly Python 3 |
| **Hardcoded Pi revision codes** | Medium | Bypass exists |
| **Hardcoded username 'pi'** | Low | Pervasive but not blocking |

**Bottom line**: The scripts themselves are easy to fix. The real blockers are the 32-bit ARM binaries: LinBPQ and rx_tarpnstatapp.

---

## Critical Blockers

### 1. Explicit 32-bit OS Requirement

**File**: `w.sh:72-81`
```bash
####### Verify that we are on a 32-bit OS
var=$(file /usr/bin/ls | grep 32-bit | wc -l)
good=1
if [ $var -ne $good ]; then
   echo "##### ERROR 1.1   32-bit not found in OS description"
   echo "#####     TARPN scripting and executables require a 32-bit OS."
   echo "####  abort"
   exit 1
fi
```

**Fix**: Remove this check entirely, or make it a warning with bypass option.

**Why it exists**: The LinBPQ binary distributed (`bpq_6_0_21_40_mar_2021.zip` containing `pilinbpq.dms`) is compiled for 32-bit ARM.

---

### 2. Explicit Bullseye Version Check

**File**: `tarpn_start1.sh:321-334`
```bash
cat /etc/*-release | grep "VERSION" | grep "11 (bullseye)" > $temp_parsing_file
if grep -q "VERSION" $temp_parsing_file;
then
   echo -n "Linux ok: "
else
   echo -e "\n\nERROR!  This script does not support the Linux version"
   exit 1
fi
```

**Also in**: `tarpn:561`
```bash
cat /etc/*-release | grep --text "VERSION" | grep --text "11 (bullseye)" > $TEMP_PARSE_FILE
```

**Fix**: Update to accept `12 (bookworm)` as well, or remove the check.

**Bypass exists**: Both scripts check for `/usr/local/etc/bypass-platform-checks.txt`:
```bash
if [ -f /usr/local/etc/bypass-platform-checks.txt ];
then
   echo "Platform checks are bypassed"
   _version_ok=1
fi
```

---

### 3. LinBPQ 32-bit Binary

**File**: `tarpn_start1dl.sh:903-904`
```bash
latest_bpq_zipfile="bpq_6_0_21_40_mar_2021"
latest_bpq_file="pilinbpq.dms"
```

**This is the real blocker**. The TARPN scripts download a pre-compiled 32-bit ARM binary of LinBPQ. On a 64-bit OS, this binary won't run natively.

**Options**:
1. **Check if G8BPQ provides 64-bit builds** - The [LinBPQ GitHub](https://github.com/g8bpq/linbpq) has source code
2. **Use multiarch** - 64-bit Raspberry Pi OS can run 32-bit binaries with `armhf` libraries
3. **Compile from source** - Build LinBPQ for aarch64

**Note**: G8BPQ's official releases at https://www.cantab.net/users/john.wiseman/Downloads/Beta/ may have 64-bit versions.

---

### 4. rx_tarpnstatapp 32-bit Binary

**File**: `update.sh:1711-1712`
```bash
tarpnget rx_tarpnstatapp.zip
```

**Binary analysis**:
```
rx_tarpnstatapp: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV),
dynamically linked, interpreter /lib/ld-linux-armhf.so.3, for GNU/Linux 3.2.0
```

This is a compiled C program that:
- Queries LinBPQ for ROUTES statistics (NBOUR_IFRAMES, NBOUR_RETRIES, queue depth)
- Broadcasts stats as CQ/UI frames: `[TARPNstat V2]~CALLSIGN~>~txINT~retINT~bufINT~`
- Enables bilateral link quality monitoring across the network

**Options for 64-bit**:
1. **armhf compatibility layer** - Same as LinBPQ, install 32-bit libs
2. **Request source from maintainer** - Source is available on request, could be recompiled for aarch64
3. **Replace with open-source alternative** - Could reimplement the functionality:
   - Query LinBPQ via telnet for ROUTES stats
   - Broadcast in same format for compatibility

**Note**: Unlike LinBPQ (which has source on GitHub), rx_tarpnstatapp source must be requested from the TARPN maintainer.

---

## High Severity Issues

### 5. Boot Configuration Paths

**File**: `tarpn_start1dl.sh:437`
```bash
sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt
```

**File**: `tarpn_start1dl.sh:1106-1110`
```bash
echo "##### Remove config for having tty-async-serial as console port from /boot/cmdline.txt"
sudo sed -i "s~console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 ~~" /boot/cmdline.txt
```

**File**: `update.sh:1649`
```bash
sudo sed -i "s^enable_uart=0^enable_uart=1^" /boot/config.txt
```

**Bookworm Change**: On Raspberry Pi OS Bookworm, boot files moved:
- `/boot/config.txt` → `/boot/firmware/config.txt`
- `/boot/cmdline.txt` → `/boot/firmware/cmdline.txt`

**Fix**: Check which path exists:
```bash
if [ -f /boot/firmware/config.txt ]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
else
    BOOT_CONFIG="/boot/config.txt"
fi
```

---

## Medium Severity Issues

### 6. Python 2 Package References

**File**: `tarpn_start1dl.sh:1458-1466`
```bash
echo "##### APT-GET install of python-configparser"
sudo apt-get install -y python-configparser
sudo apt-get install -y python-configparser

echo "##### APT-GET install of python-tornado"
```

**File**: `update.sh:1655-1672`
```bash
echo "##### checking for python-configparser"
dpkg-query -W -f='${binary:Package} ${Version}\t${Maintainer}\n' python-configparser | wc -l
```

**Bookworm**: Python 2 packages removed. `python-configparser` doesn't exist.

**Note**: The actual TARPN Home application already uses Python 3:
```bash
# home_background.sh:341
python3 tarpn_home.pyc
```

**Fix**: Remove Python 2 package installation attempts. They'll fail gracefully anyway on Bookworm.

---

### 7. Hardcoded Raspberry Pi Revision Codes

**File**: `tarpn_start1.sh:156-191` (40+ revision codes)
```bash
_value0="000d"     #### Red B+ Chinese
_value1="000e"
# ... 35+ more codes
_value4BF="d03115"   #### Raspberry Pi 4 Model B Rev 1.5 8GB

# Then 40+ individual if statements to check each one
if [ $_value0 == $_countb ]; then _version_ok=1; fi
if [ $_value1 == $_countb ]; then _version_ok=1; fi
# ...
```

**Missing**: Raspberry Pi 5 revision codes

**Bypass exists**: The `/usr/local/etc/bypass-platform-checks.txt` file bypasses this check.

**Better fix**: Use a more flexible detection method or whitelist approach:
```bash
# Check for any Pi 4 or Pi 5
if [[ $_countb =~ ^[a-d]0[0-9][0-9][0-9][0-9]$ ]]; then
    _version_ok=1
fi
```

---

## Low Severity Issues

### 8. Hardcoded Username 'pi'

**Files**: All scripts assume:
- Username: `pi`
- Home directory: `/home/pi`
- Files like `/home/pi/node.ini`, `/home/pi/bpq/`

**Example** (`w.sh:36-42`):
```bash
if [ $(whoami) != "pi" ]; then
   echo "ERROR:  Hello user " $(whoami);
   echo "ERROR:  The TARPN start scripts will fail if the user name is not 'pi'."
   exit 1
fi
```

**Note**: Raspberry Pi Imager now allows custom usernames, but defaults to `pi`. Most TARPN users will continue using `pi`.

**Fix** (long-term): Use `$USER` and `$HOME` instead of hardcoded paths.

---

## tarpn-mon/tarpn-terminal Independence

You correctly noted that tarpn-mon (our replacement, tarpn-terminal) **should not depend on linbpq**:

**Current behavior** (`tarpnmon-runner.sh:260-275`):
```bash
check_process "linbpq"
if [ $? -ge 1 ]; then    # linbpq IS running
    check_process "tarpn-mon"
    if [ $? -ge 1 ]; then
        sleep 10
    else
        sudo -u pi $TARPNMON_EXECUTABLE &   # Start tarpn-mon
    fi
else                      # linbpq NOT running
    # Kill tarpn-mon!
    sudo killall tarpn-mon
fi
```

**Problems with this approach**:
1. Kills tarpn-mon when linbpq stops, losing all buffered data
2. tarpn-mon/tarpn-terminal can reconnect on its own
3. Creates unnecessary coupling

**For tarpn-terminal**: Our service should be completely independent:
```ini
[Unit]
Description=TARPN Terminal
After=network.target
# NO BindsTo=linbpq.service - we handle reconnection ourselves

[Service]
Type=simple
User=pi
ExecStart=/usr/local/sbin/tarpn-terminal -call N0CALL -host localhost
Restart=always
RestartSec=5
```

---

## Recommended Fixes for Bookworm/64-bit Support

### Minimal Changes (Works Today)

1. **Create bypass file**:
   ```bash
   sudo touch /usr/local/etc/bypass-platform-checks.txt
   ```

2. **Use 32-bit Raspberry Pi OS** (works on Pi 4/5 hardware)

3. **Install armhf libraries for 64-bit OS**:
   ```bash
   sudo dpkg --add-architecture armhf
   sudo apt update
   sudo apt install libc6:armhf
   ```

### Script Changes Needed

| File | Line(s) | Change |
|------|---------|--------|
| `w.sh` | 72-81 | Remove 32-bit check or make it a warning |
| `tarpn_start1.sh` | 321-334 | Accept Bookworm version string |
| `tarpn_start1dl.sh` | 437 | Use `/boot/firmware/config.txt` if exists |
| `tarpn_start1dl.sh` | 1110 | Use `/boot/firmware/cmdline.txt` if exists |
| `tarpn_start1dl.sh` | 1458-1466 | Remove Python 2 package installs |
| `update.sh` | 1649 | Use `/boot/firmware/config.txt` if exists |
| `tarpn` | 561 | Accept Bookworm version string |

### LinBPQ 64-bit

The critical question is whether G8BPQ provides a 64-bit ARM build. Options:
1. Check https://www.cantab.net/users/john.wiseman/Downloads/Beta/ for aarch64 builds
2. Build from source at https://github.com/g8bpq/linbpq
3. Continue using 32-bit OS (still fully supported on Pi 4/5)

---

## Summary

**What's blocking Bookworm**:
- Hardcoded version string check (trivial fix)
- Boot config file paths (simple fix)
- Python 2 package attempts (harmless failures)

**What's blocking 64-bit**:
- Explicit 32-bit check in `w.sh` (trivial to remove)
- 32-bit LinBPQ binary (needs upstream 64-bit build or armhf compatibility layer)
- 32-bit rx_tarpnstatapp binary (same - needs recompile or armhf compat)

**The bypass exists today**: Creating `/usr/local/etc/bypass-platform-checks.txt` skips most checks. The remaining issues are the boot paths and 32-bit binary architecture (LinBPQ + rx_tarpnstatapp).

---

*Analysis Date: January 2026*
