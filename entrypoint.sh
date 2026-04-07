#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# Symlink openclaw config so gateway reads from persistent volume
# (exec-approvals.json uses HOME, not OPENCLAW_STATE_DIR)
rm -rf /home/openclaw/.openclaw
ln -sfn /data/.openclaw /home/openclaw/.openclaw

# Fix plugin ownership — OpenClaw requires root-owned plugin dirs
# (ownership resets to openclaw:openclaw on deploy because /data is chowned above)
chown -R root:root /data/.openclaw/extensions/ 2>/dev/null || true

# Persist QMD cache on /data volume (default ~/.cache/qmd is ephemeral)
# Symlink for both root and openclaw users since QMD may run as either
mkdir -p /data/.qmd-cache
chown openclaw:openclaw /data/.qmd-cache
mkdir -p /root/.cache
ln -sfn /data/.qmd-cache /root/.cache/qmd
mkdir -p /home/openclaw/.cache
ln -sfn /data/.qmd-cache /home/openclaw/.cache/qmd
chown -h openclaw:openclaw /home/openclaw/.cache/qmd

# Set up SSH deploy key for simmer-labs (survives redeploys via env var)
if [ -n "$SIMMER_LABS_DEPLOY_KEY" ]; then
  mkdir -p /home/openclaw/.ssh
  printf '%s\n' "$SIMMER_LABS_DEPLOY_KEY" > /home/openclaw/.ssh/id_simmer_labs
  chmod 600 /home/openclaw/.ssh/id_simmer_labs
  ssh-keyscan github.com >> /home/openclaw/.ssh/known_hosts 2>/dev/null
  chown -R openclaw:openclaw /home/openclaw/.ssh
fi

# Rebuild QMD collections after container restart (best-effort)
QMD="/data/node_modules/.bin/qmd"
if [ -x "$QMD" ]; then
  echo "[entrypoint] Rebuilding QMD collections..."
  gosu openclaw "$QMD" update 2>/dev/null || echo "[entrypoint] QMD update skipped"
fi

# Install Python tooling (uv + simmer-reactor-mcp) on persistent volume.
# Self-heals if /data is wiped (volume recreate, fresh service from template).
# The bookworm runtime image has python3 but no pip/pipx, so we provide our own
# via uv (single static binary). Required for any MCP server shipped as a Python
# package on PyPI — without this, simmer-reactor-mcp can't start and reactor
# auto-react silently fails.
PYTHON_TOOLS_DIR="/data/python-tools"
UV_BIN="$PYTHON_TOOLS_DIR/bin/uv"
REACTOR_MCP_BIN="$PYTHON_TOOLS_DIR/bin/simmer-reactor-mcp"

if [ ! -x "$UV_BIN" ]; then
  echo "[entrypoint] Installing uv to $PYTHON_TOOLS_DIR..."
  mkdir -p "$PYTHON_TOOLS_DIR/bin"
  chown -R openclaw:openclaw "$PYTHON_TOOLS_DIR"
  gosu openclaw bash -c "
    export UV_INSTALL_DIR=$PYTHON_TOOLS_DIR/bin
    curl -LsSf https://astral.sh/uv/install.sh | sh
  " 2>&1 | tail -3 || echo "[entrypoint] uv install failed (non-fatal)"
fi

if [ -x "$UV_BIN" ] && [ ! -x "$REACTOR_MCP_BIN" ]; then
  echo "[entrypoint] Installing simmer-reactor-mcp via uv..."
  gosu openclaw bash -c "
    export UV_TOOL_DIR=$PYTHON_TOOLS_DIR/tools
    export UV_TOOL_BIN_DIR=$PYTHON_TOOLS_DIR/bin
    $UV_BIN tool install simmer-reactor-mcp
  " 2>&1 | tail -3 || echo "[entrypoint] simmer-reactor-mcp install failed (non-fatal)"
fi

# Health check: warn if reactor MCP is configured but binary is missing
if grep -q "simmer-reactor-mcp" /data/.openclaw/openclaw.json 2>/dev/null && [ ! -x "$REACTOR_MCP_BIN" ]; then
  echo "[entrypoint] WARNING: simmer-reactor MCP is configured but $REACTOR_MCP_BIN is missing — auto-react will not fire"
fi

exec gosu openclaw node src/server.js
