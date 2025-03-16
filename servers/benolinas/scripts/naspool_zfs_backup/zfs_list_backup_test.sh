#!/bin/bash

# ZFS Backup TEST Script with Disk Space Monitoring, Logging, Retention Period & Discord Notifications

# Set the source pool
SOURCE_POOL="naspool"

# Log files
LOG_FILE="/var/log/zfs_backup_test.log"
DISK_USAGE_LOG="/var/log/zfs_disk_usage_test.log"

# Detect the active backup pool
# NOTE: This will only grab the first match for a pool name that contains "naspool_backup". If both naspool_backup1 and naspool_backup2 are available, it will only grab the first pool it encounters in the list, which could be either naspool_backup1 or naspool_backup2, depending on the order in which they are listed by zpool list.
BACKUP_POOL=$(zpool list -H -o name | grep "naspool_backup")

# Discord Webhook URL (Replace with your actual webhook)
DISCORD_WEBHOOK_URL=$(awk 'NR==1' ./secrets/.zfs_backups_discord_webhook)

# Minimum required free space in GB
WARNING_THRESHOLD=100  # Send a warning if below this
CRITICAL_THRESHOLD=50  # Stop backup if below this

# Snapshot retention period (days)
RETENTION_DAYS=7  # Retention period for snapshots (adjust as needed)

# Function to send a Discord notification
send_discord_notification() {
    MESSAGE=$1
    JSON_MESSAGE=$(jq -Rn --arg msg "$MESSAGE" '{content: $msg}')
    curl -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE" "$DISCORD_WEBHOOK_URL"
}

send_snapshot_list() {
    # Get the last 7 snapshots and format them as a list
    SNAPSHOT_LIST=$(zfs list -t snapshot -o name,creation -s creation | tail -7 | awk '{print "**"$1"** - "$2" "$3" "$4}' | jq -R . | jq -s .)

    # Format the JSON payload using jq
    JSON_MESSAGE=$(jq -n --argjson snapshots "$SNAPSHOT_LIST" --arg title "**Latest Snapshots:**" '{content: ($title + "\n" + ($snapshots | join("\n")))}')

    # Send to Discord (webhook)
    curl -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE" "$DISCORD_WEBHOOK_URL"
}

# Log start of backup
echo "$(date) - Starting ZFS backup TEST" | tee -a $LOG_FILE

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

# Send snapshot list to Discord
send_snapshot_list

# Send success message
send_discord_notification ":tada: **Backup Completed Successfully!**"
echo "$(date) - Backup process complete!" | tee -a $LOG_FILE
