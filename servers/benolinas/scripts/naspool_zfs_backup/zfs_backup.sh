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
MAX_RETENTION_PERIODS=50 # Adjust accordingly, but 50 seems like enough

# Set the source pool
SOURCE_POOL="naspool"

# Log files
LOG_FILE="/var/log/zfs_backup.log"
DISK_USAGE_LOG="/var/log/zfs_disk_usage.log"

# Detect the active backup pool
BACKUP_POOL="naspool_backup2"
#$(zpool list -H -o name | grep -m1 "naspool_backup")

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

# Function to log messages
log_message() {
    local message="$1"
    echo -e "$(date) - $message" | tee -a "$LOG_FILE"
}

# Log start of backup and do some preliminary checks
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
if [[ "$RETENTION_PERIOD" =~ ^[0-9]+$ ]] && (( RETENTION_PERIOD >= 0 && RETENTION_PERIOD <= MAX_RETENTION_PERIODS )); then
    log_message "Info: Retention period (${RETENTION_PERIOD}) is valid."
else
    log_message "Error: Invalid Retention period (${RETENTION_PERIOD}), this must be a number between 0 and $MAX_RETENTION_PERIODS."
    exit 1
fi

# Function to send a Discord notification - note this will also log the message, so no need to call both the log and send functions
send_discord_notification() {
    local message=$1
    local markdown_replaced_message=$(echo "$message" | sed -e 's/:x:/Error:/g' \
                                               -e 's/\*\*//g' \
                                               -e 's/:warning:/Warning:/g' \
                                               -e 's/:white_check_mark:/Info:/g' \
                                               -e 's/__//g' \
                                               -e 's/:test_tube:/Test:/g')
    log_message $markdown_replaced_message # Log the message, then send via discord webhook

    JSON_MESSAGE=$(jq -Rn --arg msg "$message" '{content: $msg}')
    curl -H "Content-Type: application/json" -X POST -d "$JSON_MESSAGE" "$DISCORD_WEBHOOK_URL"
}

# Check if backup pool is found
if [ -z "$BACKUP_POOL" ]; then
    send_discord_notification ":x: **ZFS Pool Backup Failed** No backup pool detected!"
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
    send_discord_notification ":warning: **Low Disk Space Warning** - ${FREE_SPACE_GB}GB free on BACKUP_POOL: **$BACKUP_POOL**!"
fi
if (( $(echo "$FREE_SPACE_GB_SOURCE_POOL < $SOURCE_POOL_SIZE_WARNING_THRESHOLD" | bc -l) )); then
    send_discord_notification ":warning: **Low Disk Space Warning** - ${FREE_SPACE_GB_SOURCE_POOL}GB free on SOURCE_POOL: **$SOURCE_POOL**!"
fi

# Stop the backup if space is critically low
if (( $(echo "$FREE_SPACE_GB < $BACKUP_POOL_CRITICAL_THRESHOLD" | bc -l) )); then
    send_discord_notification ":x: **ZFS Pool Backup Stopped** - Critical disk space alert on BACKUP_POOL: **$BACKUP_POOL**! *Free Space, ${FREE_SPACE_GB}GB is below ${BACKUP_POOL_CRITICAL_THRESHOLD}GB critical threshold.*"
    exit 1
fi
if (( $(echo "$FREE_SPACE_GB_SOURCE_POOL < $SOURCE_POOL_CRITICAL_THRESHOLD" | bc -l) )); then    
    send_discord_notification ":x: **ZFS Pool Backup Stopped** - Critical disk space alert on SOURCE_POOL: **$SOURCE_POOL**! *Free Space, ${FREE_SPACE_GB_SOURCE_POOL}GB is below ${SOURCE_POOL_CRITICAL_THRESHOLD}GB critical threshold.*"
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



# TODO: NEED TO GET THE LAST SNAP ON THE BACKUP POOL AND SET THE INCREMENTAL SOURCE TO THAT SNAPSHOT NAME
# TODO: Do I need to keep a record of snapshots between the naspool and backup pool so that I don't delete the last snapshot that the backup pool has when it was ejected?
# TODO: Yes, Setup txt file to keep track of which snapshots have been sent to the naspool_backup, name it the same as the backup, naming convention: snapshot_history_[backup_pool_name].txt, e.g.: snapshot_history_naspool_backup1.txt
# OTHERWISE, GETTING ERRORS LIKE: 
    Fri Mar 21 03:25:43 PM EDT 2025 - Info: Sending incremental snapshot from naspool@daily_backup_20250321 to naspool@daily_backup_20250321 to backup pool: naspool_backup2.
    WARNING: could not send naspool@daily_backup_20250321:
    incremental source (naspool@daily_backup_20250321) is not earlier than it
    WARNING: could not send naspool/share@daily_backup_20250321:
    incremental source (naspool/share@daily_backup_20250321) is not earlier than it
    WARNING: could not send naspool/backups@daily_backup_20250321:
    incremental source (naspool/backups@daily_backup_20250321) is not earlier than it
# ALSO, AFTER TESTING ON naspool2, DON'T FORGET TO CHANGE BACK THE BACKUP_POOL VARIABLE ABOVE




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
            
            # Capture/Log the exit status of the zfs send command
            ZFS_SEND_EXIT_CODE=$?
            if [ ZFS_SEND_EXIT_CODE -eq 0 ]; then
                log_message "Info: Successfully sent incremental snapshot from $LAST_SNAP to $SNAP_NAME to backup pool: $BACKUP_POOL."
            else
                log_message "Error: Failed to send incremental snapshot from $LAST_SNAP to $SNAP_NAME to backup pool: $BACKUP_POOL. ZFS_SEND_EXIT_CODE: $ZFS_SEND_EXIT_CODE"
            fi            
        else
            log_message "Info: Skipping ZFS incremental send to $BACKUP_POOL because IS_TEST is true. LAST_SNAP: $LAST_SNAP | SNAP_NAME: $SNAP_NAME"
        fi
    else
        if [ "$IS_TEST" = false ]; then
            log_message "Info: Sending full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL."
            zfs send -R "$SNAP_NAME" | zfs receive -Fdu "$BACKUP_POOL"
            
            # Capture/Log the exit status of the zfs send command
            ZFS_SEND_EXIT_CODE=$?
            if [ ZFS_SEND_EXIT_CODE -eq 0 ]; then
                log_message "Info: Successfully sent full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL."
                            
            else
                log_message "Error: Failed to send full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL. ZFS_SEND_EXIT_CODE: $ZFS_SEND_EXIT_CODE"
            fi 
        else
            log_message "Info: Skipping ZFS full send to $BACKUP_POOL because IS_TEST is true. LAST_SNAP: $LAST_SNAP | SNAP_NAME: $SNAP_NAME"
        fi
    fi
fi

# Cleanup old snapshots
log_message "Info: Checking retention period (${RETENTION_PERIOD}) and cleaning up older snapshots."

# TODO: TEST THIS!
cleanup_snapshots() {  
    local SNAP_COUNT=0
    local SNAP_LIMIT=$RETENTION_PERIOD

    # List and loop through the snapshots based on the SNAP_TYPE
    zfs list -H -t snapshot -o name,creation | grep "$SNAP_TYPE" | while read -r SNAP CREATION; do
        if (( SNAP_COUNT < SNAP_LIMIT )); then
            if [ "$IS_TEST" = false ]; then
                log_message "Info: Destroying (cleaning up) snapshot $SNAP"
                zfs destroy -r "$SNAP"
            else
                log_message "Info: Skipping snapshot cleanup because IS_TEST is true. Snapshot that would be destroyed: $SNAP"
            fi
            ((SNAP_COUNT++))
        else
            break
        fi
    done

    if (( SNAP_COUNT == 0 )); then
        log_message "Info: No snapshots found for cleanup."
    else
        log_message "Info: $SNAP_COUNT snapshots cleaned up."
    fi
}

# call the function to cleanup older snapshots based on retention period
cleanup_snapshots

# send message 
if [ "$IS_TEST" = false ]; then
    send_discord_notification ":white_check_mark: **ZFS ${SNAP_TYPE^} Backup Completed Successfully for ${SOURCE_POOL}** - Snapshot ${SNAP_NAME} sent to ${BACKUP_POOL}. *(see $LOG_FILE for more details)*"    
else
    send_discord_notification ":white_check_mark::test_tube: **_Test_ run of ZFS ${SNAP_TYPE^} Backup Completed Successfully** - Snapshot ${SNAP_NAME} would have been created and sent to ${BACKUP_POOL} if IS_TEST were set to 'false'. *(see $LOG_FILE for more details)*"    
fi

# Add separator for log file for next run:
log_message "End of ZFS Backup Process\n=========="