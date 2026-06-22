# macOS temperature support for the Beszel agent (via smctemp)

On macOS the Beszel agent reports no temperatures: it relies on gopsutil's
sensors package, whose Darwin implementation is a no-op, so there is no
Temperature card. This adds CPU/GPU temperature on macOS by reading the Apple
SMC through [`smctemp`](https://github.com/narugit/smctemp).

## How it works

The agent selects its temperature source at compile time with Go build tags:

| File | Build tag | Source |
| --- | --- | --- |
| `agent/sensors_default.go` | `!windows && !darwin` | gopsutil (Linux/BSD) |
| `agent/sensors_windows.go` | `windows` | shells out to a LibreHardwareMonitor helper |
| `agent/sensors_darwin.go`  | `darwin`  | **shells out to `smctemp`** (new) |

`agent/sensors_darwin.go` runs `smctemp -c` (CPU) and `smctemp -g` (GPU) and
maps the results into the existing `Stats.Temperatures` map, so the data flows
through the normal `SENSORS` / `PRIMARY_SENSOR` filtering and renders on the
dashboard with **no hub or frontend changes**.

`smctemp` is run as a **separate process on purpose**: it is GPL-2.0 while Beszel
is MIT, so keeping it at arm's length avoids mixing the licenses in one binary.
This mirrors how the Windows build shells out to an external helper.

### Configuration

| Env var | Purpose |
| --- | --- |
| `SMCTEMP_PATH` | Absolute path to the `smctemp` binary. Required under launchd, whose `PATH` excludes `/usr/local/bin`. |
| `PRIMARY_SENSOR` | Sensor that drives the All Systems table temperature (`CPU` or `GPU`). |
| `SENSORS` | Standard Beszel whitelist/blacklist, e.g. `CPU` or `-GPU`. |

### Limitations

- **Temperature only.** `smctemp` does not read fan RPM, and Beszel has no fan
  field, so fans are not reported.
- Requires building the agent from source (the feature is not in upstream
  releases yet) and having `smctemp` installed on the machine.

## Install / re-apply

```sh
./contrib/macos-smctemp/setup.sh
```

The script is idempotent. It will:

1. Check prerequisites (Xcode CLT, Go).
2. Build & install `smctemp` to `/usr/local/bin/smctemp` (if missing).
3. Build this repo's `beszel-agent` and install it to `/usr/local/bin/beszel-agent`
   (backing up any existing binary to `*.pre-smctemp.bak`).
4. Ensure `SMCTEMP_PATH` + `PRIMARY_SENSOR` are set in
   `~/.config/beszel/beszel-agent.env` (creating it from a template if needed —
   you must fill in `KEY` / `TOKEN` / `HUB_URL` from your hub).
5. Install the launchd plist (if missing) and (re)start the agent.

### When do I need to re-run it?

Only when something overwrites the binary with an upstream build that lacks this
feature — chiefly `beszel-agent update` or re-running Beszel's official
installer. Restarts, reboots, and config edits do **not** require re-running.
(A Homebrew upgrade does not affect it: neither binary is brew-managed.)

## Update Beszel and keep temperatures (`update.sh`)

Do **not** run `beszel-agent update` — it replaces the binary with a stock
upstream build that drops this feature. Instead, run:

```sh
./contrib/macos-smctemp/update.sh
```

It fetches upstream, rebases this feature branch onto the latest `upstream/main`,
fast-forwards your fork's `main`, then rebuilds + reinstalls the patched agent
and pushes the branch — giving you the newer Beszel version *and* temperatures in
one step. Requires a clean tree on the feature branch with an `upstream` remote
(`git remote add upstream https://github.com/henrygd/beszel.git`). If the rebase
hits a conflict (usually `agent/sensors_default.go`), it aborts cleanly and tells
you how to resolve it.

## Verify

```sh
beszel-agent health                 # -> ok
smctemp -c                          # CPU °C
tail -f ~/.cache/beszel/beszel-agent.log
# With LOG_LEVEL=debug you'll see:  DEBUG Temperature sensors=[{CPU ..} {GPU ..}]
```

## Uninstall / rollback

```sh
cp /usr/local/bin/beszel-agent.pre-smctemp.bak /usr/local/bin/beszel-agent  # restore stock agent
launchctl kickstart -k gui/$(id -u)/dev.henrygd.beszel-agent                # restart
# then remove SMCTEMP_PATH / PRIMARY_SENSOR from ~/.config/beszel/beszel-agent.env
# and optionally: rm /usr/local/bin/smctemp
```
