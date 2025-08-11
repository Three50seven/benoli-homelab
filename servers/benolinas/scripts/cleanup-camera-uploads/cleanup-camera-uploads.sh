#!/bin/bash

# cleanup-trashed.sh - Remove .trashed files from FolderSync upload directories
# Usage: ./cleanup-camera-uploads.sh [--dry-run|--delete]

FOLDERSYNC_DIR="/naspool/share/benolilab-docker/foldersync"
LOG_FILE="/var/log/foldersync-cleanup.log"

# Define the path and name pattern to search within
PATH_PATTERN="*/sftp/upload/*"
NAME_PATTERN=".trashed-*"

# Define the number of days for file cleanup
DAYS_OLD=30

# Function to show usage
show_usage() {
    echo "Usage: $0 [--dry-run|--delete]"
    echo "  --dry-run    Show what files would be deleted (default)"
    echo "  --delete     Actually delete the files"
    echo
    echo "Removes $NAME_PATTERN files older than $DAYS_OLD days from $PATH_PATTERN directories"
    exit 1
}

# Function to log messages
log_message() {
    echo "$(date): $1" | tee -a "$LOG_FILE"

    # Also show the message in stdout
    echo -e "$1"
}

# Parse command line arguments
DRY_RUN=true
case "$1" in
    --dry-run)
        DRY_RUN=true
        ;;
    --delete)
        DRY_RUN=false
        ;;
    "")
        # Default to dry-run if no argument provided
        DRY_RUN=true
        ;;
    *)
        show_usage
        ;;
esac

# Check if directory exists
if [ ! -d "$FOLDERSYNC_DIR" ]; then
    echo "Error: Directory $FOLDERSYNC_DIR does not exist"
    exit 1
fi

echo "Searching for $NAME_PATTERN files older than $DAYS_OLD days in $FOLDERSYNC_DIR"
echo "Looking in subdirectories matching the pattern: $PATH_PATTERN"
echo

# Find files matching criteria
FILES=$(find "$FOLDERSYNC_DIR" -path "$PATH_PATTERN" -name "$NAME_PATTERN" -type f -mtime +$DAYS_OLD)

if [ -z "$FILES" ]; then
    log_message "No $NAME_PATTERN files older than $DAYS_OLD days were found for cleanup in $FOLDERSYNC_DIR matching the pattern: $PATH_PATTERN"
    exit 0
fi
# Count files
FILE_COUNT=$(echo "$FILES" | wc -l)

if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN - Would delete $FILE_COUNT file(s):"
    echo "----------------------------------------"
    echo "$FILES"
    echo "----------------------------------------"
    echo "To actually delete these files, run: $0 --delete"
    log_message "Dry-run found $FILE_COUNT $NAME_PATTERN file(s) that would be deleted"
else
    # log details and which files are being deleted
    log_message "DELETING $FILE_COUNT file(s):\n------------------------------\n$FILES\n------------------------------"
    
    # Actually delete the files
    find "$FOLDERSYNC_DIR" -path "$PATH_PATTERN" -name "$NAME_PATTERN" -type f -mtime +$DAYS_OLD -delete
    
    if [ $? -eq 0 ]; then
        log_message "Successfully deleted $FILE_COUNT $NAME_PATTERN file(s)"
    else
        log_message "Error occurred during deletion of $NAME_PATTERN files"
        exit 1
    fi
fi