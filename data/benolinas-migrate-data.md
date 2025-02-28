2024.12.06
Notes on migrating data to NAS:

# Plug in external hd to source and copy over data
	--Windows Powershell to copy over old media files (prior to hosting plex in docker container)
	ROBOCOPY "I:\Plex\Library" "H:\nasplexlibrary\Plex\Library" /z /mir /xj /mt /eta /tee
	ROBOCOPY "C:\Users\Three50seven\Music\iTunes\iTunes Music" "H:\nasplexlibrary\Plex\Library\Music" /z /mir /xj /mt /eta /tee
	--note - renamed OtherVideos to "Other Videos" since first robocopy of library had a different name
	--also removed /mir in the next robocopy so that nothing is deleted in the destination since we're just merging the two plex libraries
	--also deleted "Music" from "H:\NAS_Backup\Plex\Library"
	ROBOCOPY "H:\NAS_Backup\Plex\Library" "H:\nasplexlibrary\Plex\Library" /z /e /xj /mt /eta /tee /xo

# Passthrough external hd to destination VM on Proxmox (NAS)
	--Plug in external hd to the NAS machine:
	```bash
	lsblk to view new drive
	```	
<!--ONLY NEEDED if passing the disk to a VM or container:
# Use virtio for faster performance on disk for VM:
	ref: https://www.youtube.com/watch?v=wGhSJ-G9jQg
	--this will use the para virtualized disk, which is ~20-25% faster than sd disk
	SSH to proxmox nas host (benolinas)
	--install 
	```bash
	apt install lshw
	lshw -class disk -class storage
	ls -l /dev/disk/by-id
	```	
	--e.g.: usb-WD_Game_Drive_575845324532303159595546-0:0-part1
	--get device name by id (not by virtual name - i.e. /dev/sdb1 etc.)
	```bash
	qm set [proxmox vm id] -virtio2 /dev/disk/by-id/[full id of disk from prev. command]
	more /etc/pve/qemu-server/[proxmox vm id].conf
	```
	--you should see a line for virtio2: /dev/disk/by-id/[full id of disk from prev. command]
	--you should also see a new hard disk in the hardware of the virtual machine (via gui)
	```bash
	lsblk
	```
	--you should now see a vda disk in the VM
-->

# Mount the drive - 
--Note, use /dev/vda if doing para virtual disk, or /dev/sdg1 (assuming this is where the usb dev is located) if using standard disk
	```bash
	mkdir /mnt/exthd	
	# mount /dev/vda /mnt/exthd
	mount /dev/sdg1 /mnt/exthd
	cd /mnt/exthd
	```

# (OPTIONAL) - Perform speed test on disk:
	```bash
	mkdir /mnt/exthd/temp
	cd /mnt/exthd/temp
	```
	--run command to create a bigFile of 10GB with 1G block size
	```bash
	time sudo dd if=/dev/urandom bs=1G count=10 of=bigFile
	```
	--you should see output of time and speed it took to write the bigFile

# View drive space usage and directory sizes:
	df -H
	You can use the `du` (disk usage) command to view all directories with their size of contents. Here's a command that lists all directories in the current directory along with their sizes in a human-readable format:

	```bash
	du -h --max-depth=1
	```

	If you want to sort the directories by size, you can pipe the output to the `sort` command:

	```bash
	du -h --max-depth=1 | sort -h
	```

	Here's a breakdown of the options used:
	- `-h`: Displays sizes in a human-readable format (e.g., 1K, 234M, 2G).
	- `--max-depth=1`: Limits the depth of directory traversal to one level, so it only shows the sizes of the directories in the current directory.
	- `sort -h`: Sorts the output by size in a human-readable format.

	This command will give you a clear view of the sizes of all directories in the current directory. If you need to check a different directory, you can specify the path like this:

	```bash
	du -h --max-depth=1 /path/to/directory | sort -h
	```

# Copy data to NAS drives for use by Plex etc.
	--rsync [options] [source] [dest]
	--TEST Music first:
	```bash
	rsync -rvh --info=progress2 --stats /mnt/exthd/nasplexlibrary/Plex/Library/Music/ /naspool/share/Plex/Library/Music
	rsync -rvh --info=progress2 --stats /mnt/exthd/nasplexlibrary/Plex/Library/ /naspool/share/Plex/Library
	```
	
	--IF USING PARA VIRTUAL DISK:
	```bash
	rsync -rvh --info=progress2 --stats /mnt/exthd/nasplexlibrary/Plex/Library/Music /srv/dev-disk-by-uuid-a75a07c1-2bf0-4af8-bf91-1cf1d02866c3/naspool/plex/library/Music
	rsync -rvh --info=progress2 --stats /mnt/exthd/nasplexlibrary/Plex/Library/ /srv/dev-disk-by-uuid-a75a07c1-2bf0-4af8-bf91-1cf1d02866c3/naspool/plex/library/
	```
	
	--IF RUNNING A SUBSEQUENT TIME (use --ignore-existing option):
	```bash
	rsync -rvh --info=progress2 --stats --ignore-existing /mnt/exthd/nasplexlibrary/Plex/Library/ /naspool/share/Plex/Library
	```
	
	--issues:
	sending incremental file list
              0   0%    0.00kB/s    0:00:00 (xfr# 0, to-chk=525/16642)
	TV Shows/That '70s Show/Season 08/That '70s Show - s08e22 - That '70s Finale.mkv
			626.28M   0%    2.53MB/s    0:03:56 (xfr#1, to-chk=503/16642)
	TV Shows/The Big Bang Theory/Season 8/The Big Bang Theory - s08e10 - The Champagne Reflection.mkv
			969.64M   0%    3.68MB/s    0:04:11 (xfr#2, to-chk=0/16642)

# Set the permissions on the Plex Directories and Files so that Plex can "see" them:
	find /naspool/share/Plex/Library -type d -exec chmod 755 {} \;
	find /naspool/share/Plex/Library -type f -exec chmod 644 {} \;
	
	<!--
	755: Owner has full control, others can read and execute.
	644: Owner can read and write, others can only read.
	
	The numbers used in chmod are octal (base-8) representations of the file permissions. Each digit represents different levels of access:

	First digit: Permissions for the owner of the file.
	Second digit: Permissions for the group associated with the file.
	Third digit: Permissions for others (everyone else).
	Each digit is a sum of the following values:

	4 = Read (r)
	2 = Write (w)
	1 = Execute (x)
	chmod 755
	Owner: 7 (4 + 2 + 1) = Read, Write, Execute
	Group: 5 (4 + 0 + 1) = Read, Execute
	Others: 5 (4 + 0 + 1) = Read, Execute
	This means:

	The owner can read, write, and execute the file.
	The group can read and execute the file.
	Others can read and execute the file.
	chmod 644
	Owner: 6 (4 + 2 + 0) = Read, Write
	Group: 4 (4 + 0 + 0) = Read
	Others: 4 (4 + 0 + 0) = Read
	This means:

	The owner can read and write the file.
	The group can read the file.
	Others can read the file.
	-->
# Unmount drive when done and unplug drive
	```bash
	umount /mnt/exthd 
	```
	
# Rescan Plex files on plex dashboard.
	Go to Settings > Manage > Libraries (bottom left) > Press "Scan Library Files" button










