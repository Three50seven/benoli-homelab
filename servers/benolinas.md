2024.07.12
Specified ZFS RAID0 for root system - 65GB partition
Installed Proxmox VE 8.2 (updated 2024.04.24)
fullname: benolinas.krimmhouse.local
URL: https://192.168.1.103:8006
2024.07.31 - installed new SSD:
	500GB capacity
	Samsung 870 EVO - V-NAND SSD
	PN: MZ7L3500HBLU
	Model: MZ-77E500
	R-R-SEC-MZ-77E2T0
	SN: S6PXNU0X329038K
	WWN: 5002538F543442F3
	PSID: CM4Q7X088FH6GTMRUY9FG31V7FNWK3SN

#Physical Machine info:
Product: MID TOWER PC
MODEL: DELL Optiplex 755
	
#Create ZFS Pool with remaining diskspace:
##See ...\Dropbox\Main\HomeServers\linux-notes\partition-storage-device-linux.md for notes on using the rest of the partition not used by the root file system of Proxmox
##Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
df -Th

#See ...\Dropbox\Main\HomeServers\linux-notes\zfs-file-system-notes.md FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
zpool list
OUTPUT SHOULD LOOK SOMETHING LIKE THIS:
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
naspool  7.25T   356G  6.90T        -         -     0%     4%  1.00x    ONLINE  -
rpool    63.5G  1.78G  61.7G        -         -     0%     2%  1.00x    ONLINE  -
zbarrel   928G   305G   623G        -         -     0%    32%  1.00x    ONLINE  -
zkeg      400G  1.95M   400G        -         -     0%     0%  1.00x    ONLINE  -

#Potentially remove the nag (popop warning) about licensing in Proxmox Web Manager:
https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/

#Update the APT (Advance Package Tool) Repositories in Proxmox Host:
#Guide: https://benheater.com/bare-metal-proxmox-laptop/amp/
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

#Then run the following to clean and update:
	apt clean && apt update
	
#Run upgrade to upgrade all packages to latest:
	#NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
	#Reference: https://www.baeldung.com/linux/list-upgradable-packages
	apt upgrade	

#Install NFS (Network File System) for Linux Sharing
apt install nfs-kernel-Server

- export the zfs filesystem by adding the following line to /etc/exports
/naspool/share 192.168.1.0/24(rw,sync,no_subtree_check)

- Apply the Export:

exportfs -a
systemctl restart nfs-kernel-server

2024-12-08 - LEFT OFF HERE - AFTER DECIDING TO DITCH THE OMV SETUP (KEPT CRASHING)
--INSTALLING SMB SHARES AND MANAGING DIRECTLY FROM PROXMOX TO SKIP THE VM SETUP
====================
SETUP vmnas CONTAINER TO SHARE zpool
====================
https://www.naturalborncoder.com/linux/proxmox/2023/07/06/building-a-nas-using-proxmox-part-1/dddd
https://www.youtube.com/watch?v=Hu3t8pcq8O0&list=LLd
https://www.youtube.com/watch?v=hJHpVi9LGqc
https://blog.kye.dev/proxmox-cockpit

--Setup Cockpit and Debian 12 standard container for managing files and file shares
navigate to proxmox web interface
go to "local (benolinas)" > CT Templates > Templates and download Debian 12 standard
Click "Create CT"
LEAVE "unprivileged container" UNCHECKED - BUT BE WARNED THIS WILL GIVE GUEST ACCESS TO HOST files
	--we want this so zpool on host can be directly managed by the guest container with all the Samba and NFS etc. installed
pw: <PASSWORD>
use the Debian 12 standard template (downloaded earlier)
provided static ip: 192.168.3.18
left defaults except for specifying 2 core limit on cpu
install cockpit:
	apt update
	apt install cockpit --no-install-recommends
removed root from disallowed users that can login to Cockpit
	nano /etc/cockpit/disallowed-users
Navigate to Cockpit portal: https://192.168.3.18:9090/
login with root user setup during install

--Install add on packages to help with managing files in web interface GUI:
Go to URL for each > Latest under Releases > look for ".deb" file: 
wget each deb file to root directory
then install with: apt install ./*.deb 
after install, you may get an error/warning that package files can't be deleted
just delete them yourself: rem *.deb
cockpit-file-sharing - web GUI designed to manage Samba and NFS
	https://github.com/45Drives/cockpit-file-sharing	
	https://github.com/45Drives/cockpit-file-sharing/releases/download/v3.3.7/cockpit-file-sharing_3.3.7-1focal_all.deb
cockpit-navigator - web browser to navigate the file system
	https://github.com/45Drives/cockpit-navigator
	https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.10/cockpit-navigator_0.5.10-1focal_all.deb
cockpit-identities - better than default accounts - can also manage Samba passwords (for Windows file sharing)
	https://github.com/45Drives/cockpit-identities
	https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12-1focal_all.deb

--Add container mount points
CLI: (e.g. [pct set 103 -mp0 /host/dir,mp=/container/mount/point] where 103 = container id)
	pct set 101 -mp0 /naspool/share,mp=/mnt/naspool/share
	--verify mapping was added by viewing the lxc config: /etc/pve/nodes/NODE/lxc/ID.conf
	nano /etc/pve/nodes/benolinas/lxc/101.conf
	--you should see a line for mp0: /naspool/share, mp=/mnt/naspool/share
	
	--Also Add sdb Storage from host:
	pct set 101 -mp1 /mnt/sdb,mp=/mnt/sdb
	
--LEFT OFF HERE 7/16/2024
	
#Make sure zpool is listed as storage option for VMs and OSs:
go to the Proxmox of host machine on local IP, them go to Datacenter > Storage > Add > ZFS > Choose the zpool you wanted to add.
add mount point on fileserver (via proxmox web ui) - fileserver > Resources > Add
to start out - choose 3072 (3TB) for "Disk size"
leave Mount Point ID = 0
Storage = naspool
Path = /mnt/naspool

--User Management:
Using Cockpit UI - Go to Identities
Groups > + (add group) > Type: naspool-users
Then go to Identities > Users > + (add user) > Type: krimmhouse (or whatever you want your user to be named)

--FROM HOST

--Samba File Share:
Using Cockpit UI - Go to File Sharing
Server Description: krimmhouseNAS
ShareName: naspool
Share Description: NAS ZFS Pool on Debian LXC hosted on Proxmox
Path: /mnt/naspool	
	Could also create subdirectories etc. here if needing to separate storage spaces
Add Valid Groups: naspool-users
Check Windows ACLs: so that all file use Windows permissions and ignore Linux permissions

--RSYNC test file:	
	rsync -ah --progress source destination
	cd /naspool/subvol-101-disk-0
	mkdir idrive
	rsync -ah --progress /naspool/share/iDrive/ubuntu24bin/idriveforlinux.bin /naspool/subvol-101-disk-0/idrive/idriveforlinux.bin
	
	test larger amount (29.6)	
	cd /naspool/subvol-101-disk-0
	mkdir ffmpegoutput
	rsync -ah --progress /naspool/share/ffmpegOutput/_DisneyAnimatedClassics_Processed /naspool/subvol-101-disk-0/ffmpegoutput
	
	test 7z file:
	cd /naspool/share/
	mkdir copytest
	rsync -ah --progress /naspool/share/ffmpegOutput/_DisneyAnimatedClassics_Processed.7z /naspool/share/copytest/disneyprocessed.7z
	
	test 7z file:
	cd /naspool/subvol-101-disk-0
	mkdir compressedtest
	rsync -ah --progress /naspool/share/ffmpegOutput/_DisneyAnimatedClassics_Processed.7z /naspool/subvol-101-disk-0/compressedtest/disneyprocessed.7z

==========================
CREATE PROXMOX BACKUPS
==========================
References: https://www.vinchin.com/vm-backup/proxmox-offsite-backup.html
	https://pve.proxmox.com/wiki/Backup_and_Restore
	By default additional mount points besides the Root Disk mount point are not included in backups. 
	For volume mount points you can set the Backup option to include the mount point in the backup. 
	Device and bind mounts are never backed up as their content is managed outside the Proxmox VE storage library.