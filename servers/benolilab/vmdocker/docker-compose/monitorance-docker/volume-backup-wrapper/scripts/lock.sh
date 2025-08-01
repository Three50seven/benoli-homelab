#!/bin/bash
trap '' PIPE
# Redirect logging to the docker compose log window so things like echo show in the docker compose logs
exec >> /proc/1/fd/1 2>&1

LOCKFILE="/tmp/docker_backup.lock"
TIMEOUT=600
echo "[LOCK] Acquiring backup lock..."

START=$(date +%s)
while [ -e "$LOCKFILE" ]; do
  [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ] && { echo "[LOCK] Timeout. Exiting."; exit 1; }
  echo "[LOCK] Lock exists, waiting..."
  sleep 5
done

touch "$LOCKFILE"