# Updating

For a node that already has this installed.

## The short version

```bash
cd tarpn-mon
git pull
sudo ./tarpn-node/install.sh
```

That is the whole thing. Your settings are not touched.

## What those two commands do

`git pull` only updates the checkout. The installed copy lives in
`/opt/tarpn`, so `install.sh` has to restage it. That second command:

- restages `/opt/tarpn`, so `tarpnctl` and the module code are current
- re-runs **every module you have installed**, not just the default set, so
  anything you added later is updated too
- re-fetches the programs for your architecture
- restarts services that were running, so a replaced program actually takes
  effect

Services you deliberately stopped stay stopped. `/etc/tarpn/node.conf` and
`tarpn.conf` are never overwritten.

## Checking it worked

```bash
tarpnctl status
tarpnctl doctor
```

## Getting a module added in a newer version

New modules are not installed automatically — updating never adds something
you did not ask for. Update first, then install it:

```bash
cd tarpn-mon && git pull
sudo ./tarpn-node/install.sh
sudo tarpnctl install qtterm
```

The order matters. Modules live in `/opt/tarpn`, so one added in a newer
version does not exist on the node until `install.sh` has restaged the tree.
Asking for it first gives:

```
[XX] no such module: qtterm
     this installation has: core linbpq node-commands routes tarpn-mon
     a module added in a newer version only appears once the tree
     is restaged. From the checkout:
       git pull && sudo ./install.sh
```

`tarpnctl list` shows what is available and what is installed.

## Just the binaries

```bash
sudo tarpnctl update
```

Re-fetches programs for the modules you have installed, without restaging from
git. Use it when only a release has changed. It does not pick up changes to
the scripts themselves — that needs `install.sh`.

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
revision and a reinstall:

```bash
cd tarpn-mon
git log --oneline -10
git checkout <earlier commit>
sudo ./tarpn-node/install.sh
```

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
