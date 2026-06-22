#!/usr/bin/env bash
#
# Beszel macOS temperature support (smctemp) — installer / re-apply script.
#
# Builds `smctemp` and a patched `beszel-agent` (this repo) and wires them into
# launchd so the Beszel dashboard shows CPU/GPU temperature on macOS.
#
# Idempotent: safe to re-run. Use it on a fresh machine, or to re-apply after a
# `beszel-agent update` reverts the binary to an upstream build without this
# feature.
#
# Requirements: macOS, Xcode Command Line Tools, Go, git. (Intel & Apple Silicon.)
#
set -euo pipefail

SMCTEMP_REPO="https://github.com/narugit/smctemp.git"
SMCTEMP_BIN="/usr/local/bin/smctemp"
AGENT_BIN="/usr/local/bin/beszel-agent"
ENV_FILE="$HOME/.config/beszel/beszel-agent.env"
PLIST="$HOME/Library/LaunchAgents/dev.henrygd.beszel-agent.plist"
LABEL="dev.henrygd.beszel-agent"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || err "macOS only."

# --- prerequisites -----------------------------------------------------------
xcode-select -p >/dev/null 2>&1 || \
  err "Xcode Command Line Tools required. Run: xcode-select --install"

if ! command -v go >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then log "Installing Go via Homebrew..."; brew install go; \
  else err "Go is required to build the agent (brew install go)."; fi
fi

# --- smctemp (GPL-2.0, kept as a separate binary on purpose) ------------------
if [ -x "$SMCTEMP_BIN" ]; then
  log "smctemp already installed ($("$SMCTEMP_BIN" -v 2>/dev/null || echo '?'))."
else
  log "Building smctemp from source..."
  tmp="$(mktemp -d)"
  git clone --depth 1 "$SMCTEMP_REPO" "$tmp/smctemp"
  make -C "$tmp/smctemp"
  install -m 0755 "$tmp/smctemp/smctemp" "$SMCTEMP_BIN" 2>/dev/null || \
    sudo install -m 0755 "$tmp/smctemp/smctemp" "$SMCTEMP_BIN"
  rm -rf "$tmp"
  log "Installed smctemp -> $SMCTEMP_BIN"
fi
"$SMCTEMP_BIN" -c >/dev/null 2>&1 || \
  log "WARNING: smctemp could not read a CPU temperature yet (this can vary by Mac)."

# --- build & install patched agent -------------------------------------------
log "Building beszel-agent ($(go env GOOS)/$(go env GOARCH)) from $REPO_ROOT ..."
out="$SCRIPT_DIR/.beszel-agent.build"
( cd "$REPO_ROOT" && go build -ldflags "-w -s" -o "$out" ./internal/cmd/agent )

if [ -f "$AGENT_BIN" ]; then
  cp "$AGENT_BIN" "$AGENT_BIN.pre-smctemp.bak"
  log "Backed up existing agent -> $AGENT_BIN.pre-smctemp.bak"
fi
install -m 0755 "$out" "$AGENT_BIN" 2>/dev/null || sudo install -m 0755 "$out" "$AGENT_BIN"
rm -f "$out"
log "Installed patched agent -> $AGENT_BIN"

# --- env configuration -------------------------------------------------------
mkdir -p "$(dirname "$ENV_FILE")"
if [ ! -f "$ENV_FILE" ]; then
  cp "$SCRIPT_DIR/beszel-agent.env.template" "$ENV_FILE"
  log "Created $ENV_FILE from template."
  log "ACTION REQUIRED: edit it and set KEY / TOKEN / HUB_URL from your Beszel hub (\"Add System\")."
fi
if ! grep -q '^SMCTEMP_PATH=' "$ENV_FILE"; then
  printf '\n# macOS SMC temperature support\nSMCTEMP_PATH=%s\nPRIMARY_SENSOR=CPU\n' "$SMCTEMP_BIN" >> "$ENV_FILE"
fi
log "Ensured SMCTEMP_PATH + PRIMARY_SENSOR in $ENV_FILE"

# --- launchd -----------------------------------------------------------------
mkdir -p "$HOME/.cache/beszel"
if [ ! -f "$PLIST" ]; then
  sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/dev.henrygd.beszel-agent.plist.template" > "$PLIST"
  log "Installed launchd plist -> $PLIST"
fi
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true
log "Agent (re)started."

cat <<EOF

Done. Temperatures should appear on your Beszel dashboard within ~1 minute.
  - Verify the binary:   $AGENT_BIN health
  - Watch the log:       tail -f "$HOME/.cache/beszel/beszel-agent.log"
  - Read sensors direct: $SMCTEMP_BIN -c   (CPU °C),   $SMCTEMP_BIN -g   (GPU °C)
EOF
