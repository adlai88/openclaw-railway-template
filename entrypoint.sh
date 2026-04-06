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

# Persist QMD cache on /data volume (default /root/.cache/qmd is ephemeral)
mkdir -p /data/.qmd-cache
mkdir -p /root/.cache
ln -sfn /data/.qmd-cache /root/.cache/qmd

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

exec gosu openclaw node src/server.js
