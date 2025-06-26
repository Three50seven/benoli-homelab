#!/bin/bash
set -e
trap '' PIPE

# Inside your cron file or script - setting this to run daily so that it stays within the MAX_AGE - if updating one, make sure to update the heartbeat schecule accordingly
# 0 0 * * * /app/scripts/healthcheck-heartbeat.sh

# check for heartbeat log file
if [ ! -f "$HEARTBEAT_LOG" ]; then
    echo "[healthcheck] HEARTBEAT_LOG does not exist yet."
    exit 1
fi

# In your healthcheck:
LAST_RUN=$(stat -c %Y "$HEARTBEAT_LOG" 2>/dev/null || echo 0)
NOW=$(date +%s)
MAX_AGE=172800  # seconds - if the heartbeat (last run) is older than MAX_AGE, it will be unhealthy

if [ $((NOW - LAST_RUN)) -le $MAX_AGE ]; then
  echo "[healthcheck] supercronic ran at $(date -d "@$LAST_RUN")"
  exit 0
else
  echo "[healthcheck] No recent run detected. Last was at $(date -d "@$LAST_RUN")"
  exit 1
fi