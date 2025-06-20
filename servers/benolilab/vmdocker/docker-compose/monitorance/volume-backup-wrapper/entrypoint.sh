#!/bin/bash
set -e

CRON_TEMPLATE_FILE="/app/backup.cron"
SCRIPT_FILE="/app/scripts/run-backup.sh"
: "${CRON_FILE:=/app/config/backup.cron}"
: "${HEARTBEAT_LOG:=/tmp/heartbeat.log}"

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
    echo "[entrypoint] - Cron file missing trailing newline - appending."
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

echo "[entrypoint] - Validating cron syntax for: $CRON_FILE"
if ! supercronic -test "$CRON_FILE"; then
    echo "[entrypoint] - Invalid cron file syntax - refusing to launch. Sleeping indefinitely for debugging purposes."
    sleep infinity
fi

echo "[entrypoint] - Generating an entrypoint heartbeat (first log for healthcheck)"
echo "$(date) healthcheck heartbeat" > $HEARTBEAT_LOG 2>&1

if [ "$DISABLE_CRON" != "true" ]; then
    echo "[entrypoint] - crontab file syntax looks good and cron (DISABLE_CRON) is enabled."
    echo "[entrypoint] - Launching cron scheduler. DRY_RUN is set to $DRY_RUN.  Make sure DRY_RUN is 'false' for the backups to properly execute."
    echo "[entrypoint] - After scheduling, supercronic will wait for job to run..."
    supercronic "$CRON_FILE"
else
    echo "[entrypoint] - Cron disabled - sleeping indefinitely for debugging purposes"
    sleep infinity
fi