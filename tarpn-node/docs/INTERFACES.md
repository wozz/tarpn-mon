# Interfaces

The point of splitting the node into modules is that any one of them can be
replaced. This is what a replacement has to provide.

## Roles

A module declares the role it fills with `PROVIDES` in `module.conf`. Only one
module should provide a given role at a time.

| Role          | Provided by  | Responsibility                          |
|---------------|--------------|-----------------------------------------|
| `node-engine` | `linbpq`     | AX.25 L2, NetROM L3/L4, KISS TNC I/O, applications |
| `monitor`     | `tarpn-mon`  | Packet monitoring, link stats, web UI   |
| `chat`        | `tarpn-chat` | Chat, when `CHAT_PROVIDER=tarpn-chat`   |
| `node-commands` | `node-commands` | Helper commands at the node prompt |

### Adding your own node command

The engine connects out to a `CMDPORT` socket and speaks plain text over it,
so a handler is any program that reads stdin and writes stdout. Add a
`.socket` with `Accept=yes` on a free `CMDPORT` entry, a matching `@.service`
with `StandardInput=socket`, and an `APPLICATION n,NAME,C 32 HOST i S` line
where `i` is that port's index in the `CMDPORT` list.

Handlers should source `modules/node-commands/bin/_cmd-common.sh` for the CRLF
output helper and the callsign-consuming read, and should assume the user is
on a slow, unauthenticated RF link.

## Replacing the node engine

Disable the module and provide your own unit:

```bash
sudo tarpnctl disable linbpq
sudo systemctl stop tarpn-linbpq

# your own unit, WantedBy=tarpn.target and PartOf=tarpn.target
sudo systemctl enable --now my-engine.service
```

`tarpnctl remove linbpq` also works, but keeping the module installed and
merely disabled means `tarpnctl config`, `check` and `apply` still work, since
the config generator lives in that module.

An engine is compatible if it offers the endpoints below. These are what the
generated `bpq32.cfg` configures and what the other components connect to.

### Endpoints

| Port    | Protocol | Used by | Purpose |
|---------|----------|---------|---------|
| `8010`  | Telnet (`TCPPORT`) | `tarpn-mon` | Node, chat and BBS sessions. Applications are selected by command after connect, not by port. |
| `8011`  | Telnet (`FBBPORT`) | `tarpn-mon`, `routes` | Monitor stream: AX.25 frames, TNC status, `[TARPNstat V2]` messages. |
| `7777`  | HTTP (`HTTPPORT`) | operator | LinBPQ's own web admin. Nothing here depends on it. |
| `63000`–`63004` | TCP (`CMDPORT`) | `node-commands` | The engine connects out to these when a user runs `TRR`, `LINUX`, `TINFO` or `LINKTEST`. Loopback only. |

When `CHAT_PROVIDER=tarpn-chat`, the generated config also declares
`NETROMPORT` (default `63119`, set by `NETROM_PORT` in `node.conf`), and
`tarpn-chat` attaches there as its own NetROM node. This requires LinBPQ
6.0.25 or newer; the module checks the binary and warns if it looks older.

### Ports the modules add

| Port   | Bind      | Provided by  | Purpose |
|--------|-----------|--------------|---------|
| `8212` | all       | `tarpn-mon`  | Web UI and the frontend's WebSocket. Compiled in, not configurable. |
| `8513` | 127.0.0.1 | `tarpn-chat` | Client API that `tarpn-mon` consumes. Loopback only. |
| `63119`| 127.0.0.1 | `linbpq`     | `NETROMPORT`, only when `CHAT_PROVIDER=tarpn-chat`. |

### Behaviour

- **Login.** The telnet port prompts with `<op-call>:` and accepts the sysop
  user defined from `OP_CALL` and `SYSOP_PASSWORD`.
- **Monitor format.** `tarpn-mon` parses the LinBPQ monitor format. An engine
  that emits something else needs a matching parser.
- **Restarts are expected.** Consumers must reconnect on their own. Nothing
  may assume the engine is up at its own start time, and nothing should be
  stopped because the engine stopped — that throws away buffered history.

### Configuration

The engine is expected to read `bpq32.cfg` from `BPQ_HOME`. If yours reads a
different format, disable the `linbpq` module and manage its config yourself;
`node.conf` is only meaningful to `tarpn-bpq-genconfig`.

## Files other modules may rely on

| Path | Contract |
|------|----------|
| `/etc/tarpn/tarpn.conf` | `TARPN_USER`, `BPQ_HOME`, release channel. Read-only to modules; only `core` seeds it. |
| `/etc/tarpn/node.conf`  | Node identity and ports. Owned by the operator. |
| `$BPQ_HOME/bpq32.cfg`   | Generated. Never hand-edit; never patch from a watcher. |

A module needing the node's callsign should read `NODE_CALL` from
`node.conf` rather than parsing `bpq32.cfg`.

## Adding a module

```
modules/<name>/
  module.conf         NAME, SUMMARY, VERSION, REQUIRES=core, UNITS, ENABLE
  units/tarpn-<name>.service
  hooks/postinstall   fetch binaries, seed config
```

Units should be `PartOf=tarpn.target` and `WantedBy=tarpn.target`, log to the
journal with a `SyslogIdentifier`, and use `@PLACEHOLDER@` for user and paths.
Do not add `BindsTo=tarpn-linbpq.service` — see "Restarts are expected" above.

`hooks/postinstall` runs with the library loaded; use `install_release_binary`
to fetch a binary for the host architecture, and wrap every mutation in `run`
so `--dry-run` stays honest.
