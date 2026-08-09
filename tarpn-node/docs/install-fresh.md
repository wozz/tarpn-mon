# Install from scratch

Setting up a node on a machine with nothing on it yet. About five commands and
one config file.

If the machine already runs TARPN, use
[Move an existing node over](MIGRATION.md) instead — it keeps your settings.

## Before you start

You need:

- Raspberry Pi OS or Debian (Bullseye, Bookworm or Trixie; 32- or 64-bit)
- Your NinoTNCs plugged in
- Your callsign, your node name, and the callsign of each neighbour you link to

## 1. Get it

```bash
git clone https://github.com/wozz/tarpn-mon.git
cd tarpn-mon/tarpn-node
```

## 2. Install

```bash
sudo ./install.sh
```

This installs the node engine, monitoring, and the link-quality broadcaster.
It downloads LinBPQ for your machine automatically.

Nothing is running yet, and nothing transmits.

> Want to see what it will do first? `sudo ./install.sh --dry-run`.

## 3. Configure

```bash
sudo tarpnctl config
```

That opens `/etc/tarpn/node.conf` in an editor. The file is commented
throughout, but only six settings are actually required:

```ini
NODE_CALL=N0CALL-2          # your node's callsign, SSID -2 by convention
NODE_NAME=MYNODE            # up to 6 characters, shown in NODES listings
OP_CALL=N0CALL              # your own callsign, no SSID
SYSOP_PASSWORD=changethis   # change it

PORT_A_NEIGHBOR=N1XXX-2     # the neighbour on your first NinoTNC
PORT_A_FRACK=9000           # frame timeout, ms - both ends should agree
```

Add `PORT_B_`, `PORT_C_` and so on for further NinoTNCs, **filling the slots
from A upwards with no gaps**. Slot A is the first NinoTNC, B the second, and
so on in the order Linux enumerates them.

Everything else — position, INFO text, a BBS callsign — is optional and can
wait.

When you save and exit, the settings are checked and applied. If something is
wrong it says exactly what, and nothing is written.

## 4. Start it

```bash
sudo tarpnctl start
```

## 5. Check it

```bash
tarpnctl status
tarpnctl doctor
```

`doctor` inspects the machine and reports anything missing or mismatched.
Then open `http://<the node's address>:8212` for the web interface.

To watch traffic as it happens:

```bash
tarpnctl logs -f
```

Your links will not come up until the neighbouring node is also configured for
you — links are point-to-point, and both ends have to agree.

## Then what

- Add optional pieces — chat, the node-prompt commands, a desktop terminal —
  with [Choose modules](install-modules.md).
- To update later, see [Updating](updating.md).

## If the node has no Internet

Step 2 downloads LinBPQ and the monitoring programs. On a node that cannot
reach the Internet, fetch them on another machine and carry them across —
see [Updating without Internet](updating.md#updating-on-a-node-with-no-internet),
which works the same way for a first install. You will also need a LinBPQ
binary; point `LINBPQ_SOURCE` in `/etc/tarpn/tarpn.conf` at it.

## If something is wrong

`tarpnctl doctor` first; it catches most of it. Beyond that:

| Symptom | Likely cause |
|---|---|
| `no linbpq at ...` | The download failed. `doctor` prints the URL for your architecture. |
| `NODE_CALL is required` | `node.conf` is not filled in yet — `sudo tarpnctl config`. |
| Slot errors about gaps | NinoTNC slots must run A, B, C… with no holes. |
| No `/dev/ttyACM*` devices | The TNCs are not plugged in or not enumerating. |
| Web interface unreachable | `tarpnctl status` — is `tarpn-mon` running? |

Installing does not start anything and does not transmit, so it is safe to
stop at any point and pick it up later.
