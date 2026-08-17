# Updating

For a node that already has this installed.

## The short version

```bash
sudo tarpnctl update
```

That is the whole thing. Your settings are not touched.

You do not need to be in the checkout, and you do not need to remember where
it is — the node recorded that when it was installed.

## What that does

In order:

1. **Refreshes the source checkout** (`git pull --ff-only`), if it is a git
   checkout and has no local edits
2. **Restages `/opt/tarpn`**, so `tarpnctl` and the module code are current
3. **Re-runs every module you have installed**, not just the default set, so
   anything you added later is updated too, and re-fetches the programs for
   your architecture
4. **Regenerates `bpq32.cfg`** from your `node.conf`
5. **Restarts what was running**, once, so replaced programs take effect

Services you deliberately stopped stay stopped. `/etc/tarpn/node.conf` and
`tarpn.conf` are never overwritten.

Step 4 is also the safety check for step 5. `tarpn-linbpq.service`
regenerates its config as it starts, so a `node.conf` that no longer
validates would take the node *down* on restart. Update checks first and
stops before restarting anything, leaving the node up on its previous config:

```
[XX] node.conf does not validate; stopping before anything is restarted
     the node is still running on its previous config
```

## Checking it worked

```bash
tarpnctl status
tarpnctl doctor
```

## Options

| Command | What it does |
|---|---|
| `sudo tarpnctl update` | everything above |
| `sudo tarpnctl update --no-pull` | skip the `git pull`, use the checkout as it is |
| `sudo tarpnctl update <module>...` | refresh just those modules; no config regeneration |
| `sudo tarpnctl update --dry-run` | say what would happen, change nothing |

If the checkout has uncommitted changes, update says so and carries on
without pulling rather than discarding your work:

```
[!!] local changes in /home/pi/tarpn-mon; not pulling
     commit or stash them first, or pass --no-pull to skip this step
```

A failed pull — no network, no upstream branch — is a warning, not an error.
The node still restages from the checkout it has, so an offline node can
always repair itself.

## When you still need install.sh

`tarpnctl update` handles updates. Use `install.sh` for:

- the **first** install on a node
- **changing which modules are installed** (or use `tarpnctl install`)
- a node installed before `tarpnctl update` existed, which will say:

```
[XX] this node does not record where it was installed from
     run the installer once from your checkout to record it:
       sudo /path/to/tarpn-mon/tarpn-node/install.sh
     after that, 'sudo tarpnctl update' is enough
```

## Getting a module added in a newer version

New modules are not installed automatically — updating never adds something
you did not ask for. Update first, then install it:

```bash
sudo tarpnctl update
sudo tarpnctl install qtterm
```

The order matters. Modules live in `/opt/tarpn`, so one added in a newer
version does not exist on the node until the tree has been restaged. Asking
for it first gives:

```
[XX] no such module: qtterm
     this installation has: core linbpq node-commands routes tarpn-mon
```

`tarpnctl list` shows what is available and what is installed.

## Pinning to a specific release

Programs come from the release channel set in `/etc/tarpn/tarpn.conf`:

```ini
RELEASE_BASE_URL=https://tarpn-terminal.s3.us-east-1.amazonaws.com
RELEASE_VERSION=latest
```

Set `RELEASE_VERSION` to a published version to pin to it, then
`sudo tarpnctl update`. Useful for testing a specific build, or holding a node
back.

## Going back

Nothing is versioned automatically, so a rollback is a checkout of the old
revision and a restage:

```bash
cd tarpn-mon
git log --oneline -10
git checkout <earlier commit>
sudo tarpnctl update --no-pull
```

`--no-pull` matters here: without it the update would pull you straight back
to the tip and undo the checkout.

Your configuration is untouched by this, so the node comes back the way it
was. If it is the *programs* rather than the scripts you want to roll back,
pin `RELEASE_VERSION` as above instead.

## Updating on a node with no Internet

Build elsewhere, bring the results with you:

```bash
# on a machine with the toolchain
make build-arm64 build-sendroutesviacq-arm64 build-linktest-arm64
cp dist/*.linux-arm64 tarpn-node/bin/

# copy the tarpn-node directory across, then on the node
sudo ./install.sh
```

Anything in `bin/` named `<component>.linux-<arch>` is used in preference to
the release channel, and is kept so later `tarpnctl update` runs find it too.
