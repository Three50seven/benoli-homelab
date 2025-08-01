#!/bin/bash

# cleanup-trashed.sh - Remove .trashed files from FolderSync upload directories
# Usage: ./cleanup-camera-uploads.sh [--dry-run|--delete]

FOLDERSYNC_DIR="/naspool/share/benolilab-docker/foldersync"
LOG_FILE="/var/log/foldersync-cleanup.log"

# Function to show usage
show_usage() {
    echo "Usage: $0 [--dry-run|--delete]"
    echo "  --dry-run    Show what files would be deleted (default)"
    echo "  --delete     Actually delete the files"
    echo
    echo "Removes .trashed-* files older than 1 day from */sftp/upload/ directories"
    exit 1
}

# Function to log messages
log_message() {
    echo "$(date): $1" | tee -a "$LOG_FILE"
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

echo "Searching for .trashed-* files older than 1 day in $FOLDERSYNC_DIR"
echo "Looking in */sftp/upload/ subdirectories only"
echo

# Find files matching criteria
FILES=$(find "$FOLDERSYNC_DIR" -path "*/sftp/upload/*" -name ".trashed-*" -type f -mtime +1)

if [ -z "$FILES" ]; then
    echo "No .trashed-* files found that are older than 1 day"
    log_message "No .trashed-* files found for cleanup"
    exit 0
fi

# Count files
FILE_COUNT=$(echo "$FILES" | wc -l)

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN - Would delete $FILE_COUNT file(s):"
    echo "----------------------------------------"
    echo "$FILES"
    echo "----------------------------------------"
    echo "To actually delete these files, run: $0 --delete"
    log_message "Dry run found $FILE_COUNT .trashed-* file(s) that would be deleted"
else
    echo "DELETING $FILE_COUNT file(s):"
    echo "------------------------------"
    echo "$FILES"
    echo "------------------------------"
    
    # Actually delete the files
    find "$FOLDERSYNC_DIR" -path "*/sftp/upload/*" -name ".trashed-*" -type f -mtime +1 -delete
    
    if [ $? -eq 0 ]; then
        echo "Successfully deleted $FILE_COUNT .trashed-* file(s)"
        log_message "Successfully deleted $FILE_COUNT .trashed-* file(s)"
    else
        echo "Error occurred during deletion"
        log_message "Error occurred during deletion of .trashed-* files"
        exit 1
    fi
fi