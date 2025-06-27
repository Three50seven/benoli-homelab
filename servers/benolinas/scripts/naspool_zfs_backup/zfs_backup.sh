#!/usr/bin/bash

# ZFS Backup Script with Disk Space Monitoring, Logging, Retention Period & Discord Notifications
# The MAIN parts of this script (i.e. the ones that impact the ZFS pools) are as follows:
#   zfs snapshot
#   zfs send
#   zfs destroy
# You can search for these and find them towards the bottom of the script, they should have the "IS_TEST" check around them too.
# The remainder of the script is "fluff" and used for variable setup and function setup, as well as safety checks, duplicate checks, etc.

# Example, to run script from terminal, for daily and keeping 7 days worth of snapshots, 
#   navigate to or point to the location on the server and run with: 
#   bash zfs_backup.sh daily 7

# NOTE: To make the script executable on Linux, make sure it's in Unix (LF) format'
# If not, you'll see errors like this: line 2 $'\r': command not found
# When opening this file, make sure bottom-right status in Notepad++ says Unix (LF)
# If it indicates Windows CRLF, convert it => open NotePad++, click Edit, Hover over EOL Conversion and select Unix (LF)

print_help() {
    cat <<EOF
Usage: $0 [snapshot_type] [retention_period] [options]

Positional Arguments:
  snapshot_type         Type of snapshot to run. Valid options: daily, weekly, monthly, yearly
  retention_period      Number of snapshots to retain for the given type. Use 0 to skip creating a snapshot

Optional Flags:
  -v, --verbose         Enable verbose output (echo messages to stdout)
  -q, --quiet           Suppress stdout messages (log silently)
  -t, --test            Run in TEST mode (default). No destructive actions performed
      --live            Run in LIVE mode. Operations affecting ZFS pools will be executed
  -h, --help            Display this help message and exit

Configuration File:
  The script expects a configuration file named zfs_backup_settings.conf to be present.
  This file defines essential runtime parameters, such as:

    - SOURCE_POOL: Primary ZFS pool where snapshots originate
    - REQUIRED_POOLS: All pools involved in the backup and cleanup process. Note: even if a pool is offline, the script will need it to store its snapshot history.
    - LOG_FILE, DISK_USAGE_LOG, etc.: Paths for log management
    - LOG_FILE_LINES_TO_KEEP: Maximum lines to retain in log files
    - LOG_DATE_FORMAT: Optional formatting can be passed, default is ISO 8601
    - SKIP_LOG_FILE_MAINTENANCE: Set to "true" to skip log trimming
    - BACKUP_POOL thresholds for disk space warning/critical levels
    - Discord webhook path for alerts (relative to the script directory)

  Make sure the Discord webhook is created and the path etc. is stored here:
  Format of Webhook: https://discord.com/api/webhooks/[WEBHOOK_ID]/[UNIQUE_CODE]
  (relative to the script directory)/secrets/.zfs_backups_discord_webhook"

  The script automatically detects the active BACKUP_POOL from available devices 
  matching the pattern "naspool_backup*", and selects the first valid match for sending snapshots.

Current Configuration (values read from $CONFIG_FILE):
  SOURCE_POOL                 = $SOURCE_POOL
  REQUIRED_POOLS              = ${REQUIRED_POOLS[*]}
  LOG_FILE                    = $LOG_FILE
  DISK_USAGE_LOG              = $DISK_USAGE_LOG
  SNAPSHOT_TRANSFER_HISTORY_LOG = $SNAPSHOT_TRANSFER_HISTORY_LOG
  LOG_FILE_LINES_TO_KEEP      = $LOG_FILE_LINES_TO_KEEP
  SKIP_LOG_FILE_MAINTENANCE   = $SKIP_LOG_FILE_MAINTENANCE
  MAX_RETENTION_PERIODS       = $MAX_RETENTION_PERIODS
  BACKUP_POOL WARNING         = ${BACKUP_POOL_SIZE_WARNING_THRESHOLD}GB
  BACKUP_POOL CRITICAL        = ${BACKUP_POOL_CRITICAL_THRESHOLD}GB
  SOURCE_POOL WARNING         = ${SOURCE_POOL_SIZE_WARNING_THRESHOLD}GB
  SOURCE_POOL CRITICAL        = ${SOURCE_POOL_CRITICAL_THRESHOLD}GB
  LOG_DATE_FORMAT             = $LOG_DATE_FORMAT

Examples:
  $0 daily 7 -v           Run a daily backup keeping 7 snapshots with verbose output - default will be test mode
  $0 monthly 4 --live     Run a live monthly backup retaining 4 snapshots
  $0 weekly 0 -q          Skip weekly snapshot (retention = 0), quiet mode
  $0 daily 7 -vt          Run a daily backup keeping 7 snapshots with verbose output and in test mode only, so that no snapshot is created and no destructive actions are performed.

EOF
}

# Load config file
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/zfs_backup_settings.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file $CONFIG_FILE not found. Exiting script."
    exit 1
fi

# Config file readability check
if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "Error: Config file $CONFIG_FILE exists but cannot be read. Exiting script."
    exit 1
fi

echo "Info: Sourcing variables from config file after checking if it exists and is readable:"
source "$CONFIG_FILE"

# Positional Arguments:
# Get the snapshot type - this will be sent from the Cron job
# Valid options are: daily|weekly|monthly|yearly
SNAP_TYPE=""

# Snapshot retention periods
# If zero (0) - a snapshot will not be taken for that period
RETENTION_PERIOD=""

# Default values
VERBOSE="false"
QUIET="false"
IS_TEST="true"  # default
TEST_MODE_SET=""
LIVE_MODE_SET=""

# Parse the opations:
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        --quiet)
            QUIET="true"
            shift
            ;;
        --test)
            IS_TEST="true"
            TEST_MODE_SET="true"
            shift
            ;;
        --live)
            IS_TEST="false"
            LIVE_MODE_SET="true"
            shift
            ;;
        -[a-zA-Z]*)
            # Loop over each character in the combined flag (e.g. -vq)
            for (( i=1; i<${#1}; i++ )); do
                char="${1:$i:1}"
                case "$char" in
                    v) VERBOSE="true" ;;
                    q) QUIET="true" ;;
                    t) IS_TEST="true"; TEST_MODE_SET="true" ;;
                    *) echo "Unknown flag: -$char"; exit 1 ;;
                esac
            done
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$SNAP_TYPE" ]]; then
                SNAP_TYPE="$1"
            elif [[ -z "$RETENTION_PERIOD" ]]; then
                RETENTION_PERIOD="$1"
            else
                echo "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check for conflict in run modes live|test
if [[ "$TEST_MODE_SET" == "true" && "$LIVE_MODE_SET" == "true" ]]; then
    echo "Error: Cannot use --test and --live together. Choose one."
    exit 1
fi

ensure_log_files_exist() {
    for path in "$LOG_FILE" "$DISK_USAGE_LOG" "$SNAPSHOT_TRANSFER_HISTORY_LOG"; do
        if [[ ! -f "$path" ]]; then
            touch "$path"
            if [[ $? -ne 0 ]]; then
                echo "Error: Failed to create log file: $path  - check permissions!"
                exit 1
            else
                echo "Info: Created missing log file: $path"
            fi
        fi
        if [[ ! -w "$path" ]]; then
            echo "Error: Log file $path exists but is not writable! Check permissions."
            exit 1
        fi
    done
}

# Function to log messages
log_message() {
    local message="$1"
    local timestamped_msg="$(date +"$LOG_DATE_FORMAT") - $message"

    # Always write to log file
    echo -e "$timestamped_msg" >> "$LOG_FILE"

    # Echo to stdout only if verbose is enabled and quiet is not
    if [[ "$VERBOSE" == "true" && "$QUIET" != "true" ]]; then
        echo -e "$timestamped_msg"
    fi
}

trim_log_files() {
    if [[ "$SKIP_LOG_FILE_MAINTENANCE" == "false" ]]; then
        local LOG_FILES=("$LOG_FILE" "$DISK_USAGE_LOG" "$SNAPSHOT_TRANSFER_HISTORY_LOG")
        local MIN_LOG_LINES=100
        local MAX_LOG_LINES=50000
        local TRIM_NOTICE_PATTERN=" - Info: Previous log entries trimmed to maintain file size."
        local TRIM_NOTICE="$(date +"$LOG_DATE_FORMAT")$TRIM_NOTICE_PATTERN"

        if ! echo "$LOG_FILE_LINES_TO_KEEP" | grep -qE '^[0-9]+$'; then
            log_message "Error: LOG_FILE_LINES_TO_KEEP must be a valid number. Found: $LOG_FILE_LINES_TO_KEEP"
            exit 1
        elif (( LOG_FILE_LINES_TO_KEEP < MIN_LOG_LINES || LOG_FILE_LINES_TO_KEEP > MAX_LOG_LINES )); then
            log_message "Error: LOG_FILE_LINES_TO_KEEP ($LOG_FILE_LINES_TO_KEEP) must be between $MIN_LOG_LINES and $MAX_LOG_LINES."
            exit 1
        fi

        for LOCAL_LOG_FILE in "${LOG_FILES[@]}"; do
            if [[ -f "$LOCAL_LOG_FILE" ]]; then
                local CURRENT_LINES
                CURRENT_LINES=$(wc -l < "$LOCAL_LOG_FILE")

                if (( CURRENT_LINES > LOG_FILE_LINES_TO_KEEP )); then
                    log_message "Info: Trimming log file ($LOCAL_LOG_FILE). Current lines: $CURRENT_LINES. Keeping: $LOG_FILE_LINES_TO_KEEP."

                    # Get the last N lines (excluding any previous trim notice)
                    tail -n "$LOG_FILE_LINES_TO_KEEP" "$LOCAL_LOG_FILE" | \
                        sed "1{/$(printf '%s\n' "$TRIM_NOTICE_PATTERN" | sed 's/[^^]/[&]/g; s/\^/\\^/g')/d}" > "$LOCAL_LOG_FILE.tmp"

                    # Prepend the updated trim notice
                    echo "$TRIM_NOTICE" | cat - "$LOCAL_LOG_FILE.tmp" > "$LOCAL_LOG_FILE.trimmed" && mv "$LOCAL_LOG_FILE.trimmed" "$LOCAL_LOG_FILE"

                    if [[ $? -eq 0 ]]; then
                        log_message "Info: Successfully trimmed $LOCAL_LOG_FILE"
                    else
                        log_message "Error: Failed to replace $LOCAL_LOG_FILE with trimmed version"
                    fi
                else
                    log_message "Info: Log file has $CURRENT_LINES lines. No trimming needed."
                fi
            else
                log_message "Warning: Log file $LOCAL_LOG_FILE does not exist-skipping trim."
            fi
        done
    else
        log_message "Info: Skipping log file maintenance."
    fi
}

echo "Info: Ensuring log files exist and are writable."
ensure_log_files_exist

LOG_DATE_FORMAT=${LOG_DATE_FORMAT:-"%Y-%m-%dT%H:%M:%S%z"}  # Default to ISO 8601

# Validate LOG_DATE_FORMAT (must contain recognized format specifiers)
if ! date +"$LOG_DATE_FORMAT" &>/dev/null; then
    log_message "Warning: Invalid LOG_DATE_FORMAT detected. Falling back to ISO 8601."
    LOG_DATE_FORMAT="%Y-%m-%dT%H:%M:%S%z"
fi

# Safety flag for running just a test without impacting the ZFS pools - only runs in "LIVE" mode when set to "false" in config - Default is true
if [[ "$IS_TEST" == "false" ]]; then
    log_message "Info: Running in LIVE mode - backup operations will proceed normally."
else
    log_message "Info: Running in TEST mode - no destructive operations will be performed."
fi

# Detect the active backup pool
BACKUP_POOL=$(zpool list -H -o name | grep -m1 "naspool_backup")

# Discord Webhook URL (Replace with your actual webhook)
WEBHOOK_FILE="$SCRIPT_DIR/secrets/.zfs_backups_discord_webhook"

# Log start of backup and do some preliminary checks
log_message "Info: Starting ZFS $SNAP_TYPE backup on $(hostname)

$(printf "+-%-40s-+-%-35s-+\n" "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..35})")
$(printf "| %-40s | %-35s |\n" "Variable" "Value")
$(printf "+-%-40s-+-%-35s-+\n" "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..35})")
$(printf "| %-40s | %-35s |\n" "SNAP_TYPE" "$SNAP_TYPE")
$(printf "| %-40s | %-35s |\n" "RETENTION_PERIOD" "$RETENTION_PERIOD")
$(printf "| %-40s | %-35s |\n" "IS_TEST" "$IS_TEST")
$(printf "| %-40s | %-35s |\n" "SOURCE_POOL" "$SOURCE_POOL")
$(printf "| %-40s | %-35s |\n" "BACKUP_POOL" "$BACKUP_POOL")
$(printf "| %-40s | %-35s |\n" "REQUIRED_POOLS" "$(printf "%s, " "${REQUIRED_POOLS[@]}")")
$(printf "| %-40s | %-35s |\n" "BACKUP_POOL_SIZE_WARNING_THRESHOLD (GB)" "$BACKUP_POOL_SIZE_WARNING_THRESHOLD")
$(printf "| %-40s | %-35s |\n" "BACKUP_POOL_CRITICAL_THRESHOLD (GB)" "$BACKUP_POOL_CRITICAL_THRESHOLD")
$(printf "| %-40s | %-35s |\n" "SOURCE_POOL_SIZE_WARNING_THRESHOLD (GB)" "$SOURCE_POOL_SIZE_WARNING_THRESHOLD")
$(printf "| %-40s | %-35s |\n" "SOURCE_POOL_CRITICAL_THRESHOLD (GB)" "$SOURCE_POOL_CRITICAL_THRESHOLD")
$(printf "| %-40s | %-35s |\n" "WEBHOOK_FILE" "$WEBHOOK_FILE")
$(printf "| %-40s | %-35s |\n" "LOG_FILE" "$LOG_FILE")
$(printf "| %-40s | %-35s |\n" "DISK_USAGE_LOG" "$DISK_USAGE_LOG")
$(printf "| %-40s | %-35s |\n" "SNAPSHOT_TRANSFER_HISTORY_LOG" "$SNAPSHOT_TRANSFER_HISTORY_LOG")
$(printf "+-%-40s-+-%-35s-+\n" "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..35})")
$(printf "| %-40s | %-35s |\n" "SKIP_LOG_FILE_MAINTENANCE" "$SKIP_LOG_FILE_MAINTENANCE")
$(printf "| %-40s | %-35s |\n" "LOG_FILE_LINES_TO_KEEP" "$LOG_FILE_LINES_TO_KEEP")
$(printf "| %-40s | %-35s |\n" "LOG_DATE_FORMAT" "$LOG_DATE_FORMAT")
"

# Check log maintenance variables only if maintenance is done/needed
trim_log_files

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
# Note: when adding any new markdown (used by Discord), make sure it's replaced in the function for cleaner logging
send_discord_notification() {
    local message=$1

    # Convert markdown symbols to plain text for logging
    local markdown_replaced_message=$(echo "$message" | sed -e 's/:x:/Error:/g' \
                                                   -e 's/\*\*//g' \
                                                   -e 's/:warning:/Warning:/g' \
                                                   -e 's/:white_check_mark:/Info:/g' \
                                                   -e 's/__//g' \
                                                   -e 's/:test_tube:/Test:/g')
    log_message "$markdown_replaced_message" # Log cleaned message

    # Dynamically determine embed color based on the message content
    local message_color=16777215 # Default: White
    if echo "$markdown_replaced_message" | grep -q "Error[:.!?-]*"; then
        message_color=16711680 # Red
    elif echo "$markdown_replaced_message" | grep -q "Warning[:.!?-]*"; then
        message_color=16776960 # Yellow
    elif echo "$markdown_replaced_message" | grep -iq "Test[:.!?-]*"; then
        message_color=2003199 # Blue
    elif echo "$markdown_replaced_message" | grep -Eiq "Success|Successfully|Succeeded"; then
    message_color=65280 # Green
    fi

    # Extract bold title (text inside the first set of bold markdown **...**)
    local message_title=$(echo "$message" | grep -o '\*\*[^*]*\*\*' | sed 's/\*\*//g')

    # Construct JSON payload for Discord webhook - using embedded JSON for more customization (like changing colors)
    local embed_json=$(jq -n \
        --arg title "$message_title" \
        --arg desc "$message" \
        --argjson color "$message_color" \
        '{embeds: [{title: $title, description: $desc, color: $color}]}')

    # Send to Discord webhook
    curl -H "Content-Type: application/json" -X POST -d "$embed_json" "$DISCORD_WEBHOOK_URL"
}

# Stop the backup if SOURCE_POOL is blank or the ZFS pool is offline
if [[ -z "$SOURCE_POOL" ]]; then
    send_discord_notification ":x: **ZFS Pool Backup Aborted** SOURCE_POOL variable is blank - ZFS backup aborted!"
    exit 1
fi
if ! zpool list | grep -q "$SOURCE_POOL"; then
    send_discord_notification ":x: **ZFS Pool Backup Aborted** Source Pool ($SOURCE_POOL) is offline - ZFS backup aborted!"
    exit 1
fi

# Stop the backup if the BACKUP_POOL is blank or the ZFS pool is offline:
if [[ -z "$BACKUP_POOL" ]]; then
    send_discord_notification ":x: **ZFS Pool Backup Aborted** BACKUP_POOL variable is blank - ZFS backup aborted!"
    exit 1
fi
if ! zpool list | grep -q "$BACKUP_POOL"; then
    send_discord_notification ":x: **ZFS Pool Backup Aborted** Backup Pool ($BACKUP_POOL) is offline - ZFS backup aborted!"
    exit 1
fi

# Show pool and dataset sizes before new snapshot is sent to backup:
log_message "Info: Getting pool and dataset sizes before new snapshot is sent to backup:
$(zfs list -r -o name,used,available "$SOURCE_POOL" | column -t)
$(zfs list -r -o name,used,available "$BACKUP_POOL" | column -t)"

FREE_SPACE_GB_SOURCE_POOL=$(zfs list -H -o available $SOURCE_POOL | numfmt --from=iec | awk '{print $1 / 1073741824}')
FREE_SPACE_GB=$(zfs list -H -o available $BACKUP_POOL | numfmt --from=iec | awk '{print $1 / 1073741824}')

if ! echo "$FREE_SPACE_GB_SOURCE_POOL" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    log_message "Error: Failed to retrieve valid free space data for source pool: $SOURCE_POOL."
    exit 1
fi
if ! echo "$FREE_SPACE_GB" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    log_message "Error: Failed to retrieve valid free space data for backup pool: $BACKUP_POOL."
    exit 1
fi

# Log disk usage to separte file for helping to plot usage over time
echo "$(date +"$LOG_DATE_FORMAT"), $BACKUP_POOL, ${FREE_SPACE_GB}GB free" | tee -a $DISK_USAGE_LOG
echo "$(date +"$LOG_DATE_FORMAT"), $SOURCE_POOL, ${FREE_SPACE_GB_SOURCE_POOL}GB free" | tee -a $DISK_USAGE_LOG
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

# Get today's date for snapshot name
DATE=$(date +"%Y%m%d")
SNAP_ENDING="${SNAP_TYPE}_backup_$DATE"
SNAP_NAME="${SOURCE_POOL}@${SNAP_ENDING}"

# Get the Last Snapshot on source: Use zfs list to find the most recent snapshot.
LAST_SNAP_SOURCE_POOL=$(zfs list -H -t snapshot -o name -S creation -r $SOURCE_POOL | head -n 1)

# Display the last snapshot or notify if no entry found
if [ -n "$LAST_SNAP_SOURCE_POOL" ]; then
    log_message "Info: Last snapshot on source (${SOURCE_POOL}): $LAST_SNAP_SOURCE_POOL - New snapshot: $SNAP_NAME"
else
    log_message "Info: No snapshot found for $SNAP_TYPE backup."
fi

log_existing_snapshots() {
    local POOL=$1

    # Check if the pool is available before proceeding
    if ! zpool list | grep -q "$POOL"; then
        log_message "Warning: Pool $POOL is offline-skipping snapshot logging!"
        return
    fi

    zfs list -H -t snapshot -o name "$POOL" | while IFS= read -r SNAPSHOT; do
        if ! grep -q "$SNAPSHOT $POOL" "$SNAPSHOT_TRANSFER_HISTORY_LOG"; then
            echo -e "$SNAPSHOT $POOL $(date +"$LOG_DATE_FORMAT")" | tee -a "$SNAPSHOT_TRANSFER_HISTORY_LOG"
            log_message "Info: Adding previously transferred snapshot to log: $SNAPSHOT"
        fi
    done
}

log_snapshot_transfer() {
    local SNAP_NAME=$1
    local POOL=$2
    echo -e "$SNAP_NAME $POOL $(date +"$LOG_DATE_FORMAT")" | tee -a "$SNAPSHOT_TRANSFER_HISTORY_LOG"
}

snapshot_sent_to_all_pools() {
    local SNAP_NAME=$1

    for POOL in "${REQUIRED_POOLS[@]}"; do
        if ! grep -q "$SNAP_NAME $POOL" "$SNAPSHOT_TRANSFER_HISTORY_LOG"; then
            log_message "Warning: $SNAP_NAME has not been confirmed on $POOL-skipping deletion!"
            return 1 # Exit with failure (snapshot must remain)
        fi
    done

    return 0 # Success: safe to delete
}

# Breaker for actual ZFS manipulation and Snapshot processing that follows
log_message "Info: Set up and pre-checks complete - Continuing ZFS Backup."

# Create new snapshot based on retention settings for this type if one by the same name doesn't already exist
if [ "$RETENTION_PERIOD" -ne 0 ]; then
    if zfs list -t snapshot -o name | grep -q "$SNAP_NAME"; then
        log_message "Info: Skipping snapshot creation - snapshot $SNAP_NAME already exists."
    else
        if [[ "$IS_TEST" == "false" ]]; then
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

# Check for Previous Snapshot: If a previous snapshot exists, send the incremental snapshot. Otherwise, perform a full send.
LAST_SNAP_BACKUP_POOL=$(zfs list -H -t snapshot -o name -S creation -r $BACKUP_POOL | head -n 1)

# Convert LAST_SNAP_BACKUP_POOL to reference SOURCE_POOL
# for incremental sending, we need the latest snapshot from SOURCE_POOL that exists in BACKUP_POOL to ensure incremental send uses the correct lineage.            
if [[ -n "$LAST_SNAP_BACKUP_POOL" ]]; then
    LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP="${SOURCE_POOL}@$(echo "$LAST_SNAP_BACKUP_POOL" | cut -d'@' -f2)"
    log_message "Info: Found previous snapshot in backup pool: $LAST_SNAP_BACKUP_POOL - Adjusted to source pool: $LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP"

    # Verify the correct snapshot name - double-check that the converted snapshot exists in the source pool before attempting an incremental send
    if zfs list -H -t snapshot -o name | grep -q "^$LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP"; then
        log_message "Info: Snapshot $LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP exists in source pool, proceeding with incremental send."
    else
        log_message "Warning: Adjusted snapshot does not exist in source pool! Falling back to full send."
        LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP=""
    fi
else
    log_message "Warning: No prior snapshots found in backup pool. Defaulting to full send."
    LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP=""  # Forces full send
fi

# Check for Previous Snapshot: If a previous snapshot exists, send the incremental snapshot. Otherwise, perform a full send.
# Send incremental snapshots to backup pool if it doesn't already exist
# Check if the snapshot already exists on the receiving pool
if zfs list -H -t snapshot -o name | grep -q "^$SOURCE_POOL@$SNAP_ENDING" && \
   zfs list -H -t snapshot -o name | grep -q "^$BACKUP_POOL@$SNAP_ENDING"; then
    log_message "Info: Snapshot $SNAP_ENDING already exists in both pools (source pool: $SOURCE_POOL and backup pool: $BACKUP_POOL). Skipping send."    
else    
    if [ -n "$LAST_SNAP_BACKUP_POOL" ]; then
        if [[ "$IS_TEST" == "false" ]]; then            
            log_message "Info: Sending incremental snapshot from $LAST_SNAP_BACKUP_POOL to $SNAP_NAME to backup pool: $BACKUP_POOL."
            zfs send -R -I "$LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP" "$SNAP_NAME" | zfs receive -Fdu "$BACKUP_POOL"
            
            # Capture/Log the exit status of the zfs send command
            ZFS_SEND_EXIT_CODE=$?
            if [ $ZFS_SEND_EXIT_CODE -eq 0 ]; then
                log_message "Info: Successfully sent incremental snapshot from $LAST_SNAP_BACKUP_POOL to $SNAP_NAME to backup pool: $BACKUP_POOL."
                log_snapshot_transfer $SNAP_NAME $BACKUP_POOL
            else
                log_message "Error: Failed to send incremental snapshot from $LAST_SNAP_BACKUP_POOL to $SNAP_NAME to backup pool: $BACKUP_POOL. ZFS_SEND_EXIT_CODE: $ZFS_SEND_EXIT_CODE"
            fi            
        else
            log_message "Info: Skipping ZFS incremental send to $BACKUP_POOL because IS_TEST is true. LAST_SNAP_BACKUP_POOL: $LAST_SNAP_BACKUP_POOL | SNAP_NAME: $SNAP_NAME"
            log_message "Info: Here's the command if running in 'LIVE' mode: zfs send -R -I ${LAST_SNAP_SOURCE_POOL_SENT_TO_BACKUP} ${SNAP_NAME} | zfs receive -Fdu ${BACKUP_POOL}"
        fi
    else
        if [[ "$IS_TEST" == "false" ]]; then
            log_message "Info: Sending full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL."
            zfs send -R "$SNAP_NAME" | zfs receive -Fdu "$BACKUP_POOL"
            
            # Capture/Log the exit status of the zfs send command
            ZFS_SEND_EXIT_CODE=$?
            if [ $ZFS_SEND_EXIT_CODE -eq 0 ]; then
                log_message "Info: Successfully sent full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL."
                log_snapshot_transfer $SNAP_NAME $BACKUP_POOL
            else
                log_message "Error: Failed to send full snapshot $SNAP_NAME to backup pool: $BACKUP_POOL. ZFS_SEND_EXIT_CODE: $ZFS_SEND_EXIT_CODE"
            fi 
        else
            log_message "Info: Skipping ZFS full send to $BACKUP_POOL because IS_TEST is true. LAST_SNAP_BACKUP_POOL: $LAST_SNAP_BACKUP_POOL | SNAP_NAME: $SNAP_NAME"
            log_message "Info: Here's the command if running in 'LIVE' mode: zfs send -R ${SNAP_NAME} | zfs receive -Fdu ${BACKUP_POOL}"
        fi
    fi
fi

# TODO: TEST THIS!
cleanup_snapshots() {  
    local SNAP_COUNT=0
    local SNAP_LIMIT=$RETENTION_PERIOD
    local MINIMUM_SNAPSHOTS=1

    for POOL in "${REQUIRED_POOLS[@]}"; do
        if ! zpool list | grep -q "$POOL"; then
            log_message "Warning: Pool $POOL is offline-will use historical logs for validation."
        fi

        SNAPSHOT_COUNT=$(zfs list -H -t snapshot -o name "$POOL" | grep "$SNAP_TYPE" | wc -l)

        log_message "Info: $SNAPSHOT_COUNT $SNAP_TYPE snapshots exist for ZFS pool $POOL before cleanup."
        
        if (( SNAPSHOT_COUNT <= MINIMUM_SNAPSHOTS )); then
            log_message "Warning: Skipping cleanup in $POOL-only $SNAPSHOT_COUNT snapshot(s) left!"
            continue
        fi

        # Process snapshot cleanup
        zfs list -H -t snapshot -o name,creation "$POOL" | grep "$SNAP_TYPE" | sort -k2 | while read -r SNAP CREATION; do
            TOTAL_SNAPSHOTS=$(zfs list -H -t snapshot -o name "$POOL" | grep "$SNAP_TYPE" | wc -l)

            # Ensure cleanup only removes excess snapshots while keeping the required amount
            if (( TOTAL_SNAPSHOTS - SNAP_COUNT <= SNAP_LIMIT )); then
                log_message "Info: Retention policy met - stopping cleanup in $POOL (keeping $SNAP_LIMIT snapshots)"
                break
            fi

            # Ensure snapshot exists in *all* backup pools
            local safe_to_delete=true
            for BACKUP_POOL in "${REQUIRED_POOLS[@]}"; do
                if ! zfs list -H -t snapshot -o name "$BACKUP_POOL" | grep -q "$SNAP"; then
                    log_message "Warning: $SNAP is missing from $BACKUP_POOL-skipping deletion!"
                    safe_to_delete=false
                    break
                fi
            done

            # Final deletion logic
            if [[ "$safe_to_delete" == true && $(snapshot_sent_to_all_pools "$SNAP") == true ]]; then
                log_message "Info: Safe to delete snapshot $SNAP."
                if [[ "$IS_TEST" == "false" ]]; then
                    zfs destroy -r "$SNAP"
                    log_message "Info: Snapshot $SNAP destroyed-record retained in history log ($SNAPSHOT_TRANSFER_HISTORY_LOG)."
                else
                    log_message "Info: Skipping deletion (IS_TEST=true): Would have destroyed: $SNAP"
                fi
            else
                log_message "Warning: Retaining $SNAP due to incomplete backup validation!"
            fi            

            ((SNAP_COUNT++))
        done

        SNAPSHOT_COUNT=$(zfs list -H -t snapshot -o name "$POOL" | grep "$SNAP_TYPE" | wc -l)
        log_message "Info: $SNAPSHOT_COUNT $SNAP_TYPE snapshots exist for ZFS pool $POOL after cleanup."
    done

    # Send notification based on results
    if (( SNAP_COUNT == 0 )); then
        send_discord_notification "Info: **Snapshot Cleanup Complete** No snapshots found for cleanup."
    else
        send_discord_notification "Info: **Snapshot Cleanup Complete** $SNAP_COUNT snapshots and dependent datasets cleaned up."
    fi
}

# Log any existing snapshots automatically for each backup pool before cleanup:
log_message "Info: Logging existing snapshots (if they don't already exist) for all REQUIRED_POOLS ($REQUIRED_POOLS)"
for POOL in "${REQUIRED_POOLS[@]}"; do
    log_existing_snapshots $POOL
done

# Cleanup old snapshots - call the function to cleanup older snapshots based on retention period
log_message "Info: Checking retention period (${RETENTION_PERIOD}) and cleaning up older snapshots."
cleanup_snapshots

# Show pool and dataset sizes after new snapshot is sent to backup:
log_message "Info: Getting pool and dataset sizes after new snapshot is sent to backup:
$(zfs list -r -o name,used,available "$SOURCE_POOL" | column -t)
$(zfs list -r -o name,used,available "$BACKUP_POOL" | column -t)"

# send message 
if [[ "$IS_TEST" == "false" ]]; then
    # Verify snapshot exists in backup pool
    log_message "Info: Verifying snapshot $SNAP_ENDING in backup pool $BACKUP_POOL."
    if zfs list -H -t snapshot -o name | grep -q "^$BACKUP_POOL@$SNAP_ENDING"; then
        send_discord_notification ":white_check_mark: **ZFS ${SNAP_TYPE^} Backup Completed Successfully for ${SOURCE_POOL}** - Snapshot ${SNAP_NAME} verified as sent to ${BACKUP_POOL}. *(see $LOG_FILE for more details)*"    
    else
        send_discord_notification ":x: **ZFS Backup Error** - Snapshot $SNAP_ENDING did NOT arrive in $BACKUP_POOL!"
        exit 1
    fi    
else
    send_discord_notification ":white_check_mark::test_tube: **_Test_ run of ZFS ${SNAP_TYPE^} Backup Completed Successfully** - Snapshot ${SNAP_NAME} would have been created and sent to ${BACKUP_POOL} if IS_TEST were set to 'false'. *(see $LOG_FILE for more details)*"    
fi

# Add separator for log file for next run:
log_message "End of ZFS Backup Process\n=========="