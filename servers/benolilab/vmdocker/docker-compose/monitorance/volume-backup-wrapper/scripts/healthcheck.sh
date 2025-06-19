#!/bin/sh
set -e

CRON_FILE="/app/.cron"  # This is where we inject the schedule at runtime
NOW_EPOCH=$(date +%s)

# Extract the next scheduled time from the first line (assumes single job)
NEXT_TIME=$(awk '{ print $1, $2, $3, $4, $5 }' "$CRON_FILE" | \
  xargs -I{} date -d "{}" +%s 2>/dev/null || echo 0)

if [ "$NEXT_TIME" -gt "$NOW_EPOCH" ]; then
  echo "[healthcheck] Next scheduled run is in the future: $(date -d "@$NEXT_TIME")"
  exit 0
else
  echo "[healthcheck] Invalid or past schedule. Check CRON_FILE."
  exit 1
fi