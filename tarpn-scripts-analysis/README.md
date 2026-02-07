# TARPN Install Scripts Analysis

This directory contains a comprehensive analysis of the TARPN (Terrestrial Amateur Radio Packet Network) installation scripts and system configuration.

## Purpose

1. **Documentation** - Understand how TARPN systems are installed and configured
2. **Analysis** - Identify bugs, issues, and potential improvements
3. **Reference** - Provide a reference for tarpn-terminal development

## Directory Structure

```
tarpn-scripts-analysis/
├── README.md           # This file
├── scripts/            # Downloaded TARPN scripts
├── docs/               # Analysis documentation
│   ├── INSTALL_FLOW.md     # Installation process flow
│   ├── FILES_AND_DIRS.md   # Files and directories created
│   ├── SERVICES.md         # Systemd services
│   └── ISSUES.md           # Bugs and improvement opportunities
├── services/           # Service file copies
└── configs/            # Configuration file templates
```

## Source

Scripts are downloaded from: `https://tarpn.net/bullseye2021/`

## Script Chain

1. `w` - Bootstrap script (user downloads this)
2. `tarpn_start1.sh` - Environment validation
3. `tarpn_start1dl.sh` - Main installer (~2000 lines)
4. `tarpn_start2.sh` - Post-reboot configuration
5. Various utility scripts installed to `/usr/local/sbin/`

## Analysis Date

January 2026
