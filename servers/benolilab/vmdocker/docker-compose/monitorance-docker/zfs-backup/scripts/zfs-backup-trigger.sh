#!/bin/bash
set -e

# Get the snapshot type - this will be sent from the Cron job
# Valid options are: daily|weekly|monthly|yearly
SNAP_TYPE="$1"

# Snapshot retention periods
# If zero (0) - a snapshot will not be taken for that period
RETENTION_PERIOD="$2"

# Remove the first two arguments that we've already processed.
# Now, "$@" contains all remaining arguments (e.g., --live, --verbose, etc.)
shift 2

SSH_KEY_PATH="${ZFS_BACKUP_SSH_KEY}"
SSH_USER=$(cat "${ZFS_BACKUP_SSH_USER}")
SSH_HOST=$(cat "${ZFS_BACKUP_SSH_HOST}")

# Verify the snapshot type is not empty and matches a valid type
if [[ -z "$SNAP_TYPE" || ! "$SNAP_TYPE" =~ ^(daily|weekly|monthly|yearly)$ ]]; then
    echo "[zfs-backup-trigger] - Error: Incorrect snapshot type usage: $0 {daily|weekly|monthly|yearly}"
    exit 1
fi

# Verify the snapshot retention period is valid
if [[ "$RETENTION_PERIOD" =~ ^[0-9]+$ ]]; then
    echo "[zfs-backup-trigger] - Info: Retention period (${RETENTION_PERIOD}) is valid."
else
    echo "[zfs-backup-trigger] - Error: Invalid Retention period (${RETENTION_PERIOD}), this must be a number."
    exit 1
fi

# Scan the actual host key fingerprint
ACTUAL_FINGERPRINT=$(ssh-keyscan -t rsa -H "$SSH_HOST" 2>/dev/null | ssh-keygen -lf - | awk '{print $2}')

if [ "$ACTUAL_FINGERPRINT" != "$SSH_ZFS_HOST_FINGERPRINT" ]; then
  echo "[zfs-backup-trigger] - SSH host fingerprint mismatch!"
  echo "Expected: $SSH_ZFS_HOST_FINGERPRINT"
  echo "Actual:   $ACTUAL_FINGERPRINT"
  exit 1
else
  echo "[zfs-backup-trigger] - SSH fingerprint verified."
fi

# DRY_RUN logic
if [ "${DRY_RUN}" = "true" ]; then
    echo "[zfs-backup-trigger] DRY_RUN enabled - testing SSH connectivity ONLY - SNAP_TYPE=${SNAP_TYPE}, RETENTION_PERIOD=${RETENTION_PERIOD}..."
    ssh -v -i "${SSH_KEY_PATH}" "${SSH_USER}@${SSH_HOST}" "echo 'connection succeeded'" \
        && echo "[zfs-backup-trigger] - SSH succeeded" \
        || echo "[zfs-backup-trigger] - SSH failed"
else
    echo "[zfs-backup-trigger] DRY_RUN disabled - executing ZFS backup script remotely - SNAP_TYPE=${SNAP_TYPE}, RETENTION_PERIOD=${RETENTION_PERIOD}, OTHER_OPTIONS=\"${@}\"..."
    # Pass the SNAP_TYPE, RETENTION_PERIOD, and all remaining options ("$@")
    ssh -i "${SSH_KEY_PATH}" "${SSH_USER}@${SSH_HOST}" "${SSH_HOST_SCRIPT_FULL_PATH} ${SNAP_TYPE} ${RETENTION_PERIOD} \"$@\""
fi

# Get next scheduled run:
"./scripts/preview-schedule.sh"