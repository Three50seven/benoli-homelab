#!/bin/bash
set -e

CRON_TEMPLATE_FILE="/app/zfs-backup.cron"
SCRIPT_FILE="/app/scripts/zfs-backup-trigger.sh"
: "${CRON_FILE:=/app/config/zfs-backup.cron}"
: "${HEARTBEAT_LOG:=/tmp/heartbeat.log}"

echo "[entrypoint] - Starting entrypoint"

# Verify required binaries exist
for bin in bash supercronic ssh; do
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

# Copy the CRON_TEMPLATE_FILE to the CRON_FILE location:
cat "$CRON_TEMPLATE_FILE" > "$CRON_FILE"

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

echo "[entrypoint] - Found $CRON_FILE.:"

if [ "${DRY_RUN}" = "true" ]; then
    echo "[entrypoint] - Previewing CRON_FILE ($CRON_FILE):"
    cat "$CRON_FILE"
fi

echo "[entrypoint] - Validating cron syntax with supercronic TEST mode for: $CRON_FILE"
if ! supercronic -test "$CRON_FILE"; then
    echo "[entrypoint] - Invalid cron file syntax - refusing to launch. Sleeping indefinitely for debugging purposes."
    sleep infinity
fi

echo "[entrypoint] - Generating an entrypoint heartbeat (first log for healthcheck)"
echo "$(date) healthcheck heartbeat" > $HEARTBEAT_LOG 2>&1

echo "[entrypoint] - Running preview-schedule script:"
"./scripts/preview-schedule.sh"

if [ "$DISABLE_CRON" != "true" ]; then
    echo "[entrypoint] - crontab file syntax looks good and cron is enabled (DISABLE_CRON='$DISABLE_CRON')."
    echo "[entrypoint] - Launching cron scheduler. DRY_RUN is set to $DRY_RUN.  Make sure DRY_RUN is 'false' for the backups to properly execute."
    echo "[entrypoint] - After scheduling, supercronic will wait for the next job to run..."
    supercronic "$CRON_FILE"
else
    echo "[entrypoint] - Cron disabled - sleeping indefinitely for debugging purposes"
    sleep infinity
fi