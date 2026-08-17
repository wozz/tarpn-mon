# Move an existing TARPN node over

Your node keeps its callsign, neighbours, ports and everything else — the
settings are read out of your existing `node.ini`.

Nothing the stock installer created is modified, patched or removed. Until you
disable the legacy services in step 4, nothing has changed and you can walk
away at any point.

## First: are you running the older tarpn-mon/tarpn-chat overlay?

If you ever installed this project's earlier `deploy/install.sh` — the one run
as `curl … /latest/scripts/install.sh | sudo bash`, which puts things in
`/opt/tarpn-mon` and `/opt/tarpn-chat` — remove it **before** installing, and
before anything else in this guide:

```bash
sudo ./deploy/install.sh --uninstall
```

Check with `ls /opt/tarpn-mon /opt/tarpn-chat`, or
`systemctl list-units 'send-routes-via-cq*' 'tarpn-chat-config*'`.

The order is not optional. That overlay uses the same unit names for
`tarpn-mon.service` and `tarpn-chat.service` as this does, so its uninstaller
deletes them by name — run it afterwards and it takes this installation's
units with it. Installing over it without removing it is no better: the two
shared units get quietly taken over while `send-routes-via-cq.timer` keeps
broadcasting link stats alongside the `routes` module, and
`tarpn-chat-config.path` keeps re-patching `bpq32.cfg`.

`install.sh` detects this and stops, so you cannot get it wrong by accident.
Your `bpq32.cfg` and `node.ini` are not touched by the uninstall.

Nothing below is affected by whether you had that overlay.

## The short version

```bash
# 1. keep a copy of the one file you cannot regenerate
cp /home/pi/node.ini ~/node.ini.backup

# 2. install alongside the existing setup, touching nothing
git clone https://github.com/wozz/tarpn-mon.git
cd tarpn-mon/tarpn-node
sudo ./install.sh --alongside

# 3. bring your settings across, and check them
sudo tarpnctl import-node-ini /home/pi/node.ini
tarpnctl doctor

# 4. hand the radios over
sudo systemctl disable --now tarpn.service home.service tarpn_mon.service \
     statusmonitor.service rx_tarpnstat.service neighbor_port_association.service
sudo tarpnctl start

# 5. confirm
tarpnctl status
tarpnctl logs -f
```

Then check from the node itself that `PORTS`, `ROUTES` and `NODES` look the way
they did before. Neighbours reappear as their links re-establish.

**Both stacks must not run at once** — two copies of LinBPQ would fight over
the same USB TNCs, and both would broadcast link statistics. That is what step
4 prevents.

### Going back

Nothing the legacy installer owns was changed, so:

```bash
sudo tarpnctl stop
sudo systemctl disable --now tarpn.target
sudo systemctl enable  --now tarpn.service
```

---

The rest of this document is detail: exactly what gets carried across, what
does not, and the things worth watching. You do not need it to migrate.

## 1. Take stock

```bash
systemctl list-units 'tarpn*' 'home*' 'statusmonitor*' 'rx_tarpnstat*' \
                     'neighbor_port_association*'
cp /home/pi/node.ini ~/node.ini.backup
cp /home/pi/bpq/bpq32.cfg ~/bpq32.cfg.backup
```

Keep the backups. `node.ini` is the only file you cannot regenerate.

## 2. Install alongside, without starting anything

```bash
cd tarpn-mon/tarpn-node
sudo ./install.sh --dry-run
sudo ./install.sh --alongside
```

`--alongside` acknowledges the legacy install and proceeds without touching
it. Without that flag the installer refuses to continue, on purpose.

Nothing is running yet: the units are installed but the node is not started.

## 3. Import the configuration

```bash
sudo tarpnctl import-node-ini /home/pi/node.ini
```

This reads `node.ini`, maps it onto `/etc/tarpn/node.conf`, and validates the
result. The source file is only read.

What it maps:

| `node.ini` | `node.conf` |
|------------|-------------|
| `nodecall`, `nodename` | `NODE_CALL`, `NODE_NAME` |
| `local-op-callsign`, `sysop-password` | `OP_CALL`, `SYSOP_PASSWORD` |
| `latlon`, `ctext`, `infomessage1..8` | `LATLON`, `CTEXT`, `INFO1..8` |
| `bbscall`, `chatcall` | `BBS_CALL`, `CHAT_CALL` |
| `neighborA..J`, `frackA..J` | `PORT_A..J_NEIGHBOR`, `PORT_A..J_FRACK` |
| `usb-port11/12` and friends | `PORT_11/12_*` |

`NOT_SET` becomes empty. `kissoptions:disable` becomes
`PORT_n_KISS_PARAMS=false` — the legacy name is inverted relative to its
meaning.

What it does not carry over, because this installation does not provide it:
TARPN Home, the inetd node commands, and HOST mode. `LEGACY_TARPN_APPS` and
`HOST_MODE` are set to off. See [DESIGN.md](DESIGN.md#what-is-not-ported).

Review the result, then compare the generated config against your current one:

```bash
sudo tarpnctl config
sudo tarpnctl show > /tmp/bpq32.new
diff ~/bpq32.cfg.backup /tmp/bpq32.new
```

Expect differences in the TARPN Home and node-command sections; check that
callsigns, port devices, FRACK values and neighbours match.

## 4. Provide a LinBPQ binary

By default the `linbpq` module downloads the build matching this machine's
userland from G8BPQ's download area, so this step usually happens on its own.
If you would rather reuse the binary already on the node — worth doing if you
are on 32-bit and want the exact version your links are known to work with:

```bash
sudo cp /home/pi/bpq/linbpq /var/lib/tarpn/bpq/linbpq
sudo chown "$(grep '^TARPN_USER=' /etc/tarpn/tarpn.conf | cut -d= -f2)" \
     /var/lib/tarpn/bpq/linbpq
sudo chmod +x /var/lib/tarpn/bpq/linbpq
```

`LINBPQ_SOURCE` in `/etc/tarpn/tarpn.conf` controls this: `auto` (the default)
picks by architecture, or give it a path, a URL, or `none` to manage it
yourself. Re-run `sudo tarpnctl update linbpq` after changing it.

Note that migrating a 32-bit node to a 64-bit OS is a separate step from
migrating the installer. If you move to a 64-bit userland, set
`LINBPQ_SOURCE=auto` so the `pilinbpq64` build is fetched; carrying the old
32-bit binary across will not run.

Capabilities are granted by the unit (`AmbientCapabilities`), so the binary
does not need `setcap` and does not lose privileges when replaced.

## 5. Cut over

```bash
# stop the legacy stack
sudo systemctl disable --now tarpn.service home.service tarpn_mon.service \
     statusmonitor.service rx_tarpnstat.service neighbor_port_association.service

# confirm nothing is holding the radios
pgrep -af linbpq

# start the new one
sudo tarpnctl start
tarpnctl status
tarpnctl logs -f
```

Then check from the node itself that links come up: `PORTS`, `ROUTES` and
`NODES` should look as they did before, and neighbours should reappear as
their links establish.

## Removing this installation

Handing the radios back is the three commands under
[Going back](#going-back) above. To take this installation off the machine
entirely as well:

```bash
sudo ./install.sh --uninstall          # keeps /etc/tarpn and /var/lib/tarpn
sudo ./install.sh --purge              # removes those too
```

## Things to watch

- **Node data.** `BPQNODES.dat` lives in `BPQ_HOME`, which is now
  `/var/lib/tarpn/bpq`, so the new node starts without learned routes and
  relearns them. Copy the file across first if you would rather not wait.
  Note that `tarpn_background.sh` deleted this file on every legacy start, so
  it may not have been carrying much.
- **The `pi` user.** `TARPN_USER` defaults to `pi` when that account exists.
  On an image without it, set `TARPN_USER` in `/etc/tarpn/tarpn.conf` and make
  sure the account is in the `dialout` group.
- **BBS spool and files.** Not migrated. If you run the BBS, copy its
  directories from `/home/pi/bpq/` into the new `BPQ_HOME`.
- **The web interface.** `tarpn-mon` replaces TARPN Home and listens on port
  8212, not TARPN Home's port. Disabling `home.service` is part of step 5
  above; leaving both running means two web interfaces on one node.
- **Chat.** By default chat stays with LinBPQ's built-in `LINCHAT`, exactly as
  before. If you install the `tarpn-chat` module, it takes over: the module
  reads your chat peers out of the old `chatconfig.cfg` into
  `/etc/tarpn/tarpn-chat.toml`, and needs LinBPQ 6.0.25 or newer. Check the
  imported peer list before cutting over.
- **The legacy updater.** If any legacy service is left enabled, `update.sh`
  can still run and rewrite `/home/pi/bpq/bpq32.cfg`. That file is no longer
  the one in use, but leaving the legacy timers enabled is asking for
  confusion.
