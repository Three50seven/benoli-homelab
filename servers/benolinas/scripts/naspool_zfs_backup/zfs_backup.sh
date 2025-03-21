#!/usr/bin/bash

# ZFS Backup Script with Disk Space Monitoring, Logging, Retention Period & Discord Notifications
# The MAIN parts of this script (i.e. the ones that impact the ZFS pools) are as follows:
#   zfs snapshot
#   zfs send
#   zfs destroy
# You can search for these and find them towards the bottom of the script, they should have the "IS_TEST" check around them too.
# The remainder of the script is "fluff" and used for variable setup and function setup, as well as safety checks, duplicate checks, etc.

# Set the IS_TEST variable to true to run a test only 
# When false, the ZFS commands will be executed. i.e. a snapshot will be made and sent to the backup pool, and old ones will be destroyed
IS_TEST=true # Safety flag for running just a test without impacting the ZFS pools

# Get the snapshot type - this will be sent from the Cron job
# Valid options are: daily|weekly|monthly|yearly
SNAP_TYPE="$1"

# Snapshot retention periods
# If zero (0) - a snapshot will not be taken for that period
RETENTION_PERIOD="$2"

# Set the source pool
SOURCE_POOL="naspool"

# Log files
LOG_FILE="/var/log/zfs_backup.log"
DISK_USAGE_LOG="/var/log/zfs_disk_usage.log"

# Function to log messages
log_message() {
    local message="$1"
    echo -e "$(date) - $message" | tee -a "$LOG_FILE"
}

# Detect the active backup pool
BACKUP_POOL=$(zpool list -H -o name | grep -m1 "naspool_backup")

# Discord Webhook URL (Replace with your actual webhook)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
WEBHOOK_FILE="$SCRIPT_DIR/secrets/.zfs_backups_discord_webhook"

# Minimum required free space in GB
# Send a warning if below warning threshold
BACKUP_POOL_SIZE_WARNING_THRESHOLD=500
SOURCE_POOL_SIZE_WARNING_THRESHOLD=500
# Stop backup if below critical threshold
BACKUP_POOL_CRITICAL_THRESHOLD=100  
SOURCE_POOL_CRITICAL_THRESHOLD=100

# Log start of backup
log_message "Info: Starting ZFS $SNAP_TYPE backup on $(hostname) - Variables:\n\tSNAP_TYPE: $SNAP_TYPE\n\t\
RETENTION_PERIOD: $RETENTION_PERIOD\n\tIS_TEST: $IS_TEST\n\tBACKUP_POOL_SIZE_WARNING_THRESHOLD (GB): $BACKUP_POOL_SIZE_WARNING_THRESHOLD\n\t\
BACKUP_POOL_CRITICAL_THRESHOLD (GB): $BACKUP_POOL_CRITICAL_THRESHOLD\n\tSOURCE_POOL_SIZE_WARNING_THRESHOLD (GB): $SOURCE_POOL_SIZE_WARNING_THRESHOLD\n\t\
SOURCE_POOL_CRITICAL_THRESHOLD (GB): $SOURCE_POOL_CRITICAL_THRESHOLD\n\tWEBHOOK_FILE: $WEBHOOK_FILE"

# Attempt to Read webhook URL from the file specified in the variable
if [[ -f "$WEBHOOK_FILE" ]]; then
    DISCORD_WEBHOOK_URL=$(awk 'NR==1' "$WEBHOOK_FILE")
else
    log_message "Error: Webhook file not found for ZFS Backup!"
    exit 1
fi

# Verify the snapshot type is not empty and matches a valid type
if [[ -z "$SNAP_TYPE" || ! "$SNAP_TYPE" =~ ^(daily|weekly|monthly|yearly)$ ]]; then
    log_message "Error: Incorrect snapshot type usage: $0 {daily|weekly|monthly|yearly}"
    exit 1
fi

# Verify the snapshot retention period is valid
if [[ "$RETENTION_PERIOD" =~ ^[0-9]+$ ]] && (( RETENTION_PERIOD >= 0 && RETENTION_PERIOD <= 50 )); then
    log_message "Info: Retention period (${RETENTION_PERIOD}) is valid."
else
    log_message "Error: Invalid Retention period (${RETENTION_PERIOD}), this must be a number between 0 and 50."
    exit 1
fi

# Function to send a Discord notification
send_discord_notification() {
    MESSAGE=$1
    JSON_MESSAGE=$(jq -Rn --arg msg "$MESSAGE" '{content: $msg}')
    curl -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE" "$DISCORD_WEBHOOK_URL"
}

# Check if backup pool is found
if [ -z "$BACKUP_POOL" ]; then
    log_message "Error: ZFS Pool Backup failed - No backup pool detected!"
    send_discord_notification ":x: **ZFS Pool Backup Failed:** No backup pool detected!"
    exit 1
fi

FREE_SPACE_GB=$(zfs list -H -o available $BACKUP_POOL | numfmt --from=iec | awk '{print $1 / 1073741824}')
FREE_SPACE_GB_SOURCE_POOL=$(zfs list -H -o available $SOURCE_POOL | numfmt --from=iec | awk '{print $1 / 1073741824}')

# Log disk usage to separte file for helping to plot usage over time
echo "$(date), $BACKUP_POOL, ${FREE_SPACE_GB}GB free" | tee -a $DISK_USAGE_LOG
echo "$(date), $SOURCE_POOL, ${FREE_SPACE_GB_SOURCE_POOL}GB free" | tee -a $DISK_USAGE_LOG
log_message "Info: Backup ZFS Pool: $BACKUP_POOL has ${FREE_SPACE_GB}GB free - also see $DISK_USAGE_LOG for CSV list to help plot out usage over time"
log_message "Info: Source ZFS Pool: $SOURCE_POOL has ${FREE_SPACE_GB_SOURCE_POOL}GB free - also see $DISK_USAGE_LOG for CSV list to help plot out usage over time"

# Send a warning if space is low on source pool or backup pool
if (( $(echo "$FREE_SPACE_GB < $BACKUP_POOL_SIZE_WARNING_THRESHOLD" | bc -l) )); then
    log_message "Warning: Low Disk Space Warning - ${FREE_SPACE_GB}GB free on BACKUP_POOL: **$BACKUP_POOL**!"
    send_discord_notification ":warning: **Low Disk Space Warning:** ${FREE_SPACE_GB}GB free on BACKUP_POOL: **$BACKUP_POOL**!"
fi
if (( $(echo "$FREE_SPACE_GB_SOURCE_POOL < $SOURCE_POOL_SIZE_WARNING_THRESHOLD" | bc -l) )); then
    log_message "Warning: Low Disk Space Warning - ${FREE_SPACE_GB_SOURCE_POOL}GB free on SOURCE_POOL: **$SOURCE_POOL**!"
    send_discord_notification ":warning: **Low Disk Space Warning:** ${FREE_SPACE_GB_SOURCE_POOL}GB free on SOURCE_POOL: **$SOURCE_POOL**!"
fi

# Stop the backup if space is critically low
if (( $(echo "$FREE_SPACE_GB < $BACKUP_POOL_CRITICAL_THRESHOLD" | bc -l) )); then
    log_message "Error: ZFS Pool Backup Stopped - Critical disk space alert on BACKUP_POOL: $BACKUP_POOL! Free Space, ${FREE_SPACE_GB}GB is below ${BACKUP_POOL_CRITICAL_THRESHOLD}GB critical threshold."
    send_discord_notification ":x: **ZFS Pool Backup Stopped:** Critical disk space alert on BACKUP_POOL: **$BACKUP_POOL**! *Free Space, ${FREE_SPACE_GB}GB is below ${BACKUP_POOL_CRITICAL_THRESHOLD}GB critical threshold.*"
    exit 1
fi
if (( $(echo "$FREE_SPACE_GB_SOURCE_POOL < $SOURCE_POOL_CRITICAL_THRESHOLD" | bc -l) )); then
    log_message "Error: ZFS Pool Backup Stopped - Critical disk space alert on SOURCE_POOL: $SOURCE_POOL! Free Space, ${FREE_SPACE_GB_SOURCE_POOL}GB is below ${SOURCE_POOL_CRITICAL_THRESHOLD}GB critical threshold."
    send_discord_notification ":x: **ZFS Pool Backup Stopped:** Critical disk space alert on SOURCE_POOL: **$SOURCE_POOL**! *Free Space, ${FREE_SPACE_GB_SOURCE_POOL}GB is below ${SOURCE_POOL_CRITICAL_THRESHOLD}GB critical threshold.*"
    exit 1
fi

# Get today's date
DATE=$(date +"%Y%m%d")
SNAP_ENDING="${SNAP_TYPE}_backup_$DATE"
SNAP_NAME="${SOURCE_POOL}@${SNAP_ENDING}"

#1. Get the Last Snapshot: Use zfs list to find the most recent snapshot.
#2. Check for Previous Snapshot: If a previous snapshot exists, send the incremental snapshot. Otherwise, perform a full send.
LAST_SNAP=$(zfs list -H -t snapshot -o name -S creation | grep "^$SOURCE_POOL@$SNAP_TYPE" | head -n 1)
log_message "Info: Last snapshot: $LAST_SNAP - New snapshot: $SNAP_NAME"

# Create new snapshot based on retention settings for this type if one by the same name doesn't already exist
if [ "$RETENTION_PERIOD" -ne 0 ]; then
    if zfs list -t snapshot -o name | grep -q "$SNAP_NAME"; then
        log_message "Info: Skipping snapshot creation - snapshot $SNAP_NAME already exists."
    else
        if [ "$IS_TEST" = false ]; then
            zfs snapshot -r "$SNAP_NAME"
            log_message "Info: Created $SNAP_TYPE snapshot: $SNAP_NAME"
        else
            log_message "Info: Skipping snapshot creation (${SNAP_NAME}) because IS_TEST is true."
        fi
    fi
else
    log_message "Info: RETENTION_PERIOD Variable (${RETENTION_PERIOD}) is set to zero (0) - skipping this snapshot"
    exit 1
fi

# Send incremental snapshots to backup pool if it doesn't already exist
# Check if the snapshot already exists on the receiving pool
if zfs list -H -t snapshot -o name | grep -q "$BACKUP_POOL@$SNAP_ENDING"; then
    log_message "Info: Snapshot ${BACKUP_POOL}@${SNAP_ENDING} already exists on the backup pool: $BACKUP_POOL. Skipping send."
else    
    if [ -n "$LAST_SNAP" ]; then
        if [ "$IS_TEST" = false ]; then
            log_message "Info: Sending incremental snapshot from $LAST_SNAP to $SNAP_NAME to backup pool: $BACKUP_POOL."
            zfs send -R -I "$LAST_SNAP" "$SNAP_NAME" | zfs receive -Fdu "$BACKUP_POOL"
            log_message "Info: Sent incremental snapshot from $LAST_SNAP to $SNAP_NAME to backup pool: $BACKUP_POOL."
        else
            log_message "Info: Skipping ZFS incremental send to $BACKUP_POOL because IS_TEST is true. LAST_SNAP: $LAST_SNAP | SNAP_NAME: $SNAP_NAME"
        fi
    else
        if [ "$IS_TEST" = false ]; then
            log_message "Info: Sending full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL."
            zfs send -R "$SNAP_NAME" | zfs receive -Fdu "$BACKUP_POOL"
            log_message "Info: Sent full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL."
        else
            log_message "Info: Skipping ZFS full send to $BACKUP_POOL because IS_TEST is true. LAST_SNAP: $LAST_SNAP | SNAP_NAME: $SNAP_NAME"
        fi
    fi
fi

# Cleanup old snapshots
log_message "Info: Checking retention period (${RETENTION_PERIOD}) and cleaning up older snapshots."

delete_old_snapshots() {  
    local DATE_FILTER

    case $SNAP_TYPE in
        daily)
            DATE_FILTER="$(date -d "$RETENTION_PERIOD days ago" +%s)"
            ;;
        weekly)
            DATE_FILTER="$(date -d "$RETENTION_PERIOD weeks ago" +%s)"
            ;;
        monthly)
            DATE_FILTER="$(date -d "$RETENTION_PERIOD months ago" +%s)"
            ;;
        yearly)
            DATE_FILTER="$(date -d "$RETENTION_PERIOD years ago" +%s)"
            ;;
        *)
        log_message "Warning: Invalid SNAP_TYPE in delete_old_snapshots function. Use daily, weekly, monthly, or yearly."
        return 1
        ;;
    esac

    # List and loop through the snapshots that are older than the retention period and destroy them, based on the SNAP_TYPE
	zfs list -H -t snapshot -o name,creation | grep "$SNAP_TYPE" | while read -r SNAP CREATION; do
		CREATION_TIMESTAMP=$(date -d "$CREATION" +%s)
		if (( CREATION_TIMESTAMP < DATE_FILTER )); then
			if [ "$IS_TEST" = false ]; then
                log_message "Info: Destroying (cleaning up) snapshot $SNAP"
                zfs destroy -r "$SNAP"
            else
                log_message "Info: Skipping snapshot cleanup because IS_TEST is true. Snapshot that would be destroyed: $SNAP"
            fi
		fi
	done
}

# call the function to cleanup older snapshots based on retention period
delete_old_snapshots

# send message 
if [ "$IS_TEST" = false ]; then
    send_discord_notification ":tada: **ZFS ${SNAP_TYPE^} Backup Completed Successfully for ${SOURCE_POOL}** - Snapshot ${SNAP_NAME} sent to ${BACKUP_POOL}. *(see $LOG_FILE for more details)*"
    log_message "Info: ZFS ${SNAP_TYPE^} backup process complete for ${SOURCE_POOL} - Snapshot ${SNAP_NAME} sent to ${BACKUP_POOL}. (see $LOG_FILE for more details)\n=========="
else
    send_discord_notification ":tada::test_tube: **_Test_ run of ZFS ${SNAP_TYPE^} Backup Completed Successfully** - Snapshot ${SNAP_NAME} would have been created and sent to ${BACKUP_POOL} if IS_TEST were set to 'false'. *(see $LOG_FILE for more details)*"
    log_message "Info: Test run of ZFS ${SNAP_TYPE^} backup process complete for ${SOURCE_POOL} - Snapshot ${SNAP_NAME} would have been created and sent to ${BACKUP_POOL} if IS_TEST were set to 'false'. (see $LOG_FILE for more details)\n=========="
fi
