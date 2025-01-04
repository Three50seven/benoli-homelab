SETUP DATE: 2024.11.29 (TBD)
Specified ZFS RAID0 for root system - 65GB partition
Installed Proxmox VE 8.2 (updated 2024.04.24)
fullname: benolilab.krimmhouse.local
URL: https://192.168.1.102:8006 (TBD)
2024.11.29 - installed new SSD:
	500GB capacity
	Samsung 870 EVO - V-NAND SSD
	PN: MZ7L3500HBLU
	Model: MZ-77E500
	R-R-SEC-MZ-77E2T0
	SN: S6PXNU0X329024R
	WWN: 5002538F543442E5
	PSID: 22393P5Q293P7Y4RBGFUR961LYYVJ1KT

#Physical Machine info:
Product: MINI TOWER PC
MODEL: DELL Optiplex 7040

#Create ZFS Pool with remaining diskspace:
##See ...\Dropbox\Main\HomeServers\linux-notes\partition-storage-device-linux.md for notes on using the rest of the partition not used by the root file system of Proxmox
##Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
df -Th

#See ...\Dropbox\Main\HomeServers\linux-notes\zfs-file-system-notes.md FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
zpool list
root@benolilab:~# zpool list
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
rpool    63.5G  1.35G  62.2G        -         -     0%     2%  1.00x    ONLINE  -
zbarrel   464G   106K   464G        -         -     0%     0%  1.00x    ONLINE  -
zkeg      173G   108K   173G        -         -     0%     0%  1.00x    ONLINE  -

#Potentially remove the nag (popop warning) about licensing in Proxmox Web Manager:
https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/
2 Easy method:
2.1 Copy and paste following command to the terminal
(8.2.8 8.2.9 8.3.0 and up)
sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service

#Update the APT (Advance Package Tool) Repositories in Proxmox Host:
#Guide: https://benheater.com/bare-metal-proxmox-laptop/amp/
	# Comment out the enterprise repositories - using Command Line:
	sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/pve-enterprise.list
	sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/ceph.list

# Add the community repositories
	echo -e '\n# Proxmox community package repository' >> /etc/apt/sources.list
	echo "deb http://download.proxmox.com/debian/pve $(grep CODENAME /etc/os-release | cut -d '=' -f 2) pve-no-subscription" >> /etc/apt/sources.list

#Then run the following to clean and update:
	apt clean && apt update
	
#Run upgrade to upgrade all packages to latest:
	#NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
	#Reference: https://www.baeldung.com/linux/list-upgradable-packages
	apt upgrade
	
#Make sure zpool is listed as storage option for VMs and OSs:
go to the Proxmox of host machine on local IP, them go to Datacenter > Storage > Add > ZFS > Choose the zpool you wanted to add.

#Download Debian OS ISO:
Go to Local storage - ISO (or other storage if added as directory from ZFS drives)
Download: https://debian.osuosl.org/debian-cdimage/12.8.0/amd64/iso-dvd/debian-12.8.0-amd64-DVD-1.iso
Note: This was the latest URL from the Debian Host as of 2024.11.30 - check latest for updated version

#Setup debian server VM for docker engine:
name: vmdocker
OS - Use CD/DVD - debian-12.8 (downloaded earlier)
150GiB HD on zkeg
250GiB HD on zbarrel
CPU - 1 Sockets - 8 Cores, x86-64-v2-AES - leave all other defaults
Memory: 20480 MB (use most, i.e. 20 GB of the 32GB of RAM from proxmox host so that Docker can use most resources)
	-checked "top" command in linux and saw that there is ~25570 MiB free, so taking about 80-90% of this for the VM is recommended
	-set minumum to 8 GB: 8192 MB - Minimum Memory: Typically, setting the minimum memory to around 25-50% of the maximum memory is a good practice. For a VM with 20GB maximum memory, this would be:
		25% of 20GB: ( 20 \times 0.25 = 5 ) GB
		50% of 20GB: ( 20 \times 0.5 = 10 ) GB
		Suggested Minimum Memory:
		5GB to 10GB: This range should provide a balance between ensuring the VM can start and run essential services while leaving room for dynamic memory allocation as needed.
	-make sure ballooning is checked to ensure memory can be dynamically adjusted based on needs of the host and other VMs
Network: Leave default
Finish and start VM - run through Debian install
hostname: vmdocker.krimmhouse.local

#Install and check SSH server:
apt install openssh-server
systemctl status ssh

#Permit SSH Root login:
nano /etc/ssh/sshd_config
Find # Authentication: section > PermitRootLogin
Remove "#" from line that says PermitRootLogin and change value to "yes"
exit and save the nano editor

#Setup Debian apt sources:
sudo nano /etc/apt/sources.list
 - view latest: https://wiki.debian.org/SourcesList
 - e.g. (comment out deb cdrom line)
deb-src http://deb.debian.org/debian bookworm main non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main non-free-firmware

#Update Debian installation:
apt update
apt upgrade

#Set static IP on Debian 12 VM (note you'll need root user for this):
https://www.linuxtechi.com/configure-static-ip-address-debian/
ip add show
 - get the name of the network interface (in this case it's ens18)
nano /etc/network/interfaces

Replace the line ‘allow-htplug ens18’ with ‘auto ens18‘ and change dhcp parameter to static.  Below is my sample file, change interface name and ip details as per your environment.

auto ens18
iface ens18 inet static
        address 192.168.1.63/24
        network 192.168.1.0
        broadcast 192.168.1.255
        gateway 192.168.1.1
        dns-nameservers 8.8.8.8

#Setup Docker on new Debian Server (vmdocker):
- NOTE: SSH into new debian server so that commands can be copy pasted:
- src: https://docs.docker.com/engine/install/debian/
	## Add Docker's official GPG key:
	apt-get update
	apt-get install ca-certificates curl
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	
echo \ 
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

#Install Docker packages:  
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#Verify installation was successful:
docker run hello-world

--remove hello-world container after test:
docker rm <container_id>

-view version and other info: 
docker info
--results:
Client: Docker Engine - Community
 Version:    27.3.1
 Context:    default
 Debug Mode: false
 Plugins:
  buildx: Docker Buildx (Docker Inc.)
    Version:  v0.17.1
    Path:     /usr/libexec/docker/cli-plugins/docker-buildx
  compose: Docker Compose (Docker Inc.)
    Version:  v2.29.7
    Path:     /usr/libexec/docker/cli-plugins/docker-compose
	
#Mount the NAS server directory and localmedia directory for library files:
https://support.plex.tv/articles/201122318-mounting-network-resources/
-install cifs-utils:
	apt install cifs-utils
-install nfs-common:
	apt install nfs-common
-make mount directories:
	mkdir /mnt/naspool
	mkdir /mnt/sdb
--NOTE: CHOOSE EITHER CIFS OR NFS:
-mount NAS directory as CIFS (SMB):
	mount -t cifs //192.168.1.103/naspool /mnt/naspool -o rw,user=krimmhouse
-mount NAS directory as NFS:
	mount -t nfs 192.168.1.103:/naspool/share /mnt/naspool
-create partition on sdb in docker server:
	fdisk -l (list partitions)
	fdisk /dev/sdb (start fdisk on target disk)
	n (for new partition)
	-accept all defaults by just hitting enterprise
	w - write the new partition if everything looks correct
	lsblk - to show all disks and partitions (should now see sdb1 partition)
	- create an ext4 file-system (WARNING - THIS WILL ERASE ALL CONTENT ON THE DISK):
	mkfs.ext4 /dev/sdb1
	- finally mount the new ext4 disk partition:
	mount /dev/sdb1 /mnt/sdb	

#Edit fstab to auto-mount at boot:
--copy fstab file to backup directory (after making a backups directory, if it doesn't exist, update date in backup as needed)
	mkdir /backups
	cp  /etc/fstab   /backups/fstab_bak_20241204
<!--NO LONGER NEEDED FOR NFS DRIVE: 
	create credentials file for naspool:
	nano /etc/naspoolcredentials.txt 
	username=krimmhouse
	password=<PW FOR USER>
	CTRL+X, y to save/write new file-->
--list uuid for each drive:
	ls -al /dev/disk/by-uuid/
--edit fstab file:
	nano /etc/fstab
--add the lines:
	# local drive sdb1
	UUID=cbd4143f-b99b-4a77-93c8-714ea3d25325       /mnt/sdb        ext4    defaults        0       0
	# naspool (network)
	192.168.1.103:/naspool/share /mnt/naspool nfs defaults 0 0
	<!--OR, if you're using CIFS (note, you'll need the credentials file created - see above)
	//192.168.1.43/naspool  /mnt/naspool    cifs    iocharset=utf8,rw,credentials=/etc/naspoolcredentials.txt  0  0
	-->
	CTRL+X, y to save/write new file
--test fstab - check the last line for errors):
	findmnt --verify
	NOTE: Ignored udf,iso9660
--if everything looks okay, reload the mount fstab:
	systemctl daemon-reload

#Add TV Tuner device for plex container to use:
--To pass a USB device from Proxmox to a virtual machine (VM), 
	navigate to the VM's settings within the Proxmox web interface, go to the "Hardware" section, 
	and select "Add > USB Device"; then choose the specific USB device you want to passthrough by 
	either selecting it using its Vendor/Device ID or specifying the physical USB port it's 
	connected to on the Proxmox host.
device should be named something like: Hauppauge 955D
on docker vm, you should see the usb device now:
	lsusb
--install the following packages:
	apt update
	apt-get install wget bzip2 build-essential libncurses5-dev	
	apt-get install software-properties-common
	apt install python3-launchpadlib
	apt update
	nano /etc/apt/sources.list
	--add repo line manually (note jammy is the closest version of ubuntu that matches to debian 12 - you may need to check the site for newer versions if you have a newer OS install):
	--source: https://launchpad.net/~b-rad/+archive/ubuntu/kernel+mediatree+hauppauge
	--source for ubuntu debian matchup: https://askubuntu.com/questions/445487/what-debian-version-are-the-different-ubuntu-versions-based-on
	-- reference: https://forums.plex.tv/t/cannot-connect-usb-tuner-wih-the-official-plex-docker-image/228823
	deb [trusted=yes] https://ppa.launchpadcontent.net/b-rad/kernel+mediatree+hauppauge/ubuntu jammy main 
	deb-src [trusted=yes] https://ppa.launchpadcontent.net/b-rad/kernel+mediatree+hauppauge/ubuntu jammy main 	
	apt-get install linux-mediatree
	--firmware install if needed (Most North American TV Tuners DO NOT NEED THIS): apt-get install linux-firmware-hauppauge 
	--restart the vmdocker server via proxmox or ssh command (reboot)
	--install wscan for channel scanning:
	apt install w-scan -y
	--make tvtuner directory:
	mkdir /opt/tvtuner
	cd /opt/tvtuner
	--scan for ATSC channels in the United States
	w_scan -fa -c US > channels.conf
	--should see results e.g. ...
	473000: 8VSB(time: 00:51.098)         signal ok:        8VSB     f=473000 kHz (0:0:0)
	479000: 8VSB(time: 00:51.938)         signal ok:        8VSB     f=479000 kHz (0:0:0)
	485000: 8VSB(time: 00:52.778)
	...	
	803000: 8VSB(time: 03:40.331)
	tune to: 8VSB     f=473000 kHz (0:0:0) (time: 03:43.431)
	service is running. Channel number: 32:1. Name: 'WLKY-HD'
	service is running. Channel number: 32:2. Name: 'ME TV'
	service is running. Channel number: 32:4. Name: 'STORY'
	WARNING: unhandled stream_type: 1B
	---
	You should now be able to setup plex with docker-compose file below.
	
#Setup Plex in Docker Container:
ref: https://www.rapidseedbox.com/blog/plex-on-docker
- login to the docker vm and create the plex directories:
mkdir /plex
mkdir /plex/{database,transcode,media}
mkdir /opt/plex
- create docker compose file with nano editor:
nano /opt/plex/docker-compose.yml
- add contents of docker-compose:
--NOTE: if you want to add a new volume (i.e. for library files), add it to the volumes list Below
	- left of the : is the actual path and to the right is the path Plex will see.  
	- map the USB bus and dev/dvb directories so that the TVTuner can be used by the container from the host
	- add write permissions to allow plex to write to media directory for dvr recordings
		stat /mnt/naspool/Plex/library
		- use command above to confirm that localadmin is UID 1000 and Gid 1000 before adding to below record
		- Verify Permissions: Check that the permissions are correctly set by listing the directory contents:
		ls -l /mnt/naspool/Plex/library
=======================
services:
  plex:
	container_name: plex
	image: linuxserver/plex
	network_mode: host
	restart: unless-stopped
	environment:
	  - TZ=America/New_York
	  - PLEX_CLAIM=<GET CLAIM FROM https://www.plex.tv/claim/>
	  - PUID=1000
	  - PGID=1000
	volumes:
	  - /plex/database:/config
	  - /plex/transcode:/transcode
	  - /plex/media:/data
	  - /mnt/naspool:/naspool
	  - /mnt/sdb:/localmedia
	devices:
	  - /dev/bus/usb:/dev/bus/usb	
	  - /dev/dvb:/dev/dvb
=======================
cd /opt/plex
-deploy container as detached:
docker compose up -d
-view info about docker container (with -a shows all, even non-running containers):
docker ps -a

#Update Plex when needed (PRE WATCHTOWER):
cd /opt/plex
docker compose pull plex
docker compose down 
docker compose up -d
--when creating a new container, run with restart unless-stopped flag to restart on reboot
docker run -d --restart unless-stopped <image_name>
--for an existing container, run:
docker update --restart unless-stopped <container_name_or_id>
- remove old images (optional):
docker image prune

#Connect to Plex server via browser (on machine that is on the same local network):
http://192.168.1.63:32400/

#Add TV Tuner and do a channel scan:
Go to Settings > Manage > Live TV & DVR
--The USB device should now show - run a scan of channels and select "Local Broadcast Listings" as the guide info source
--Plex should then show you Live TV channels it found

#Migrate Media data as needed:
See benolinas-migrate-data.md for details

#Add plex library directories via settings to view media
Go to Settings > Manage > Libraries and add libraries as needed
You should see the NAS drive and local drive as added in the volumes within the docker-compose file

#Trouble-shooting memory issues - out of memory (OOM)
- set minumum memory to 16 GB on VM
- backup and modify sysctl.conf
mkdir /backups
	<!--NOTE: THIS DID NOT WORK WELL AND STOPPED CONNECTIONS TO PROXMOX
	cp /etc/sysctl.conf /backups/sysctl.conf_bak_20241211
	nano /etc/sysctl.conf
	- add line to sysctl and save:
	vm.overcommit_memory=2
	- apply changes:
	sysctl -p 

	reverted changes
	-->
cp /etc/modprobe.d/zfs.conf /backups/zfs.conf_bak_20241211
nano /etc/modprobe.d/zfs.conf
--change arc max from default of 3 GB to 8 GB: 
	--e.g. change: options zfs zfs_arc_max=3357540352 
	--to: options zfs zfs_arc_max=8589934592
--save file and apply changes:
update-initramfs -u
reboot



