# Network Attached Storage (NAS) Server
2024.07.12
Specified ZFS RAID0 for root system - 65GB partition
Installed Proxmox VE 8.2 (updated 2024.04.24)
fullname: benolinas.krimmhouse.local
URL: https://192.168.1.103:8006
2024.07.31 - installed new SSD:
	500GB capacity
	Samsung 870 EVO - V-NAND SSD
	Model: MZ-77E500

# Physical Machine info:
Product: MID TOWER PC
MODEL: DELL Optiplex 755
	
# Create ZFS Pool with remaining diskspace:
## See ...\Dropbox\Main\HomeServers\linux-notes\partition-storage-device-linux.md for notes on using the rest of the partition not used by the root file system of Proxmox
## Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
df -Th

# See ...\Dropbox\Main\HomeServers\linux-notes\zfs-file-system-notes.md FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
zpool list
OUTPUT SHOULD LOOK SOMETHING LIKE THIS:
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
naspool  7.25T   356G  6.90T        -         -     0%     4%  1.00x    ONLINE  -
rpool    63.5G  1.78G  61.7G        -         -     0%     2%  1.00x    ONLINE  -
zbarrel   928G   305G   623G        -         -     0%    32%  1.00x    ONLINE  -
zkeg      400G  1.95M   400G        -         -     0%     0%  1.00x    ONLINE  -

# Potentially remove the nag (popop warning) about licensing in Proxmox Web Manager:
https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/

# Update the APT (Advance Package Tool) Repositories in Proxmox Host:
# Guide: https://benheater.com/bare-metal-proxmox-laptop/amp/
	# Comment out the enterprise repositories - using Command Line:
	sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/pve-enterprise.list
	sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/ceph.list

# Add the community repositories
	echo -e '\n# Proxmox community package repository' >> /etc/apt/sources.list
	echo "deb http://download.proxmox.com/debian/pve $(grep CODENAME /etc/os-release | cut -d '=' -f 2) pve-no-subscription" >> /etc/apt/sources.list
	
# If you get an error trying to get apt packages:
	ping www.google.com
	nano /etc/resolv.conf
	confirm nameserver is correct
	
	--also, you can run: dpkg --configure -a
	--f apt is interrupted for some reason, packages that have been downloaded and unpacked may not have been fully configured, or installed.
	--he --configure option causes dpkg to finish configuration of partially installed packages, and the -a indicates that rather than a specific package, all unpacked, but unconfigured packages should be processed.

# Then run the following to clean and update:
	apt clean && apt update
	
# Run upgrade to upgrade all packages to latest:
	#NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
	#Reference: https://www.baeldung.com/linux/list-upgradable-packages
	apt upgrade	

# Install NFS (Network File System) for Linux Sharing
```
apt install nfs-kernel-Server
```
- export the zfs filesystem by adding the following line to /etc/exports
/naspool/share 192.168.1.0/24(rw,sync,no_subtree_check)

- Apply the Export:
```
exportfs -a
systemctl restart nfs-kernel-server
```

==========================
CREATE PROXMOX BACKUPS
==========================
References: https://www.vinchin.com/vm-backup/proxmox-offsite-backup.html
	https://pve.proxmox.com/wiki/Backup_and_Restore
	By default additional mount points besides the Root Disk mount point are not included in backups. 
	For volume mount points you can set the Backup option to include the mount point in the backup. 
	Device and bind mounts are never backed up as their content is managed outside the Proxmox VE storage library.

# Add nasbackup User (for backing up files to nas without root access)
adduser nasbackup

- Enter a password when prompted and verify by typing password again
- Edit SSH config to allow user to connect:
nano /etc/ssh/sshd_config

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

# Setup External Backup for naspool
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
NOTE: Replace naspool_backup1 with a name for your backup pool, and "sdg" with the device/disk path
	using -f will force the pool to be created and ignores partitions (all data on the disk will be deleted)
```
zpool create -f naspool_backup1 /dev/sdg
zpool create -f naspool_backup2 /dev/sdh
```
TBD - 2025.03.14 - Left off here

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
