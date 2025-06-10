# Proxmox:

# Partition the rest of the SSD (400.8GB)
	ref: https://www.tecmint.com/linux-partition-managers/
	Connect to proxmox via web interface
	Run Shell from Datacenter > benolinas
	```
	# List all disks:
	fdisk -l 
	
	# Choose disk to manage:
	fdisk /dev/sda
	
	#Show menu (m) free unpartitioned space (F):
	#Create partition:
	n, use defaults by just pressing enter for default partition number, first and last sectors
	```
	# Change partition file system type (t):
	Enter the partition number you just created, choose "157" for ZFS, or "L" to list other options (q will quit the list paging)
	
	# Write the changes and create the partition (w):
	Run lsblk to show all disks and partitions on the system.above
	
# Create a simple zpool for storage use in proxmox (note, this will not be RAID or offer any redundancy, it's just so the storage can be used for ISOs and container storage files, etc.)
	# IMPORTANT - USE THE PARTITION NUMBER YOU CREATED ABOVE, IT MAY NOT BE sda4
	# NOTE: You can change the name from zkeg to something else, as needed.
	zpool create zkeg /dev/sda4
	
# Create backups dataset and add as directory to proxmox host:
	# Reference: https://www.theurbanpenguin.com/creating-zfs-data-sets-and-compression/
	zfs create naspool/backups
	# list all the ZFS datasets:
	zfs list 
	# Add backups to Datacenter > storage > Add > Directory:
	ID = backups
	Directory = /naspool/backups
	# Note, Content determines what the storage can be used for, e.g. VZ backupfile means it can be used for storing backups of VMs and containers. 
	# To setup new ISO image storage area, Add new storage as Directory
	# ISO Image and Container template means it can be used to store ISOs and Container templates for future VM and container setups
	Content = ISO Image, Container template, VZ backupfile
	# Leave defaults for other settings
	
# Create ZPool on sdb:
	# After changing the partition (using fdisk /dev/sdb > t > 157 > web
	# AND after copying data: 
	
	rsync -ah --info=progress2 /mnt/sdb /zkeg/beer
	
	# Unmount the sdb:
	umount /mnt/sdb
	
	# Create the zbarrel ZFS pool:
	zpool create zbarrel /dev/sdb
	
	# Then create a new dataset:
	zfs create zbarrel/bourbon
	
	# Copy data back to zbarrel bourbon
	rsync -ah --info=progress2 /zkeg/beer /zbarrel/bourbon
	
	# Remove data from /zkeg/beer - NOTE: This deletes the sdb folder and ALL its contents:
	rm -r /zkeg/beer/sdb