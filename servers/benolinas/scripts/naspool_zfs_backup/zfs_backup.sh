#!/bin/bash

# ZFS Backup Script with Disk Space Monitoring, Logging, Retention Period & Discord Notifications

# Set the source pool
SOURCE_POOL="naspool"

# Log files
LOG_FILE="/var/log/zfs_backup.log"
DISK_USAGE_LOG="/var/log/zfs_disk_usage.log"

# Detect the active backup pool
# This will only grab the first match for a pool name that contains "naspool_backup". If both naspool_backup1 and naspool_backup2 are available, it will only grab the first pool it encounters in the list, which could be either naspool_backup1 or naspool_backup2, depending on the order in which they are listed by zpool list.
BACKUP_POOL=$(zpool list -H -o name | grep "naspool_backup")

# Discord Webhook URL (Replace with your actual webhook)
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"

# Minimum required free space in GB
WARNING_THRESHOLD=100  # Send a warning if below this
CRITICAL_THRESHOLD=50  # Stop backup if below this

# Snapshot retention period (days)
RETENTION_DAYS=7  # Retention period for snapshots (adjust as needed)

# Function to send a Discord notification
send_discord_notification() {
    MESSAGE=$1
    curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$MESSAGE\"}" $DISCORD_WEBHOOK_URL
}

# Log start of backup
echo "$(date) - Starting ZFS backup" | tee -a $LOG_FILE

# Exit if no backup pool is found
if [ -z "$BACKUP_POOL" ]; then
    ERROR_MSG=":x: **Backup Failed:** No backup pool detected! Insert a backup disk."
    echo "$(date) - $ERROR_MSG" | tee -a $LOG_FILE
    send_discord_notification "$ERROR_MSG"
    exit 1
fi

# Check available space on the backup pool (convert bytes to GB)
FREE_SPACE_BYTES=$(zfs list -H -o available $BACKUP_POOL | awk '{print $1}')
FREE_SPACE_GB=$(numfmt --from=iec $FREE_SPACE_BYTES | awk '{print $1 / 1073741824}')

# Log disk usage to file
echo "$(date), $BACKUP_POOL, ${FREE_SPACE_GB}GB free" | tee -a $DISK_USAGE_LOG

# Send a warning if space is low
if [ "$(echo "$FREE_SPACE_GB < $WARNING_THRESHOLD" | bc -l)" = "1" ]; then
    WARNING_MSG=":warning: **Low Disk Space Warning:** Only ${FREE_SPACE_GB}GB free on **$BACKUP_POOL**."
    echo "$(date) - $WARNING_MSG" | tee -a $LOG_FILE
    send_discord_notification "$WARNING_MSG"
fi

# Stop the backup if space is critically low
if [ "$(echo "$FREE_SPACE_GB < $CRITICAL_THRESHOLD" | bc -l)" = "1" ]; then
    ERROR_MSG=":x: **Backup Stopped:** Critical disk space alert! Only ${FREE_SPACE_GB}GB free on **$BACKUP_POOL**."
    echo "$(date) - $ERROR_MSG" | tee -a $LOG_FILE
    send_discord_notification "$ERROR_MSG"
    exit 1
fi

# Get today's date
DATE=$(date +"%Y%m%d")
SNAPSHOT_NAME="backup_$DATE"

# Create snapshot
echo "$(date) - Creating snapshot: $SOURCE_POOL@$SNAPSHOT_NAME" | tee -a $LOG_FILE
if ! zfs snapshot -r $SOURCE_POOL@$SNAPSHOT_NAME 2>>$LOG_FILE; then
    ERROR_MSG=":x: **Backup Failed:** Could not create snapshot **$SNAPSHOT_NAME**"
    send_discord_notification "$ERROR_MSG"
    exit 1
fi

# Send snapshot to backup pool
echo "$(date) - Sending snapshot to $BACKUP_POOL" | tee -a $LOG_FILE
if ! zfs send -R $SOURCE_POOL@$SNAPSHOT_NAME | zfs receive -F $BACKUP_POOL 2>>$LOG_FILE; then
    ERROR_MSG=":x: **Backup Failed:** Could not send snapshot to **$BACKUP_POOL**"
    send_discord_notification "$ERROR_MSG"
    exit 1
fi

# Delete old snapshots (based on configurable retention)
echo "$(date) - Deleting snapshots older than $RETENTION_DAYS days..." | tee -a $LOG_FILE
SNAPSHOTS=$(zfs list -H -t snapshot -o name | grep "$SOURCE_POOL@backup_" | head -n -$RETENTION_DAYS)
for SNAP in $SNAPSHOTS; do
    echo "$(date) - Destroying old snapshot: $SNAP" | tee -a $LOG_FILE
    if ! zfs destroy -r $SNAP 2>>$LOG_FILE; then
        ERROR_MSG=":x: **Backup Failed:** Could not delete old snapshot **$SNAP**"
        send_discord_notification "$ERROR_MSG"
    fi
done

# Send success message
send_discord_notification ":tada: **Backup Completed Successfully!**"
echo "$(date) - Backup process complete!" | tee -a $LOG_FILE
