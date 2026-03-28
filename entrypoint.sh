#!/bin/bash
set -e

chown -R openclaw:openclaw /data
chmod 700 /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# Set up SSH deploy key for simmer-labs (survives redeploys via env var)
if [ -n "$SIMMER_LABS_DEPLOY_KEY" ]; then
  mkdir -p /home/openclaw/.ssh
  printf '%s\n' "$SIMMER_LABS_DEPLOY_KEY" > /home/openclaw/.ssh/id_simmer_labs
  chmod 600 /home/openclaw/.ssh/id_simmer_labs
  ssh-keyscan github.com >> /home/openclaw/.ssh/known_hosts 2>/dev/null
  chown -R openclaw:openclaw /home/openclaw/.ssh
fi

exec gosu openclaw node src/server.js
