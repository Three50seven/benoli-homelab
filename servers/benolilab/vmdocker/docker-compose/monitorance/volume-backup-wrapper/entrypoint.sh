#!/bin/sh
set -e

CRON_TEMPLATE_FILE="/app/backup.cron"
CRON_FILE="/app/config/backup.cron"
SCRIPT_FILE="/app/scripts/run-backup.sh"

echo "[entrypoint] - Starting entrypoint"

# Verify required binaries exist
for bin in bash supercronic envsubst; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[entrypoint] - Required command not found: $bin"
    exit 1
  fi
done

# Wait for cron file
until [ -f "$CRON_TEMPLATE_FILE" ]; do
  echo "[entrypoint] - Waiting for $CRON_TEMPLATE_FILE to exist..."
  sleep 1
done

# Make sure the backup schedule is set and validate its format (rudimentary check - not bulletproof):
if [ -z "$BACKUP_SCHEDULE" ]; then
  echo "[entrypoint] - BACKUP_SCHEDULE environment variable is not set"
  exit 1
fi

if ! echo "$BACKUP_SCHEDULE" | grep -Eq '^[0-9\*\/,-]+\s+[0-9\*\/,-]+\s+[0-9\*\/,-]+\s+[0-9\*\/,-]+\s+[0-9\*\/,-]+$'; then
  echo "[entrypoint] - BACKUP_SCHEDULE doesn't appear to be a valid cron expression"
  exit 1
fi

# Render environment variables into final cron file
envsubst < "$CRON_TEMPLATE_FILE" > "$CRON_FILE"

if [ -n "$(tail -c1 "$CRON_FILE")" ]; then
  echo "[entrypoint] - Cron file missing trailing newline — appending."
  echo >> "$CRON_FILE"
fi

# Sanity check: backup script must exist and be executable
if [ ! -x "$SCRIPT_FILE" ]; then
  echo "[entrypoint] - Script missing or not executable: $SCRIPT_FILE"
  ls -l "$SCRIPT_FILE"
  exit 1
fi

# Optional: Validate CRON_FILE syntax (if using supercronic)
echo "[entrypoint] - Found $CRON_FILE. Previewing jobs:"
cat "$CRON_FILE"

if [ "$DISABLE_CRON" != "true" ]; then
  echo "[entrypoint] - Launching cron scheduler"
  exec supercronic "$CRON_FILE"
else
  echo "[entrypoint] - Cron disabled - sleeping indefinitely for debugging purposes"
  sleep infinity
fi