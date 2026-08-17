# Choose modules

Everything here is a module. They install, remove and switch off independently,
so you can run only what you want.

```bash
tarpnctl list                    what exists, and what is installed
sudo tarpnctl install <name>
sudo tarpnctl remove  <name>     your settings are kept
```

Removing a module never deletes anything in `/etc/tarpn`, so reinstalling
picks up where you left off.

## The node itself

### `core`
The directory layout, `tarpn.conf`, and the `tarpn.target` group that lets you
start and stop the whole node at once. Everything depends on it and it cannot
be removed.

### `linbpq` — the node engine
LinBPQ, plus generation of `bpq32.cfg` from your `node.conf`. Downloads the
right build for your machine.

Leave this out if something else on the box already runs LinBPQ — see
[running alongside a stock node](DESIGN.md#running-alongside-a-stock-node).

### `tarpn-mon` — monitoring and web interface
Packet monitor, link statistics, and a web interface on port **8212**. Replaces
TARPN Home.

Collecting statistics is local, but it also broadcasts a link-quality summary
on each RF port every 10 minutes and posts a daily BBS bulletin. Both are on by
default and both can be turned off in `/etc/tarpn/tarpn-mon.env`:

```ini
TARPN_MON_STATS_CQ=false
TARPN_MON_STATS_BULLETIN=false
```

### `routes` — link-quality broadcasts
Sends a TARPNstat summary on each RF port every 15 minutes so neighbours can
see both ends of the link. This is the interoperable format every TARPN node
understands.

Leave it out if the legacy `statusmonitor.sh` is still running on the same
machine, or the node will send the same thing twice.

### `npa` — neighbour/port association
Locks each neighbour's route to the port it is actually heard on, every ten
minutes. **Without this the nodes table stays empty**: RF ports are generated
with `IGNOREUNLOCKEDROUTES=1`, so LinBPQ ignores node broadcasts arriving on an
unlocked route, and nothing in the config can lock them — `/dev/ttyACM*`
numbering follows kernel enumeration order, so the neighbour named in slot A is
not reliably on port 1.

If your neighbours are heard but never appear in `NODES`, this is what is
missing. Check with `ROUTES` at the node prompt: locked routes show a `!`.

```bash
sudo tarpnctl install npa
sudo systemctl start tarpn-npa     # run it now instead of waiting
```

To see what it would do without changing anything:

```bash
/opt/tarpn/modules/npa/bin/tarpn-npa --dry-run
```

Leave it out only if the legacy `neighbor_port_association.service` is still
running, or the two will fight over the same routes whenever `node.conf` and
`node.ini` disagree.

## The extras

These are installed by default too. Each is useful only in some setups, so
they are the ones to remove if you do not want them.

### `node-commands` — commands at the node prompt
Restores `TRR`, `TINFO`, `LINKTEST` and `LINUX` for stations that connect to
you.

```bash
sudo tarpnctl install node-commands
sudo tarpnctl apply
```

- **TRR** — link quality per neighbour, both directions. Needs `tarpn-mon` and
  the `sqlite3` package.
- **TINFO** — node diagnostics for whoever is connected.
- **LINKTEST** — sends 100 numbered test frames out a port so a neighbour can
  count what arrives.
- **LINUX** — runs your own scripts from the extensions directory.

It advertises only what it can actually serve, so a command that appears in the
menu will work.

### `tarpn-chat` — chat server
Replaces LinBPQ's built-in chat. Attaches over NetROM as its own node, and
needs **LinBPQ 6.0.25 or newer**.

```bash
sudo tarpnctl install tarpn-chat
sudo tarpnctl apply
```

Installing it switches `CHAT_PROVIDER` in `node.conf` and turns LinBPQ's own
chat off — they cannot both answer on the same callsign. Removing it switches
back.

**Peers.** `tarpn-chat` only connects to the nodes listed under `[[peers]]` in
`/etc/tarpn/tarpn-chat.toml`. With none it attaches to LinBPQ and stops there,
which looks the same as a radio problem. They are filled in for you:

1. from an old `chatconfig.cfg` (`OtherChatNodes`) if there is one, or
2. from the neighbours in `node.conf`, as `<neighbour base call>-9`

The second is a convention, not a fact — edit the file if a neighbour runs no
chat node, or if you reach a chat node further away. It is written on install
and, if the file has no `[[peers]]` at all, topped up by `tarpnctl apply` once
neighbours exist. A peer you delete stays deleted.

`[[known_nodes]]` in the same file is only for showing the right alias for
inbound sessions — putting a peer there does not cause it to be dialled.

Check what it is doing with:

```bash
journalctl -u tarpn-chat | grep "attempt connections to peers"
```

### `qtterm` — QtTermTCP on the node's desktop
For operators who use the node's own screen, over VNC or a monitor.

```bash
sudo tarpnctl install qtterm
```

The stock TARPN installer only ever put a 32-bit QtTermTCP on the desktop,
which is why it stops working on a 64-bit system. This installs the right build
and adds a menu entry.

It is a Qt5 program, so it needs Qt5 libraries. The module reports exactly
which are missing and the `apt install` line for them — use the line it prints,
because the package names differ between Debian releases.

Not needed to run QtTermTCP on another machine pointed at this node.

### `hostmode` — a terminal on the node itself
A `cmd:` prompt into your own node from the node's console, with no network
involved.

```bash
sudo tarpnctl install hostmode
sudo tarpnctl apply
tarpnctl host
```

Needs `minicom` (`sudo apt install minicom`). The stock `tarpn host` used a
patched minicom that chimed through the Pi's speaker on an incoming
connection; stock minicom rings the terminal bell instead, so whether you hear
anything depends on your terminal.

## Turning something off without removing it

```bash
sudo tarpnctl disable tarpn-chat     # stays installed, does not start at boot
sudo tarpnctl stop    tarpn-chat
```

Useful for replacing a component with your own — see
[INTERFACES.md](INTERFACES.md).

## System packages

The installer never runs `apt`. Two optional packages:

```bash
sudo apt install sqlite3      # the TRR command
sudo apt install minicom      # the hostmode module
```

Plus Qt5 libraries if you install `qtterm`, which that module names for you.
Nothing else needs anything a stock system does not already have.
