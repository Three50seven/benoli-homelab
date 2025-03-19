# ZFS File System on Proxmox Notes
https://www.youtube.com/watch?v=9H09xnhlCQU&t=389s
sudo zpool create nas-pool raidz1 /dev/sdc /dev/sdd /dev/sde /dev/sdf

sudo zpool create nas-pool mirror /dev/sdc /dev/sdd mirror /dev/sde /dev/sdf

rsync -azr --info=progress2 --delete /mnt/sdb2/MEDIA-NAS_BackupPriorToLinux/ffmpegOutput/ /nas-pool/share/ffmpegOutput/

https://docs.oracle.com/cd/E19253-01/819-5461/gbchy/index.html
--prepare zfs pool for new server attachment
zpool export nas-pool
--or to force disconnects:
sudo zpool export -f nas-pool

--view zfs pools (should see nas-pool)
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