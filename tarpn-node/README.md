# tarpn-node

A modular, systemd-based way to install and run a TARPN packet node.

An independent alternative to the stock `w` installer from tarpn.net. It runs
the same kind of node — LinBPQ driving NinoTNCs over RF — but as separately
installable pieces managed by systemd, and it never modifies an existing TARPN
installation.

---

## Start here

**What are you trying to do?**

| | Go to |
|---|---|
| Set up a node on a machine that has nothing on it yet | **[Install from scratch](docs/install-fresh.md)** |
| Set up a node on a Pi that already runs TARPN | **[Move an existing node over](docs/MIGRATION.md)** |
| Already have this installed, want the latest version | **[Update](docs/updating.md)** |
| Add or remove individual pieces | **[Choose modules](docs/install-modules.md)** |

Most people want one of the first two. Both are about five commands and one
config file.

If you are not sure whether it will run on your hardware, install it and run
`tarpnctl doctor` — it checks the machine and tells you what, if anything, is
missing.

---

## What you get

| Module | What it does | Installed by default |
|---|---|---|
| `core` | Directory layout and the `tarpn.target` service group | always |
| `linbpq` | The node engine, and `bpq32.cfg` generated from your settings | yes |
| `tarpn-mon` | Monitoring and a web interface on port 8212 | yes |
| `routes` | Broadcasts link quality to neighbours every 15 minutes | yes |
| `node-commands` | `TRR`, `TINFO`, `LINKTEST`, `LINUX` at the node prompt | no |
| `tarpn-chat` | Chat server, replacing LinBPQ's built-in one | no |
| `qtterm` | QtTermTCP on the node's own desktop, for VNC users | no |
| `hostmode` | A terminal into the node from the node's own console | no |

Each one can be installed, removed or switched off on its own without
disturbing the rest. See [Choose modules](docs/install-modules.md).

## Everyday commands

```
tarpnctl status                 how the node is doing
tarpnctl doctor                 check the machine, report anything missing
tarpnctl logs -f                follow the logs

sudo tarpnctl config            edit settings, then apply them
sudo tarpnctl start|stop|restart
sudo tarpnctl install|remove <module>
```

Everything accepts `--dry-run`, which changes nothing and shows what it would
do.

## Configuration

Two files, both in `/etc/tarpn`, and neither is ever overwritten by an update:

- **`node.conf`** — your node: callsign, name, neighbours, ports. This is the
  one you edit.
- **`tarpn.conf`** — the installation: which user runs it, where things live.
  Mostly leave alone.

`bpq32.cfg` is generated from `node.conf`. Edit `node.conf` and run
`sudo tarpnctl apply`; changes made directly to `bpq32.cfg` are overwritten.

Where things live:

| Path | What |
|---|---|
| `/etc/tarpn/` | Your settings. Never overwritten by an update. |
| `/opt/tarpn/` | The installed programs and modules. |
| `/var/lib/tarpn/bpq/` | The engine's working directory, including the generated `bpq32.cfg`. |
| `journalctl -u tarpn-*` | Logs. There are no log files to rotate. |

## Supported systems

Raspberry Pi OS or Debian — **Bullseye, Bookworm or Trixie, 32-bit or 64-bit**
— and x86-64 Linux. There is no check on OS version, board revision or whether
the user is called `pi`, because none of that matters here.

Details, including a caveat about 32-bit Trixie, are in
[docs/DESIGN.md](docs/DESIGN.md#platform-support).

## Status

The code is complete and tested on a development machine, and the config
generation path is tested end to end. **It has not yet been run on a live node
against real radios.** Keep your existing installation available to fall back
to until your links come up.

## Reference

| Document | What is in it |
|---|---|
| [docs/install-fresh.md](docs/install-fresh.md) | Setting up a new node |
| [docs/MIGRATION.md](docs/MIGRATION.md) | Moving an existing TARPN node over |
| [docs/updating.md](docs/updating.md) | Updating an installation |
| [docs/install-modules.md](docs/install-modules.md) | The optional pieces |
| [docs/DESIGN.md](docs/DESIGN.md) | How it works and why, and what was left out |
| [docs/INTERFACES.md](docs/INTERFACES.md) | Replacing a component with your own |
