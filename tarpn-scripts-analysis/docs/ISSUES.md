# TARPN Install Scripts - Issues and Improvement Opportunities

## Overview

This document catalogs bugs, issues, and potential improvements identified in the TARPN installation scripts. The scripts function correctly for their intended purpose on supported hardware, but contain numerous opportunities for improvement in robustness, security, and maintainability.

---

## 1. Shell Scripting Best Practices Violations

### 1.1 Unquoted Variables (Critical - 50+ instances)

Throughout all scripts, variables are used without proper quoting, which can cause word splitting and glob expansion issues.

**Examples:**

```bash
# w.sh:36
if [ $(whoami) != "pi" ]    # Should be: if [ "$(whoami)" != "pi" ]

# w.sh:101
wget $SOURCE_URL/tarpn_start1.sh    # Should be: wget "$SOURCE_URL/tarpn_start1.sh"

# runbpq.sh:256
sudo -u pi wget -o $TEMP_LOG_FILE $_source_url/testfile.txt
# Should be: sudo -u pi wget -o "$TEMP_LOG_FILE" "$_source_url/testfile.txt"
```

**Impact:** Could cause unexpected behavior with paths containing spaces or special characters.

### 1.2 Missing Error Handling (All scripts)

No scripts use proper error handling directives:

```bash
#!/bin/bash
set -e          # Exit on error - MISSING
set -u          # Error on undefined variables - MISSING
set -o pipefail # Fail on pipe errors - MISSING
```

**Impact:** Partial failures can leave systems in inconsistent states.

### 1.3 Deprecated Command Substitution Syntax

**runbpq.sh:33, tarpnmon-runner.sh:6:**
```bash
[ `pgrep -nf $1` ]    # Uses backticks
# Should be:
[ "$(pgrep -nf "$1")" ]    # Modern $() syntax with quoting
```

### 1.4 Non-POSIX Test Constructs

Multiple scripts use `==` inside `[ ]` tests:
```bash
if [ "$var" == "value" ]    # Not POSIX
# Should be either:
if [ "$var" = "value" ]     # POSIX
# Or:
if [[ "$var" == "value" ]]  # Bash-specific with [[
```

---

## 2. Security Issues

### 2.1 Hardcoded Usernames and Paths

All scripts assume:
- Username is `pi`
- Home directory is `/home/pi`
- No support for other usernames or configurations

### 2.2 Overly Permissive File Permissions (15+ instances)

```bash
# tarpn_start1dl.sh - Multiple log files
sudo chmod 666 $LOGFILE    # World writable

# tarpn_start1dl.sh:1380
sudo chmod 777 home_web_app    # World writable AND executable

# runbpq.sh:260
sudo chmod 777 Files    # World writable directory

# runbpq.sh:420
sudo chmod 666 bpq32.cfg    # World writable config file
```

**Recommendation:** Use 644 for files and 755 for directories.

### 2.3 No Download Integrity Verification

Scripts download and execute code without any verification:

```bash
# w.sh:101-108
wget $SOURCE_URL/tarpn_start1.sh
./tarpn_start1.sh    # Executes immediately without verification
```

**Recommendation:** Add checksum verification for downloaded scripts.

### 2.4 Problematic sudo Usage

**tarpn_start2.sh:432-433:**
```bash
sudo echo "text" >> $LOGFILE    # WRONG: echo runs as user, redirect fails
# Should be:
echo "text" | sudo tee -a "$LOGFILE" > /dev/null
```

**runbpq.sh:85:**
```bash
sudo killall python    # Kills ALL python processes, not just target
# Should be more targeted
```

---

## 3. Potential Race Conditions (10+ instances)

### 3.1 Check-Then-Act Patterns

```bash
# tarpnmon-runner.sh:264-273
check_process "tarpn-mon"
if [ $? -ge 1 ]; then
    sleep 10
else
    # Process could have started/stopped between check and action
    sudo -u pi $TARPNMON_EXECUTABLE &
fi
```

### 3.2 File Creation Race Conditions

```bash
# Pattern used throughout:
echo > temp.log
sudo mv temp.log $LOGFILE    # Another process could interfere
```

---

## 4. Code Duplication

### 4.1 Log File Initialization (15+ times)

The same 10-line pattern is repeated for each log file:
```bash
LOGFILE="/var/log/tarpn_something.log"
echo "tarpn-start-installer" > temp.log
sudo mv temp.log $LOGFILE
sudo chmod 666 $LOGFILE
sudo chown root $LOGFILE
echo -ne $(date) "" > $LOGFILE
echo "Created" $LOGFILE >> $LOGFILE
# ...
```

**Recommendation:** Create a function:
```bash
init_log_file() {
    local logfile="$1"
    local desc="$2"
    echo "$desc" > /tmp/init_log.tmp
    sudo mv /tmp/init_log.tmp "$logfile"
    sudo chmod 644 "$logfile"
    sudo chown root:root "$logfile"
}
```

### 4.2 Raspberry Pi Version Checking (42 identical if statements)

**tarpn_start1.sh:193-286:**
```bash
if [ $_value0 == $_countb ]; then _version_ok=1; fi
if [ $_value1 == $_countb ]; then _version_ok=1; fi
# ... 40 more identical statements
```

**Recommendation:** Use an array:
```bash
SUPPORTED_REVISIONS=("000d" "000e" "000f" "a21041" ...)
for rev in "${SUPPORTED_REVISIONS[@]}"; do
    if [[ "$_countb" == "$rev" ]]; then
        _version_ok=1
        break
    fi
done
```

### 4.3 Repeated Function Calls (100+ useless calls)

**tarpnmon-runner.sh:179-223:**
```bash
waste_time_if_node_ini_missing 0
waste_time_if_node_ini_missing 0
waste_time_if_node_ini_missing 0
# ... 42 more times
```

**Recommendation:**
```bash
for i in {1..45}; do
    waste_time_if_node_ini_missing
done
```

### 4.4 Duplicate check_process Function

Identical function defined in both `runbpq.sh` and `tarpnmon-runner.sh`.

**Recommendation:** Move to shared library sourced by both scripts.

---

## 5. Deprecated Practices

### 5.1 Boot Configuration Paths

**tarpn_start1dl.sh:437, 1110:**
```bash
sudo sed -i ... /boot/config.txt
sudo sed -i ... /boot/cmdline.txt
```

On Raspberry Pi OS Bookworm (Debian 12), these files moved to `/boot/firmware/`.

### 5.2 Python 2 References

**tarpn_start1dl.sh:**
```bash
sudo python -m pip install ...        # Python 2
sudo apt-get install python-configparser  # Python 2 package
```

Python 2 is deprecated and removed from newer distributions.

---

## 6. Compatibility Issues

### 6.1 Hardcoded Hardware Revisions

**tarpn_start1.sh:156-190:**

Script contains a whitelist of ~40 Raspberry Pi revision codes. New models (Pi 5, etc.) require script updates to function.

**Recommendation:** Allow bypass flag or use more flexible detection.

### 6.2 OS Version Lock

**tarpn_start1.sh:322:**
```bash
grep "11 (bullseye)"
```

Script only supports Debian 11 "Bullseye". Fails on:
- Debian 12 "Bookworm"
- Any future releases

**Recommendation:** Support version ranges or allow override.

### 6.3 32-bit Only

**w.sh:72-81:**
```bash
var=$(file /usr/bin/ls | grep 32-bit | wc -l)
```

Script explicitly requires 32-bit OS. Many users now run 64-bit Raspberry Pi OS.

---

## 7. Logic Errors

### 7.1 Undefined Function (Critical)

**tarpn_start2.sh:900, 927:**
```bash
resume_services    # Function is never defined!
```

This will cause a command not found error if reached.

### 7.2 Incorrect Exit Code

**tarpn_start1.sh:312:**
```bash
exit 0    # Exits with SUCCESS when hardware is unsupported
# Should be:
exit 1    # Exit with FAILURE
```

### 7.3 Misleading Log Messages

**tarpn_start1dl.sh:471:**
```bash
echo "##### runbpq.sh downloaded successfully"
# But the actual file being downloaded is test_internet.sh
```

### 7.4 File Overwrite Logic Error

**tarpn_start1dl.sh:267-268:**
```bash
# Line 263-266 creates and populates START_STOP_LOGFILE
# Then line 267 overwrites it:
echo -ne $(date) "" > $START_STOP_LOGFILE    # Overwrites previous content!
```

### 7.5 Unused Function Arguments

**tarpnmon-runner.sh:**
```bash
waste_time_if_node_ini_missing 0    # The '0' argument is never used
```

### 7.6 Potential Infinite Loop

**tarpnmon-runner.sh:246:**
```bash
while [ 1 ]; do
    # Only exits via specific exit 0 statements
    # If conditions aren't met, loops forever
done
```

---

## 8. Summary Table

| Category | Count | Severity | Effort to Fix |
|----------|-------|----------|---------------|
| Unquoted Variables | 50+ | High | Medium |
| Missing Error Handling | All | High | Low |
| Security (Permissions) | 15+ | High | Low |
| Security (Downloads) | All | Medium-High | Medium |
| Race Conditions | 10+ | Medium | High |
| Code Duplication | Major | Low | Medium |
| Compatibility | 5+ | Medium | Medium |
| Logic Errors | 8+ | Medium-High | Low |
| Undefined Functions | 2 | Critical | Low |

---

## 9. Recommendations

### Immediate Fixes (Low Effort, High Impact)

1. Fix undefined `resume_services` function in tarpn_start2.sh
2. Correct exit code in tarpn_start1.sh line 312
3. Fix misleading log message in tarpn_start1dl.sh line 471
4. Fix file overwrite logic in tarpn_start1dl.sh line 267

### Short-Term Improvements

1. Quote all variables throughout scripts
2. Add `set -e` and `set -u` to critical scripts
3. Change file permissions from 666/777 to 644/755
4. Fix sudo echo pattern to use tee

### Long-Term Refactoring

1. Create shared function library for common operations
2. Refactor Pi version detection to use array
3. Add download integrity verification (checksums)
4. Support 64-bit OS and newer Debian versions
5. Support non-pi usernames via configuration

---

## 10. Files Analyzed

| File | Lines | Issues |
|------|-------|--------|
| w.sh | 120 | 8 |
| tarpn_start1.sh | 531 | 25+ |
| tarpn_start1dl.sh | ~2000 | 50+ |
| tarpn_start2.sh | ~1000 | 20+ |
| runbpq.sh | 491 | 15+ |
| tarpnmon-runner.sh | 346 | 20+ |

---

*Analysis Date: January 2026*
