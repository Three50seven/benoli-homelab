#!/bin/bash
set -euo pipefail

trap '' PIPE

: "${CRON_FILE:=/app/config/backup.cron}"

echo "[entrypoint] - Previewing supercronic's job schedule from crontab file:"
supercronic -debug "$CRON_FILE" 2>&1 | awk '
  /^# job:/ { job = $0 }
  /^[0-9*]/ { print job "\n" $0 "\n" }
' "$CRON_FILE"

exit 0