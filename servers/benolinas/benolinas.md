# Network Attached Storage (NAS) Server
- 2024.07.12
- Specified ZFS RAID0 for root system - 65GB partition
- Installed Proxmox VE 8.2 (updated 2024.04.24)
- fullname: benolinas.krimmhouse.local
- URL: https://192.168.1.103:8006
- 2024.07.31 - installed new SSD:
	- 500GB capacity
	- Samsung 870 EVO - V-NAND SSD
	- Model: MZ-77E500

# Physical Machine info:
- Product: MID TOWER PC
- MODEL: DELL Optiplex 755
	
# Install NFS (Network File System) for Linux Sharing
```
apt install nfs-kernel-Server
```
- export the zfs filesystem by adding the following line to /etc/exports 
- no_root_squash allows Docker client to add additional users as needed to the share and take ownership of specific directories that should only be used by a specific service
/naspool/share 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

- Apply the Export:
```
exportfs -a
systemctl restart nfs-kernel-server

# Verify the mount options:
mount | grep naspool
```

# Add nasbackup User (for backing up files to nas without root access)
```
adduser nasbackup
```
- Enter a password when prompted and verify by typing password again
- Edit SSH config to allow user to connect:
```
nano /etc/ssh/sshd_config
```

# Add "newuser" to the "AllowUsers"
- Add line under "Authentication" section in format (AllowUsers username1 username2 etc.)
```
AllowUsers root nasbackup
```
- Create backup directories for docker containers (-p option will ensure parent directories are also created):
```
mkdir -p /naspool/backups/benolilab-docker/container-volumes
```
- Change owner and grant permissions to read/write for nasbackup user on backup directory:
```
chown nasbackup -R /naspool/backups/benolilab-docker
chmod -R u+rw /naspool/backups/benolilab-docker
```
- Restart the SSH service
```
systemctl restart sshd
```

# Setup External Backup for ZFS Pool
Added external drives (12 TB)
List new disks
```
lsblk
```
Identify the ZFS Pool
```
zpool list
```
Format the USB Drive as a ZFS Pool (If Not Already)
If your USB drive isn't formatted for ZFS yet, create a new ZFS pool on it:

*NOTE:* Replace naspool_backup1 with a name for your backup pool, and "sdg" with the device/disk path using -f will force the pool to be created and ignores partitions (all data on the disk will be deleted)
```
zpool create -f naspool_backup1 /dev/sdg
zpool create -f naspool_backup2 /dev/sdh
```

## Automatic ZFS Backups
Create or upload script file:
```
nano /opt/scripts/naspool_zfs_backup/zfs_backup.sh
```
Paste the script text from ./scripts/zfs_backup.sh and save (CTRL+X, then Y, then Enter).

Make the scripts directory executable:
```
chmod -R +x /opt/scripts
```

Setup dependency (jq) to use for json formatting of discord messages used in script:
```
apt update && apt install jq -y
```

Create a "secrets" directory in the /opt/scripts/naspool_zfs_backup and upload the .zfs_backups_discord_webhook file from secrets
NOTE: This is used in the bash scripts so that secrets are not kept in source control.

Schedule with Cron:
NOTE: This has since been setup with a docker container running supercron
```
# List cron jobs:
crontab -l

#View cron service: 
systemctl status cron

# Edit crontab (add a job)
crontab -e
```
Add this line to run the script daily at 4am:
Note: this is the setup for each of the cron tasks (one for each of the backup periods: daily, weekly, monthly, and another for yearly)
```
# Daily snapshot at 4am, retain 7 snapshots
0 4 * * * /opt/scripts/naspool_zfs_backup/zfs_backup.sh daily 7

# Weekly snapshot on Sunday at 4am, retain 5 snapshots
0 4 * * 0 /opt/scripts/naspool_zfs_backup/zfs_backup.sh weekly 5

# Monthly snapshot on the 1st at 4am, retain 3 snapshots
0 4 1 * * /opt/scripts/naspool_zfs_backup/zfs_backup.sh monthly 3

# Yearly snapshot on January 1st at 4am, retain 1 snapshots
0 4 1 1 * /opt/scripts/naspool_zfs_backup/zfs_backup.sh yearly 1
```

Alternative - with log and discord message (but this has since been built into the main script)
Note: This also logs the output to /var/log/zfs_backup.log and notifies via discord if the cron job fails - this has since been built into the backup script
```
0 4 * * * /opt/scripts/naspool_zfs_backup/zfs_backup.sh >> /var/log/zfs_backup.log 2>&1 || curl -H "Content-Type: application/json" -X POST -d '{"content": ":x: **ZFS Backup Failed!** The script did not execute properly."}' https://discord.com/api/webhooks/YOUR_WEBHOOK_URL

# TO DISABLE, either remove the line entirely or add a comment, like so (then save and exit):
# 0 4 * * * /opt/scripts/...
```

To check snapshots on the backup pool:
```
zfs list -t snapshot | grep $BACKUP_POOL
```

## Manual ZFS Backups:
*NOTE: This is needed for the initial backup and full-send to the backup pool(s)*
Create a Snapshot of Your Pool
Take a snapshot of your main ZFS pool (naspool in this example):
The -r flag ensures snapshots are recursive for all datasets.
```
zfs snapshot -r naspool@daily_backup_YYYYMMDD

# View Snapshots with:
zfs list -t snapshot

# View or list snapshots for a specific pool
zfs list -t snapshot naspool

# or use the following to view all snapshots for all pools:
zfs list -H -t snapshot -o name

# View more details:
zfs list -r -t snapshot -o name,used,referenced,creation naspool

# View shorter format, names only (useful for scripting): 
zfs list -H -o name -t snapshot

# View snapshot list that are older than a specific time frame (in this case older than 2 hours)
# The date comparison can be changed to something like '3 days ago', '12 weeks ago' etc.
# Example to run in terminal for debugging:
	zfs list -H -t snapshot -o name,creation | grep "daily" | awk -F ' ' -v date="$(date -d '2 hours ago' +%s)" '
	{
		# Convert the creation date to a Unix timestamp
		cmd = "date -d \"" $2 " " $3 " " $4 " " $5 " " $6 "\" +%s"
		cmd | getline creation_time
		close(cmd)
    
		# Compare the creation time with the date from 2 hours ago
		if (creation_time < date) {
			print $1
		}
	}'

# Or cleaner way without relying on awk:
	SNAP_TYPE="daily" &&
	DATE_FILTER="$(date -d '2 hours ago' +%s)" &&
	zfs list -H -t snapshot -o name,creation | grep "$SNAP_TYPE" | while read -r SNAP CREATION; do
		CREATION_TIMESTAMP=$(date -d "$CREATION" +%s)
		if (( CREATION_TIMESTAMP < DATE_FILTER )); then
			echo "Processing snapshot: $SNAP"
			# Add your processing commands here
		fi
	done
```

Send the Snapshot to the USB Drive
To perform a full backup:
This sends all datasets, preserving properties and snapshots.
-R sends the entire hierarchy (all datasets and snapshots).
-F forces a rollback on the destination if needed.
-d drops the source pool name when receiving, so sourcepool/dataset becomes targetpool/dataset.
```
zfs send -R naspool@daily_backup_YYYYMMDD | zfs receive -Fdu naspool_backup1
```

## Incremental Backups (After the First Backup)

For incremental backups:

Change directory to the script on the server 
```
cd /opt/scripts/naspool_zfs_backup
```

Run the script manually in "live" mode:
```
bash zfs_backup.sh daily 7 --live
```

1. Take a new snapshot:
```
zfs snapshot -r naspool@backup2
```
2. Send only the differences since the last snapshot:
```
zfs send -R -i naspool@backup naspool@backup2 | zfs receive -Fdu naspool_backup1

# Examples:
zfs send -R -i naspool@daily_backup_20250418 naspool@daily_backup_20250509 | zfs receive -Fdu naspool_backup1
zfs send -R -i naspool@daily_backup_20250418 naspool@daily_backup_20250509 | zfs receive -Fdu naspool_backup2
```

3. Delete old snapshots if needed:
```
zfs destroy naspool@backup
```

4. View pool size:
*Hint - open in a new terminal to "watch" as zfs send/receive is processing*
```
zfs list -r -o name,used,available naspool_backup1
```

You can alternatively call a custom script - see zfs_snapshot_send_progress.sh within the scripts directory.
Once SSH'd into the NAS server, change directory to the scripts directory
```
cd /opt/scripts/naspool_zfs_backup
```
Run the progress script with the estimated start-time for the ZFS send, for example:
```
bash zfs_snapshot_send_progress.sh "2025-09-18 10:59:38" naspool_backup1
```

## Swapping disks:

When swapping disks, always export the active pool first:
```
zpool export naspool_backup1
# OR:
zpool export naspool_backup2
```
Then physically swap the disk.
Import the New Backup Disk When Inserted:
```
zpool import naspool_backup1
# OR:
zpool import naspool_backup2
```
Use ZFS Send/Receive for Incremental Backups:
Example:
```
zfs send -R -i naspool@lastbackup naspool@newbackup | zfs receive -F backup1/naspool_backup
```
Label the Physical Drives:
Physically marking disks as backup1 and backup2 helps avoid confusion when rotating.

## Camera File Cleanup:
See cleanup-camera-uploads [README](https://github.com/Three50seven/benoli-homelab/tree/main/servers/benolinas/scripts/cleanup-camera-uploads).
Cron tab entry:
```
0 3 * * * /opt/scripts/cleanup-camera-uploads/cleanup-camera-uploads.sh --delete
```
