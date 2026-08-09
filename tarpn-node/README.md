# tarpn-node

A modular, systemd-native installation method for TARPN packet nodes.

This is an independent alternative to the stock `w` installer from tarpn.net.
It installs the same kind of node — LinBPQ driving NinoTNCs over RF — but as a
set of separately installable modules managed by systemd, instead of a tree of
shell scripts that poll each other through flag files.

It does not modify, patch or depend on an existing TARPN installation.

## Why

The stock installer works, but it is difficult to build on:

- Installation is a chain of scripts downloaded and executed at runtime, across
  two reboots, with no versioning and no way to install part of it.
- Roughly 2,500 lines of shell reimplement things systemd does natively:
  polling loops that wait for `linbpq`, `sleep` calls repeated dozens of times
  in sequence, flag files for enable/disable, `killall` for shutdown.
- Updates overwrite the whole tree, so local changes do not survive and
  swapping out a component is not possible.
- The install is pinned to 32-bit Raspberry Pi OS Bullseye and the user `pi`.

See [`../tarpn-scripts-analysis/`](../tarpn-scripts-analysis/) for the analysis
this is based on.

## Three ways in

**Monitoring only, on an otherwise stock node** — the smallest step. Installs
`tarpn-mon` beside the existing TARPN stack without touching it: the legacy
services keep running LinBPQ, and nothing regenerates `bpq32.cfg`.

```bash
sudo ./install.sh --alongside --modules core,tarpn-mon
sudo tarpnctl start tarpn-mon
```

No `node.conf` is needed — the operator callsign is read from the legacy
`/home/pi/node.ini`. This is also what enables `[LS1]` link-stats broadcasts;
see [docs/DESIGN.md](docs/DESIGN.md#running-alongside-a-stock-node) for what
that puts on the air.


**Converting an existing TARPN node** — nothing the stock installer owns is
modified, so this is reversible until you disable the legacy services. See
[docs/MIGRATION.md](docs/MIGRATION.md).

**Starting from scratch** — install, configure, go. You supply a `linbpq`
binary (it is third-party and not redistributed here) and fill in
`node.conf`; there is no interactive wizard equivalent to `tarpn config` yet.

Either way, `tarpnctl doctor` tells you whether this host can run everything
before you commit.

## Getting it onto a node

`install.sh` runs from a directory containing this tree, so any way of getting
the directory there works. It is not a `curl | bash` script and does not want
to be one — it stages a whole tree and you should be able to read it first.

```bash
git clone https://github.com/wozz/tarpn-mon.git
cd tarpn-mon/tarpn-node && sudo ./install.sh
```

### Updating

Two commands, from the checkout:

```bash
git pull
sudo ./install.sh
```

`git pull` only updates the checkout; `/opt/tarpn` is a copy, so `install.sh`
has to restage it. That second command then:

- restages `/opt/tarpn` from the checkout, so `tarpnctl` and the module code
  are current
- re-runs the hooks for **every module already installed**, not just the
  default set, so anything added later (`qtterm`, `node-commands`,
  `tarpn-chat`) is updated too
- re-fetches binaries from the release channel
- restarts services that were already running, so a replaced binary actually
  takes effect — services that were deliberately stopped stay stopped

`sudo tarpnctl update` does the same for the installed modules without
restaging from git; use it when only the binaries need refreshing.

Only the shell tree comes from git. The binaries are fetched separately from
`RELEASE_BASE_URL` in `tarpn.conf`, because they cannot be built on a node —
`tarpn-mon` embeds a frontend that needs npm, and `tarpn-chat` needs a Rust
musl toolchain.

### QtTermTCP on the node's desktop

The stock TARPN installer puts a **32-bit** QtTermTCP on the Pi desktop, so it
stops working on a 64-bit image. G8BPQ publishes a build per architecture and
the `qtterm` module installs the right one, adds a menu entry, and checks the
Qt5 libraries it needs:

```bash
sudo tarpnctl install qtterm
```

Only needed if someone uses the node's own desktop, over VNC or a monitor.
Running QtTermTCP on another machine and pointing it at the node over the
network needs nothing installed here.

Unlike everything else, QtTermTCP is a dynamically linked Qt5 application, so
it needs Qt5 runtime libraries. The module reports exactly which are missing
and the `apt install` line for them — the package names differ between Debian
releases because of the 64-bit `time_t` transition, so it resolves them
against your system rather than assuming.

### A terminal on the node itself

HOST mode gives the operator a `cmd:` prompt into their own node from the
node's console, over a pseudo-terminal rather than the network:

```bash
sudo tarpnctl install hostmode
sudo tarpnctl apply        # adds the console port, restarts the engine
tarpnctl host              # or: tarpn-host
```

The stock equivalent is `tarpn host`, which runs `piminicom` - stock minicom
plus a one-line patch playing a sound file on the terminal bell - against
`/home/pi/minicom/com8`. Only a 32-bit ARM build of that is published, so it
stops working on a 64-bit image.

This module uses stock `minicom` from Debian and puts the console device in
`BPQ_HOME`. The one thing not carried over is that audible chime on an
incoming connection: `cbell on` still rings the terminal bell, but whether
that makes a sound is up to the terminal.

### Optional system packages

The installer does not run `apt`. One optional package is worth knowing about:

```bash
sudo apt install sqlite3      # only needed for the TRR node command
sudo apt install minicom      # only needed for the hostmode module
```

`TRR` reads tarpn-mon's statistics database through the `sqlite3` CLI, which
Debian does not install by default. Without it everything else works and the
`node-commands` module simply does not advertise `TRR`. Nothing else here
needs a package that is not already on a stock system.

### Offline installation

For a node with no Internet, build elsewhere and bring the binaries with you:

```bash
make build-arm64 build-sendroutesviacq-arm64 build-linktest-arm64
cp dist/*.linux-arm64 tarpn-node/bin/
# copy the tarpn-node/ directory to the node, then:
sudo ./install.sh
```

Anything in `bin/` named `<component>.linux-<arch>` is used in preference to
the release channel, and is staged so that later `tarpnctl update` runs find
it too. Nothing contacts the network except LinBPQ itself, which you can also
supply via `LINBPQ_SOURCE=/path/to/linbpq`.

## Supported platforms

| OS | 32-bit (armhf) | 64-bit (arm64 / amd64) |
|----|----------------|------------------------|
| Bullseye (Debian 11) | yes | yes |
| Bookworm (Debian 12) | yes | yes |
| Trixie (Debian 13) | yes | yes |

Unlike the stock installer, there is no OS-version, board-revision or `pi`-user
check — nothing here needs them. Our binaries are static (Go with
`CGO_ENABLED=0`, Rust with musl), so the OS release does not matter; the
requirements are a supported CPU architecture and systemd 242+, which Debian 11
already exceeds.

LinBPQ is published per architecture and the installer picks the right one
(`pilinbpq` for armhf, `pilinbpq64` for arm64, `linbpq64` for x86-64), then
verifies the ELF architecture before installing it. Nothing else is
architecture-bound: the last 32-bit-only piece, TARPN's `linktest`, has been
reimplemented portably in `../linktest/`. See
[docs/DESIGN.md](docs/DESIGN.md#platform-support) for the Trixie `time_t`
caveat.

## Quick start

```bash
git clone https://github.com/wozz/tarpn-mon.git
cd tarpn-mon/tarpn-node

sudo ./install.sh --dry-run     # see exactly what it would do
sudo ./install.sh               # install core + linbpq + routes

sudo tarpnctl config            # edit node.conf, validate, apply
sudo tarpnctl start             # bring the node up
tarpnctl status
```

Converting an existing TARPN node instead of configuring from scratch:

```bash
sudo tarpnctl import-node-ini /home/pi/node.ini
```

## Modules

| Module       | What it provides                                        | Default |
|--------------|---------------------------------------------------------|---------|
| `core`       | Directory layout, `tarpn.conf`, the `tarpn.target` group | always  |
| `linbpq`     | LinBPQ engine and `bpq32.cfg` generation from `node.conf`| yes     |
| `routes`     | TARPNstat link-quality broadcast every 15 minutes        | yes     |
| `tarpn-mon`  | Monitoring backend and web UI on :8212, replaces TARPN Home | yes  |
| `tarpn-chat` | NetROM chat server, replaces LinBPQ's built-in LINCHAT   | opt-in  |
| `node-commands` | `TRR`, `TINFO`, `LINKTEST`, `LINUX` at the node prompt | opt-in |
| `qtterm`     | QtTermTCP on the node's own desktop, for VNC/local users | opt-in |
| `hostmode`   | Terminal into the node from its own console (HOST mode)  | opt-in |

`tarpn-chat` is not installed by default because it takes chat away from
LinBPQ and needs LinBPQ 6.0.25 or newer for `NETROMPORT`. Add it with
`sudo ./install.sh --all` or `sudo tarpnctl install tarpn-chat`; installing it
sets `CHAT_PROVIDER=tarpn-chat` in `node.conf`, and removing it sets that back.
Either way, run `sudo tarpnctl apply` afterwards.

Modules are independent. Each one owns its systemd units and its own config,
and can be installed, removed, enabled or disabled without touching the rest:

```bash
tarpnctl list
sudo tarpnctl install routes
sudo tarpnctl remove  routes      # config in /etc/tarpn is kept
sudo tarpnctl disable linbpq      # run your own engine instead
```

`node-commands` restores the helper commands a connecting station sees at the
node prompt. The stock install serves these through `inetd`; this uses systemd
socket activation instead, which is the same "run a handler per connection
with stdin/stdout on the socket" model without inetd. It advertises only what
it can actually serve — `TRR`, for instance, needs `tarpn-mon` plus `sqlite3`.

```bash
sudo tarpnctl install node-commands
sudo tarpnctl apply            # advertise them at the node prompt
```

Feature toggles inside `tarpn-mon` (chat, BBS, node console) live in its own
settings file and are edited through the web UI, not here. The module seeds
them once at install and then leaves them alone.

## Layout

| Path                        | Contents                                        |
|-----------------------------|-------------------------------------------------|
| `/opt/tarpn/`               | Installed program tree: `lib/`, `bin/`, `modules/` |
| `/etc/tarpn/tarpn.conf`     | Installation settings: user, paths, release channel |
| `/etc/tarpn/node.conf`      | Node configuration: callsign, ports, neighbours |
| `/etc/tarpn/tarpn-mon.env`  | Optional overrides for the monitor service      |
| `/etc/tarpn/tarpn-chat.toml`| Chat node identity and peers                    |
| `/var/lib/tarpn/bpq/`       | LinBPQ working directory, **generated** `bpq32.cfg` |
| `/var/lib/tarpn/mon/`       | `linkstats.db`, `chat.db`, `tarpn-mon.json`     |
| `/var/lib/tarpn/chat/`      | tarpn-chat working directory                    |
| `/etc/systemd/system/`      | `tarpn.target`, `tarpn-*.service`, `tarpn-*.timer` |

Configuration under `/etc/tarpn` is owned by the operator: it is seeded once
and never overwritten by an update, and it survives removing a module.

`bpq32.cfg` is a generated artifact. Edit `node.conf` and run `tarpnctl apply`;
direct edits to `bpq32.cfg` are overwritten on the next start.

## Commands

```
tarpnctl status                 node and module state
tarpnctl start|stop|restart     whole node, or a single module
tarpnctl enable|disable         start at boot, or not
tarpnctl logs [module] [-f]     journalctl, no log files to truncate

tarpnctl config                 edit node.conf, validate, apply
tarpnctl check                  validate without changing anything
tarpnctl apply                  regenerate bpq32.cfg and restart what needs it
tarpnctl show                   print the generated bpq32.cfg

tarpnctl list                   available and installed modules
tarpnctl install|remove|update  manage modules
```

Everything accepts `--dry-run`.

## What this does not do

Deliberately, and in contrast to the stock installer:

- No reboots, no `apt-get dist-upgrade`, no desktop wallpaper, no browser.
- No downloading and executing shell scripts at runtime.
- No watching for file changes to re-patch a config someone else regenerated.
- No editing of any existing TARPN script.
- No polling loops or flag files. Dependencies and conditions are systemd's.

Components the stock installer ships that this one does not, and why, are
listed in [`docs/DESIGN.md`](docs/DESIGN.md#what-is-not-ported).

## Status

The base is implemented and the config generation path is tested end to end
(legacy `node.ini` → `node.conf` → `bpq32.cfg`) on a development machine.
**It has not yet been run on a live node against real radios.** Install with
`--dry-run` first, and keep the legacy installation available to roll back to
until you have confirmed your links come up.

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/DESIGN.md](docs/DESIGN.md) | Module contract, systemd mapping, what was dropped |
| [docs/INTERFACES.md](docs/INTERFACES.md) | The contract for replacing a component |
| [docs/MIGRATION.md](docs/MIGRATION.md) | Moving an existing node over |
