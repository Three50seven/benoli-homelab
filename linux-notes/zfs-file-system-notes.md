# ZFS File System on Proxmox Notes
https://www.youtube.com/watch?v=9H09xnhlCQU&t=389s
zpool create naspool raidz1 /dev/sdc /dev/sdd /dev/sde /dev/sdf

zpool create naspool mirror /dev/sdc /dev/sdd mirror /dev/sde /dev/sdf

rsync -azr --info=progress2 --delete /mnt/sdb2/MEDIA-NAS_BackupPriorToLinux/ffmpegOutput/ /nas-pool/share/ffmpegOutput/

https://docs.oracle.com/cd/E19253-01/819-5461/gbchy/index.html
--prepare zfs pool for new server attachment
zpool export nas-pool
--or to force disconnects:
sudo zpool export -f nas-pool

--view zfs pools (should see naspool)
zpool import 

--attach to new server and rename to naspool:
zpool import nas-pool naspool

--MAKE MKV SETUP:
https://forum.makemkv.com/forum/viewtopic.php?f=3&t=224


--MOUNT DVD/CDROM:
sudo mount /dev/cdrom /media
 ## you can use your custom mount point as well if this is on your desktop or somewhere else
 You should be able to see the files under /media folder now
 
rsync -ah --info=progress2 /mnt/sdb /naspool/sdbbak

rsync -ah --info=progress2 /naspool/sdbbak /mnt/sdb 

robocopy S: H:\NAS_Backup /E /Z /R:3 /W:5 /MT /LOG:H:\NAS_Backup\robocopy_log.txt


========================HDD Drive Issue:===================
REF: https://serverfault.com/questions/594372/loss-of-data-when-trying-to-fix-ext4-group-descriptors-corrupted
Ran testdisk: following this article: https://recoverit.wondershare.com/file-recovery/recover-data-from-ext4.html
Disk /dev/sdb - 1000 GB / 931 GiB - CHS 121601 255 63

     Partition                  Start        End    Size in sectors

  Linux filesys. data         2048 1953523711 1953521664 [Linux filesystem]
superblock 0, blocksize=4096 []
superblock 32768, blocksize=4096 []
superblock 98304, blocksize=4096 []
superblock 163840, blocksize=4096 []
superblock 229376, blocksize=4096 []
superblock 294912, blocksize=4096 []
superblock 819200, blocksize=4096 []
superblock 884736, blocksize=4096 []
superblock 1605632, blocksize=4096 []
superblock 2654208, blocksize=4096 []

To repair the filesystem using alternate superblock, run
fsck.ext4 -p -b superblock -B blocksize device

fsck.ext4 -p -b 0 -B 4096 /dev/sdb1

 e2fsck -b 0 /dev/sdb1
 mount /dev/sdb1 /mnt/sdb
 
 =============CREATED BACKUP OF RECOVERED DATA:================
# REF: https://bobcares.com/blog/rsync-from-linux-to-windows-share/
# From Proxmox Shell:
 cd /mnt
 mkdir mediaservershare
 
# Mount Windows Share in Proxmox:
 mount -t cifs -o username=local_admin //[IP ADDRESS]/Share /mnt/mediaservershare
 
# Run Rsync to copy data:
 rsync -ah --info=progress2 /mnt/sdb /mnt/mediaservershare/nas-server-sdb-bak
 https://serverfault.com/questions/796330/how-do-i-set-destination-permissions-with-rsync-chown-chmod

# Resume an Interrupted ZFS Send/Receive
Yes, you can resume interrupted zfs send and zfs receive operations in Proxmox by using the receive_resume_token property on the receiving end, allowing you to pick up where the transfer left off. 
Here's a more detailed explanation:

    ZFS Send/Receive:
    ZFS provides the zfs send and zfs receive commands for replicating datasets, including snapshots, between systems. 

## Resuming Transfers:
If a zfs send and zfs receive process is interrupted, you can resume it by using the receive_resume_token property on the receiving end. 
Finding the Token:
The receive_resume_token is a long string that is populated on the receiving side after the zfs send process has started. 
Resuming the Process:
You can use the zfs receive -s <token> command to resume the transfer. 
Proxmox Specifics:
Proxmox itself doesn't have a built-in mechanism for automatically resuming ZFS send/receive operations, but you can use the zfs send and zfs receive commands directly. 
Proxmox Backup Server (PBS):
Proxmox Backup Server (PBS) can be used for backing up Proxmox, and it can also utilize ZFS for storage, but it's important to note that PBS uses a block-level backup approach, not directly relying on ZFS send/receive for transferring VM/CT volumes. 

Example:

    Start the send:

`
    zfs send -R rpool/data/vm-100-disk-0 | zfs receive -F rpool/data/vm-200-disk-0
`
    Interrupt the process: (Simulate an interruption)

    # Press Ctrl+C to interrupt the process

    Find the receive_resume_token:

`
    zfs get -H send_receive_token rpool/data/vm-200-disk-0
`
    Resume the receive:

`
    zfs receive -s <token> rpool/data/vm-200-disk-0
`
    Replace <token> with the actual token value obtained in the previous step.

# List ZFS Pool info:
```
zfs list -r -o name,used,available,referenced naspool_backup2
```


# Rename a snapshot and its descendant datasets:
```
zfs rename naspool@backup_20250314 naspool@daily_backup_20250314
zfs rename naspool@backup_20250315 naspool@daily_backup_20250315
zfs rename naspool@backup_20250316 naspool@daily_backup_20250316
zfs rename naspool/backups@backup_20250314 naspool/backups@daily_backup_20250314
zfs rename naspool/backups@backup_20250315 naspool/backups@daily_backup_20250315
zfs rename naspool/backups@backup_20250316 naspool/backups@daily_backup_20250316
zfs rename naspool/share@backup_20250314 naspool/share@daily_backup_20250314
zfs rename naspool/share@backup_20250315 naspool/share@daily_backup_20250315
zfs rename naspool/share@backup_20250316 naspool/share@daily_backup_20250316
```

# Rename datasets and destroy empty parent afterwards:
```
# First rename datasets to match main naspool
zfs rename naspool_backup1/naspool_backup_20250314/backups naspool_backup1/backups
zfs rename naspool_backup1/naspool_backup_20250314/share naspool_backup1/share

zfs rename naspool_backup2/naspool_backup_20250314/backups naspool_backup2/backups
zfs rename naspool_backup2/naspool_backup_20250314/share naspool_backup2/share

# List all datasets for all pools
zfs list

# Or list for specifig pool:
zfs list -r naspool_backup1
zfs list -r naspool_backup2
```
The -r flag ensures that all nested datasets under naspool_backup1/naspool_backup_20250314 are destroyed.
So make sure the datasets are moved outside the parent first by renaming them (above)
```
zfs destroy naspool_backup1/naspool_backup_20250314
zfs destroy naspool_backup2/naspool_backup_20250314
```

# Restore ZFS Pool from Replicated ZFS Pool
1. Import the Backup Pool: Ensure the backup pool naspool_backup1 is imported and accessible.
```
zpool import naspool_backup1
```
2. Export the Damaged Pool: If the original pool naspool is still imported, export it to avoid conflicts.
```
# View status of naspool
zpool status naspool

# export ot avoid conflicts:
zpool export naspool
```
3. Recreate the Original Pool: If the original pool naspool is severely damaged, you may need to recreate it. This step assumes you have already exported the damaged pool.
```
# example: zpool create naspool <disk_devices> mirror <disk_devices_mirror>
# View disks/devices:
lsblk

# Command to re-create naspool
zpool create naspool mirror /dev/sdc /dev/sdd mirror /dev/sde /dev/sdf
```
4. Restore Datasets from Backup: Use zfs send and zfs receive to transfer datasets from the backup pool to the original pool. This can be done for each dataset individually or for the entire pool.

Send and Receive Entire Pool:
```
zfs send -R naspool_backup1@daily_backup_20250418 | zfs receive -F naspool
```

Send and Receive Individual Datasets:
```
zfs send naspool_backup1/dataset1@daily_backup_20250418 | zfs receive naspool/dataset1
zfs send naspool_backup1/dataset2@daily_backup_20250418 | zfs receive naspool/dataset2
# Repeat for all datasets
```

5. Verify the Restore: After restoring, verify the datasets and ensure they are correctly mounted.
```
zfs list
zfs mount -a
```