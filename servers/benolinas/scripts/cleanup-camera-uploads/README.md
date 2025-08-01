# Cleanup Camera Script
This script gives more control over the cleanup process for .trashed camera files (images & videos) uploaded by FolderSync

For example, when you delete an image or video on Android, it gets prefixed/renamed with ".trashed-#######-" or something similar.  The image will then get uploaded again by FolderSync.  There would then be two copies on the NAS storage, e.g. image.jpg and .trashed-123456-image.jpg. To get around this, the `cleanup-camera-uploads.sh` script was created to get rid of the duplicate .trashed files.

Usage examples:
```
# See what would be deleted (default behavior)
./cleanup-trashed.sh
./cleanup-trashed.sh --dry-run

# Actually delete the files
./cleanup-trashed.sh --delete
```

Features:

- Safe by default: Runs in dry-run mode if no argument provided
- Clear output: Shows exactly which files will be/were deleted
- File counting: Tells you how many files are affected
- Logging: Logs actions to /var/log/foldersync-cleanup.log
- Error handling: Checks if directory exists and reports deletion errors
- Specific path matching: Only looks in */sftp/upload/ subdirectories

To set it up:
```
chmod +x cleanup-trashed.sh

# Test it first
./cleanup-trashed.sh --dry-run

# When ready, add to cron for automatic cleanup
crontab -e
# Add: 0 3 * * * /path/to/cleanup-trashed.sh --delete

# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of week (0 - 7) (Sunday=0 or 7)
# │ │ │ │ │
# │ │ │ │ │
# * * * * * command-to-run
```
The script will help you see exactly what's getting cleaned up before you commit to automatic deletion via cron.

Once you save and exit the crontab, the cron daemon picks it up automatically.

## To Verify

You can list your current cron jobs with:
```
crontab -l
```