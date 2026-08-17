# Design

## Principles

1. **systemd owns process lifecycle.** No polling loops, no flag files, no
   `killall`, no semaphores. If something needs to wait for a condition, that
   is a unit dependency or a `Condition*=` directive.
2. **Modules are independent.** Installing, removing or disabling one must not
   require touching another. A module owns its units, its binaries and its
   config, and nothing else.
3. **Configuration belongs to the operator.** Anything under `/etc/tarpn` is
   seeded once and never overwritten. Generated artifacts live elsewhere.
4. **Nothing is patched in place.** This installer never edits a file that
   another installer owns. Where the legacy stack would conflict, it says so
   and stops rather than modifying it.
5. **Fail loudly, early, and without side effects.** Invalid config fails
   validation before anything is written. The legacy `make_local_bpq.sh`
   rebooted the Pi on a config error; this refuses to start and explains why.

## The module contract

A module is a directory under `/opt/tarpn/modules/<name>/`:

```
module.conf         required manifest
units/              systemd units, installed to /etc/systemd/system
bin/                executables, referenced in place by the units
config/             defaults and examples, seeded but never overwritten
templates/          runtime data files
hooks/postinstall   optional, sourced during install
hooks/configure     optional, sourced by `tarpnctl apply`
hooks/preremove     optional, sourced before removal
```

`module.conf` keys:

| Key        | Meaning                                                        |
|------------|----------------------------------------------------------------|
| `NAME`     | Module name, matching the directory                            |
| `SUMMARY`  | One line, shown by `tarpnctl list`                             |
| `VERSION`  | Bumped when the module's units or layout change                |
| `REQUIRES` | Space-separated modules installed first                        |
| `UNITS`    | All units the module owns                                      |
| `ENABLE`   | Subset of `UNITS` enabled at boot; defaults to all of `UNITS`  |
| `REQUIRED` | `true` for modules that cannot be removed (`core`)             |
| `PROVIDES` | Role this module fills, e.g. `node-engine`                     |

`ENABLE` matters where a unit is pulled in by another: `routes` enables only
`tarpn-routes.timer`, because enabling the oneshot service as well would fire
it at boot outside the schedule.

Units may contain placeholders substituted at install time, so that changing
`TARPN_USER` or `BPQ_HOME` does not require hand-editing units (which an
update would then clobber):

`@TARPN_USER@` `@TARPN_GROUP@` `@TARPN_PREFIX@` `@TARPN_ETC@` `@TARPN_STATE@`
`@BPQ_HOME@`

Hooks are *sourced*, not executed, so they inherit the resolved layout, the
logging helpers and `--dry-run` handling without re-deriving any of it. A hook
that mutates the system must wrap the mutation in `run`, or `--dry-run` will
lie.

`configure` exists because modules are installed before the operator has
entered anything: on a fresh node, `node.conf` is still the shipped example
when `tarpn-chat` first runs, so a chat identity derived from it would be
`N0CALL-9` and would never be corrected. `tarpnctl apply` runs `configure` for
every installed module, which is where "make what is running match node.conf"
belongs. It must be idempotent and must not overwrite anything the operator
has edited by hand.

The entire `modules/` tree is staged on disk whether or not a module is
activated, so enabling one later needs neither the network nor the source
checkout. Installed state is recorded in `/var/lib/tarpn/modules/<name>`.

## Replacing the legacy scripts

| Legacy mechanism | Replacement |
|------------------|-------------|
| `while true; do check linbpq; sleep 5; done` | `PartOf=`, `After=`, unit dependencies |
| `waste_time_if_node_ini_missing` × 45 | `ConditionPathExists=` |
| `BACKGROUND:ON` in `background.ini` | `systemctl enable tarpn.target` |
| `/tmp/stop_service_scripts.txt` semaphore | `systemctl stop tarpn.target` |
| `killall npa.sh` | systemd process tracking |
| `check_process "linbpq"` | `systemctl is-active` |
| Per-service `/var/log/tarpn_*.log` + a truncation timer | journald |
| `make_local_bpq.sh` (1078 lines) | `tarpn-bpq-genconfig` |
| `tarpn service start/stop` | `tarpnctl start/stop` → `systemctl` |
| `runbpq.sh` reboots the Pi on config failure | validation failure, service does not start |

`tarpn.target` is the single handle for the node. Services are `PartOf=` it,
so stopping the target stops them; nothing is `BindsTo=` the engine, because
monitoring and chat must survive LinBPQ restarting.

## Config generation

`node.conf` (documented `KEY=value`) replaces `node.ini` (positional
`key:value` with a length check). `tarpn-bpq-genconfig` renders it into
`bpq32.cfg` through `modules/linbpq/templates/boilerplate.cfg`, which is the
stock TARPN template with the changes listed below.

Substitution is a single `awk` pass driven by a name/value map, using
`index()`/`substr()` so both sides are literal text. Doing it with bash
`${var//pat/rep}` takes minutes on a 900-line template; doing it with `sed`
would mean escaping every value against `&`, `/` and backslashes — and values
here include operator-written CTEXT and INFO strings.

The generator validates before writing and refuses to emit a config containing
unresolved `q~token~q` placeholders, then replaces the file atomically.

### AX.25 v2.2 and XID

LinBPQ 6.0.25 advertises AX.25 v2.2, which means it sends **XID** frames at
connect time to negotiate link parameters. A node running an older build does
not answer them, so they are retransmitted until the retry count is exhausted.
With TARPN's usual `FRACK 9000` and `RETRIES 20` that is minutes of airtime
per connection attempt, on a link that gains nothing even when it succeeds.

The generated config therefore sets `OnlyVer2point0=1` by default, which
clears LinBPQ's `SUPPORT2point2` flag and stops the XID frames. `AX25_V22` in
`node.conf` turns it back on once every neighbour on every port also runs
6.0.25 or newer.

Link compression (`L2Compress`, `L4Compress`, also 6.0.25) is a separate
setting and defaults to off in LinBPQ itself — the config struct is zeroed
before parsing and the runtime flags initialise to 0, so omitting the keywords
leaves it disabled. It is exposed as `L2_COMPRESS` and `L4_COMPRESS` anyway,
both defaulting off, because the keywords are otherwise invisible.

Compression cannot be reached without v2.2: the capability is advertised as
XID parameter fields 16 and 17 ("Can Compress", "Compress ok"), and both ends
must have it enabled — the connect handler requires the peer's flag *and* the
local setting before it turns compression on. So it is opt-in on both sides
and cannot be triggered by a neighbour alone.

> All three keywords are new in 6.0.25, but emitting them against an older
> engine is harmless: LinBPQ logs `bpq32.cfg line no N not recognised -
> Ignored` and carries on. An older build does not implement v2.2 in the first
> place, so the default is correct there too. The compression lines are still
> omitted unless enabled, to keep that message out of the log for settings
> that would do nothing.

### Divergences from the stock template

1. **Per-port FRACK is honoured.** The stock template hardcodes `FRACK=9000`
   in all ten NinoTNC port blocks, so `frackA`..`frackJ` in `node.ini` only
   ever appeared in a comment. Those blocks now read the configured value.
2. **Port ID shows the neighbour.** `ID=point to point link` became
   `ID=p2p link to <call>`, matching what ports 11 and 12 already did, so the
   `PORTS` command is readable.
3. **`KISSOPTIONS` is a single token.** The stock template emits
   `XXq~kissoptions11~qXX` and then rewrites `XXenableXX`/`XXdisableXX` in a
   later pass. Collapsed to one token with a directly meaningful value.
4. **TARPN Home and the inetd node commands are gated off** behind
   `LEGACY_TARPN_APPS`, default `false`. See below.
5. **Chat has a provider switch.** `LINCHAT` and `APPLICATION 2,CHAT` are
   gated on `CHAT_PROVIDER`, and a `NETROMPORT` line was added, which the
   stock template does not declare at all. Both are needed so the
   `tarpn-chat` module can take over chat without hand-editing the config.

## Services that depend on the engine

`tarpn-mon` and `tarpn-chat` are ordered `After=tarpn-linbpq.service` but are
deliberately **not** `Requires=`, `BindsTo=` or `PartOf=` it. Only ordering.

This is the one place the legacy design was actively harmful:
`tarpnmon-runner.sh` polled for the `linbpq` process and killed the monitor
whenever it went away, discarding the packet buffer — the thing an operator
most wants to look at after an outage. Both services maintain their own
connections and reconnect on their own, so nothing needs to supervise them.

The same reasoning applies to `tarpnctl apply`: it restarts only the engine,
never the monitor or chat.

## Chat: one provider at a time

LinBPQ's built-in `LINCHAT` and the `tarpn-chat` server would answer on the
same callsign, so `CHAT_PROVIDER` in `node.conf` picks one:

| `CHAT_PROVIDER` | `LINCHAT` | `APPLICATION 2,CHAT` | `NETROMPORT` |
|-----------------|-----------|----------------------|--------------|
| `linbpq`        | on        | on                   | off          |
| `tarpn-chat`    | off       | off                  | on           |

Installing the `tarpn-chat` module sets it to `tarpn-chat`; removing the
module sets it back to `linbpq`. Neither takes effect until `tarpnctl apply`
regenerates `bpq32.cfg` and restarts the engine, and both say so.

`tarpn-chat` attaches to LinBPQ over the NetROM host port as its own node,
rather than being an `APPLICATION` behind the engine. `tarpn-mon` then reaches
it over its local WebSocket API on 127.0.0.1:8513 — not over telnet.

## Settings that belong to the application

`tarpn-mon` persists its own feature settings (chat, BBS, node console) in
`tarpn-mon.json`, and the web UI writes that file at runtime. It only lets an
explicitly-passed command-line flag override the file.

So the unit must not pass those flags: doing so would silently revert whatever
the operator changed in the UI on every restart. The module seeds the file once
at install and never touches it again. `-stats` is the exception — it is a
flag-only toggle in `tarpn-mon` with no stored setting, so the launcher passes
it based on `TARPN_MON_STATS`.

This is why `tarpn-mon` has a small launcher script rather than a bare
`ExecStart`: the callsign is read from `node.conf` at start time, so it cannot
drift from the rest of the node config. The launcher `exec`s — there is no
supervision loop in it.

## What is not ported

These are stock components this installer deliberately does not ship. Each is
a decision, not an oversight.

**TARPN Home** (`home.service`, `tarpn_home.pyc`, `APPLICATION 4/5/6`, the
`/home/pi/minicom/com*` TNCPORTs). Replaced by the `tarpn-mon` module, which
is the reason this fork exists. Emitting the config for it would point LinBPQ
at serial devices this installer never creates. The `tarpn-mon` module warns
if the legacy `home.service` is still enabled, since both want to be the
node's web interface.

`LEGACY_TARPN_APPS` in `node.conf` exists for operators who keep the legacy
pieces installed alongside.

**TCHAT** (`APPLICATION 12`). Superseded by the `tarpn-chat` module, and its
binary is not redistributed here. The other node commands are ported — see
below.

**`rx_tarpnstat`** (`rx_tarpnstatapp`). A closed-source 32-bit ARM binary, and
one of the two blockers for 64-bit support. Not ported as a service, because
it does not need to be a separate process: `tarpn-mon` is already connected to
the monitor stream where those broadcasts appear, already parses them, and now
records them in `link_stats_tarpnstat`. A standalone module would have to open
a second monitor connection to see the same frames.

**Neighbour port association** (`npa.sh`, `neighbor_port_association.app`).
Also a closed-source 32-bit binary. Reading `npa.sh`, the app's outputs are
status files under `/tmp/tarpn/tnpa/` consumed by TARPN Home and the
link-quality reporting scripts — it writes no routes into LinBPQ. On that
reading it is an information source rather than something the node depends on
to route.

The association itself is recoverable without it: every `[TARPNstat V2]`
broadcast is recorded against the port it was heard on, so `link_stats_tarpnstat`
pairs each neighbour callsign with a port. That works for stock TARPN
neighbours too, since they all broadcast it.

> This conclusion comes from reading the wrapper script, not the closed-source
> binary. If a node turns out to depend on NPA for something not visible
> there, it can be added back as an optional module that wraps the legacy
> binary on 32-bit systems.

**`sendroutestocq`.** Replaced by the `routes` module, which runs the portable
Go rewrite in `../sendroutesviacq/` on a systemd timer instead of from inside
`statusmonitor.sh`'s polling loop.

**`pi_shutdown` / GPIO control panel.** Not ported yet. It is genuinely
polling work — button debouncing and LED blinking — so it is the one place the
legacy design is not obviously wrong. Worth a module later; it needs hardware
to test against.

**Minicom, QtTermTCP, desktop wallpaper, Midori, ring tones, `apt` upgrades,
`/forcefsck`, reboots.** Not the installer's business.

## Node commands without inetd

`TRR`, `TINFO`, `LINKTEST` and `LINUX` are `APPLICATION` entries that tell
LinBPQ to connect out to a `CMDPORT` socket. In the stock install, `inetd`
listens on those ports and runs a script per connection with stdin and stdout
wired to the socket.

systemd does this natively. A `.socket` unit with `Accept=yes` plus a
templated `@.service` is exactly `stream tcp nowait`, so the `node-commands`
module needs no inetd, no `/etc/services` edit, and no polling:

```
tarpn-cmd-trr.socket      ListenStream=127.0.0.1:63000, Accept=yes
tarpn-cmd-trr@.service    StandardInput=socket, StandardOutput=socket
```

The `HOST n` index in each `APPLICATION` line is a position in the fixed
`CMDPORT` list, so disabling one command does not renumber the others:

| HOST | Port  | Command    | Status |
|------|-------|------------|--------|
| 0    | 63000 | `TRR`      | reimplemented against tarpn-mon's database |
| 1    | 63001 | `LINUX`    | ported |
| 2    | 63002 | `TCHAT`    | not served — superseded by `tarpn-chat` |
| 3    | 63003 | `TINFO`    | rewritten for this layout |
| 4    | 63004 | `LINKTEST` | wrapper around TARPN's binary, if present |

`NODE_COMMANDS` in `node.conf` lists what to advertise, and the module sets it
to exactly what it can actually serve. An advertised command with nothing
behind it appears in the node menu and then fails, which is worse than not
offering it.

Two improvements over the legacy handlers, both because these are reachable by
any station that can connect to the node:

- They run as `TARPN_USER`, not `root` as the inetd entries did, and the units
  set `RuntimeMaxSec` so a station that disconnects mid-command cannot leave a
  handler running forever.
- `TINFO` no longer prints `hostname -I` and the default route. That is not
  information an unauthenticated connecting station needs.

`LINUX` keeps WA2M's fix for the original path-traversal bug, where answering
`../something` ran a script from outside the extensions directory.

### TRR needed a new data source, and there are two to choose between

The legacy `TRR` is a perl script reading two files this installation does not
produce: `tarpn_home_linkquality.dat` from `rx_tarpnstatapp`, and
`/tmp/tarpn/tnpa/npa_port_*` from the NPA app — both closed-source 32-bit
binaries.

Picking a replacement source means being careful about which of two unrelated
link reports is meant. They are different layers from different commands:

| | `[TARPNstat V2]` | `[LS1]` |
|---|---|---|
| Source | LinBPQ `R R` routes table | LinBPQ `S` command |
| Layer | route / NetROM adjacency | per-port AX.25 L2 |
| Fields | `tx`, `ret`, `buf`, link chevron | rxed, sent, timeouts, REJ, CRC, abandoned, tx%, busy% |
| Broadcast by | `send-routes-via-cq` (`routes` module) | `tarpn-mon` |
| Emitted by stock TARPN nodes | **yes** | no |
| Stored in | `link_stats_tarpnstat` | `link_stats_neighbor` |

`TRR` is the `[TARPNstat V2]` view — its `LOCAL_TRANS_COUNT`,
`LOCAL_RETRY_COUNT`, `LOCAL_BUFFER_WAIT` and `LOCAL_UP_DOWN` map one-to-one
onto `tx`, `ret`, `buf` and the chevron.

Using `[LS1]` for it would have been wrong twice over: wrong layer, and empty
for every neighbour not running this software — which on a real TARPN network
is most of them.

tarpn-mon was already parsing `[TARPNstat V2]` off the monitor stream but only
forwarding it to the WebSocket and Prometheus. It now also records it in
`link_stats_tarpnstat`, keeping the monitor's `R`/`T` direction flag so our own
outgoing broadcast and the neighbour's incoming one can be paired per port.
That is the bilateral view, and it completes what `rx_tarpnstatapp` did.

`tarpn-cmd-trr` queries that table read-only via `sqlite3`. It needs the
`tarpn-mon` module and the `sqlite3` CLI; the module detects both and leaves
`TRR` unadvertised if either is missing.

> The figures are cumulative counters that reset when a node restarts, and
> this has not been compared against the legacy `TRR` on a live node. Do that
> before trusting the numbers. Folding the query into tarpn-mon itself — which
> already holds the database open — would drop the `sqlite3` dependency.

## Running alongside a stock node

The modules are independent enough that `tarpn-mon` can be bolted onto an
otherwise untouched TARPN installation:

```bash
sudo ./install.sh --alongside --modules core,tarpn-mon
```

What that does and does not need:

| | Needed? |
|---|---|
| `linbpq` module | **no** — the legacy stack keeps running LinBPQ |
| A newer LinBPQ | **no** — `S`, `listen` and `CQ` are long-standing commands |
| `NETROMPORT` | **no** — that is only for `tarpn-chat` |
| `tarpn-chat` | **no** |
| `routes` module | **no**, and see the duplicate-broadcast note below |
| `node.conf` | **no** — falls back to the legacy `node.ini` |
| `bpq32.cfg` changes | **no** — stock TARPN already defines `USER=<op>,p,<OP>,,SYSOP`, which is the login the monitor uses |

Deliberately *not* installing `linbpq` is the point: that module owns
`bpq32.cfg` generation, and on a stock node the legacy scripts own it instead.
`tarpnctl status` and `doctor` detect that the module is absent and stop
treating a missing `node.conf` or `linbpq` binary as a fault.

### What stats collection puts on the air

`[LS1]` broadcasts come from `tarpn-mon`'s stats collector, not from the
`routes` module. Enabling stats turns on three things, and two of them
transmit:

| Behaviour | Interval | On the air? |
|-----------|----------|-------------|
| Poll LinBPQ's `S` command | 60s | no, local telnet only |
| `[LS1]` link-stats CQ on every RF port | 10 min | **yes** |
| `SB STATS @` daily BBS bulletin | daily, after midnight | writes to the BBS; see below |

How far the bulletin travels is not this program's decision: it hands a
message to the local BBS, and what happens next is that BBS's forwarding
configuration. TARPN setups generally forward only specific `@<tag>`
designators, so a bare `@` normally stays local — but a BBS configured to
forward it would put it on the air, which is why it is worth being able to
switch off. Both transmitting behaviours can now be turned off independently
while keeping local collection:

```
TARPN_MON_STATS_CQ=false
TARPN_MON_STATS_BULLETIN=false
```

Also note that `[LS1]` (10 min) is separate from and additional to
`[TARPNstat V2]` (15 min). On a stock node the legacy `statusmonitor.sh` is
already sending the latter via `sendroutestocq`, so installing the `routes`
module as well would duplicate it — which is why `routes` is not part of this
selection, and why its install hook warns when it sees the legacy script.

> Unverified: the `S` command output parser was written against a recent
> LinBPQ, and stock TARPN ships 6.0.21.40. The parser matches on line prefixes
> and takes the last N integers per line rather than fixed columns, so it
> should tolerate the difference, but confirm with
> `journalctl -u tarpn-mon` that snapshots are being collected before relying
> on it.

## Platform support

The legacy installer hard-checks for Raspberry Pi OS Bullseye, a 32-bit
userland, a `pi` user, and a whitelist of ~40 Pi board revisions. This one
checks none of that, because none of it is actually load-bearing here.

Everything this repository ships is built to not care about the OS version:

| Component | Build | Depends on |
|-----------|-------|-----------|
| `tarpn-mon`, `send-routes-via-cq` | Go, `CGO_ENABLED=0`, pure-Go SQLite | nothing but the kernel |
| `tarpn-chat` | Rust, static musl targets | nothing but the kernel |
| everything else | bash 4+, coreutils, systemd | see below |

That leaves two real constraints, both checkable with `tarpnctl doctor`:

1. **CPU architecture** — we build `arm32` (armhf), `arm64` and `amd64`.
2. **systemd 242+** — the newest directive used is `RestrictSUIDSGID`.
   Debian 11/12/13 ship 247/252/257, so this never binds in practice.

### Matrix

| OS | 32-bit userland (armhf) | 64-bit userland (arm64 / amd64) |
|----|-------------------------|---------------------------------|
| Bullseye (Debian 11) | supported | supported |
| Bookworm (Debian 12) | supported | supported |
| Trixie (Debian 13) | supported, see t64 note | supported |

64-bit is **not** a gap. G8BPQ publishes a build per architecture, and the
`linbpq` module selects the right one for the userland:

| Userland | Upstream build | Verified as |
|----------|----------------|-------------|
| `arm32` | `Beta/pilinbpq` | ELF 32-bit ARM EABI5 |
| `arm64` | `Beta/pilinbpq64` | ELF 64-bit ARM aarch64 |
| `amd64` | `Beta/linbpq64` | ELF 64-bit x86-64 |

All three were 6.0.25.36 when checked, and all contain the `NETROMPORT`
keyword, so the `tarpn-chat` module's requirement is met on every architecture.

`LINBPQ_SOURCE=auto` (the default) downloads the matching build; a path, a URL,
or `none` override it. Whatever arrives is checked to be an ELF of the right
architecture before it replaces a working binary — via `file(1)` where
available, otherwise by reading the ELF class and machine bytes directly, since
`file` is not on a minimal image.

> The architecture mapping and the version/NETROMPORT check were verified
> against the actual published binaries. Everything else here is an analysis of
> what the code requires, not a report of test runs on each OS — nothing has
> been run on Bullseye, Bookworm or Trixie hardware. `tarpnctl doctor` is there
> to check the real box before you commit to a cutover.

### Notes per release

- **Bullseye** — the stock TARPN target. `sqlite3` is 3.34, which is why the
  TRR query avoids `FULL OUTER JOIN` (needs 3.39+).
- **Bookworm** — images since 2022 no longer create a `pi` user. `TARPN_USER`
  resolves to the invoking user instead, and `core`'s install fails with a
  clear message rather than a cryptic `install: Invalid argument` if the
  configured account does not exist.
- **Trixie** — 32-bit ARM went through the 64-bit `time_t` transition, which
  changes the ABI of the C library and much of what links against it. Our own
  binaries are unaffected (static). A `pilinbpq` built against older armhf
  libraries is the thing most likely to break, and is worth testing before
  moving a live node.

### Nothing stays unavailable on 64-bit

Every 32-bit-only dependency is now gone:

| Original | Status |
|----------|--------|
| `pilinbpq` | never was a blocker — `pilinbpq64` is published |
| `rx_tarpnstatapp` | superseded; tarpn-mon records TARPNstat itself |
| `neighbor_port_association.app` | superseded; the association falls out of `link_stats_tarpnstat` |
| `sendroutestocq` | replaced by the Go `send-routes-via-cq` |
| `trr` (perl) | replaced by `tarpn-cmd-trr` |
| `linktest` | replaced by the Go `linktest` (see below) |

### linktest

TARPN's `linktest` is a 13 KB C program (`transmit_test.c`) distributed only
as a 32-bit ARM binary, so it was the last thing that could not run on a
64-bit node. `linktest/` in this repository is a portable reimplementation,
recovered by disassembling version 9. What it does:

1. connect to the LinBPQ telnet port
2. read the login prompt and take the callsign back out of it — the node is
   configured with `LOGINPROMPT=<callsign>:`, so the program never needs to be
   told who it is
3. send that as the username, then `p` as the password
4. `lis <port>` to attach to the requested radio port
5. send 100 `CQ` frames two seconds apart, each an 82-byte payload holding a
   sequence number and a rolling window over a fixed pangram

The sequence numbers are the whole point: a neighbour monitoring the port sees
which of `test00`..`test99` arrived, and the gaps measure the link.

The wire protocol was verified end to end against a mock node — login
exchange, `lis`, and all 100 frames byte-for-byte as derived. Deliberate
differences from the original, all marked `DIFFERENCE` in the source:

- defaults to `127.0.0.1` rather than the Debian-specific `127.0.1.1`, and the
  host, port, count and interval are settable
- read deadlines instead of a bare blocking `recv()`, which could hang forever
  if the node went quiet
- rejects a non-numeric or out-of-range port instead of quietly sending
  `lis 0` and transmitting nothing

The argument handling is unchanged, so `linktest <port> NOPRINT` still behaves
as TARPN's scripts expect.

## Open questions

- **LinBPQ on 64-bit.** No prebuilt 64-bit `pilinbpq` is published; it has to
  be built from source. The `linbpq` module does not redistribute the binary —
  it takes a path or URL, and warns when the binary's architecture does not
  match the userland, which is the most common failure when moving off the
  32-bit image.
- **Locked routes.** The template sets `IGNOREUNLOCKEDROUTES=1` on every RF
  port. How locked routes are established for NinoTNC ports on a fresh node
  needs confirming against a live node before this is relied on.
