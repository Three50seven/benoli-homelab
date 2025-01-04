2024.08.07
Press DEL Key to enter BIOS
Specified ZFS RAID0 for root system - 100GB partition
Installed Proxmox VE 8.2 (updated 2024.04.24)
fullname: benolinet.krimmhouse.local
URL: https://192.168.1.253:8006 (Temp until installed as main router)
MGMT interface: enp2s0

#Physical Machine info:
Product: MINI PC
MODEL: Beeline-EQ12-A
EQ12-A-16512SD0W64PRO-BC/XB
SN: BN1004GG50552
9B.US3020826K40
Amazon Description:
* Beelink Dual LAN 2.5Gb Mini PC, 
* EQ12 Intel Alder-Lake N100 (up to 3.4GHz), 
* 16GB DDR5 RAM 500GB M.2 SSD Mini Computers, 
* WiFi6, 
* BT5.2, 
* USB3.2, 
* 4K Triple Display, 
* Home/Office Desktop PC

#Beelink EQ12 & EQ12Pro - How to Set Auto Power On (for power outages and restore)
* Requirements - must be physically connected to the PC via HDMI or monitor connection - this cannot be done remotely
* ref: https://www.reddit.com/r/BeelinkOfficial/comments/13lqrz4/beelink_eq12_eq12pro_how_to_set_auto_power_on/
1. Press the Del key repeatedly after powering on the mini PC to enter the BIOS setup
2. Enter BIOS setup.
3. Use the arrow keys to enter the Chipset page. Select “PCH-IO Configuration” and press the Enter key.
4. Select “State After G3”.
5. Select “S0 State”. “S0 State” is to enable auto power on and “S5 State” is to disable auto power on.
6. Press the F4 and select “Yes” to save the configuration.
* You can unplug the power supply and then plug it back to test whether the setup succeeded
	
#Create ZFS Pool with remaining diskspace:
##See ...\Dropbox\Main\HomeServers\linux-notes\partition-storage-device-linux.md for notes on using the rest of the partition not used by the root file system of Proxmox
##Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
df -Th

#See ...\Dropbox\Main\HomeServers\linux-notes\zfs-file-system-notes.md FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
zpool list
OUTPUT SHOULD LOOK SOMETHING LIKE THIS:
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
netpool  7.25T   356G  6.90T        -         -     0%     4%  1.00x    ONLINE  -
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

#Then run the following to clean and update:
	apt clean && apt update
	
#Run upgrade to upgrade all packages to latest:
	#NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
	#Reference: https://www.baeldung.com/linux/list-upgradable-packages
	apt upgrade
	
#Make sure zpool is listed as storage option for VMs and OSs:
go to the Proxmox of host machine on local IP, them go to Datacenter > Storage > Add > ZFS > Choose the zpool you wanted to add.
You can also setup ZFS storage (for VM and Container Disks) as thin provisioned disks
!Warning - you can over-provision the disk if you are not careful with the assignment of storage space to each VM and Container you create.

#Disable the local-zfs or local storage disk (where the root of Proxmox is installed) to avoid over-provisioning and potentially freezing proxmox etc.
Go to Datacenter > Storage > click "local-zfs" or whatever local storage is called, > Edit > uncheck "Enable"
This prevents the local storage where the OS is installed from being used by containers, ISO storage, etc.;
Per the homenetworkguy, this can cause the web GUI and even SSH to freeze

#Setup VM with OPNSense:
Guide: https://homenetworkguy.com/how-to/virtualize-opnsense-on-proxmox-as-your-primary-router/
Network setup Guide: https://www.youtube.com/watch?v=CXp0CgilMRA

#OPNSense Configuration with ISP Gateway:
https://homenetworkguy.com/how-to/use-opnsense-router-behind-another-router/
https://www.pcguide.com/router/how-to/use-with-att-fiber/
https://github.com/owenthewizard/opnatt

To change the subnet on your AT&T WAN gateway, you'll need to access the gateway's settings. Here are the steps to do this:

Connect to the Gateway:

Open a web browser on a device connected to your network.
Enter http://192.168.1.254 in the address bar to access the gateway's interface.
* Note: Your IP may be different here
* If you want to remotely access your primary router and you can only do IP Passthrough, you will need to change the main router/modem's IP to a different subnet.
Log In:

You may be prompted to enter a Device Access Code, which is usually found on a sticker on your gateway.
Navigate to Settings:

Once logged in, go to the Home Network tab.
Select Subnets & DHCP.
Change the Subnet:

In the Private LAN Subnet section, you can change the IP Address and Subnet Mask to your desired settings.
For example, you might change the IP Address to 192.168.2.1 and the Subnet Mask to 255.255.255.0.
Save Changes:

After making the changes, click Save.
Your gateway will likely restart to apply the new settings.
Reconfigure Devices:

Ensure that all devices on your network are updated to use the new subnet.


#Setup AdGuard Home on OPNSense:
https://www.youtube.com/watch?v=_JhQn30mqCw



==========================
CREATE PROXMOX BACKUPS
==========================
References: https://www.vinchin.com/vm-backup/proxmox-offsite-backup.html
	https://pve.proxmox.com/wiki/Backup_and_Restore
	By default additional mount points besides the Root Disk mount point are not included in backups. 
	For volume mount points you can set the Backup option to include the mount point in the backup. 
	Device and bind mounts are never backed up as their content is managed outside the Proxmox VE storage library.







