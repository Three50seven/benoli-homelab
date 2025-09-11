# Lab Server (hosts Docker and Other VMs)
- SETUP DATE: 2024.11.29 (TBD)
- Specified ZFS RAID0 for root system - 65GB partition
- Installed Proxmox VE 8.2 (updated 2024.04.24)
- fullname: benolilab.krimmhouse.local
- URL: https://192.168.1.102:8006 (TBD)
- 2024.11.29 - installed new SSD:
	- 500GB capacity
	- Samsung 870 EVO - V-NAND SSD
	- Model: MZ-77E500

# Physical Machine info:
- Product: MINI TOWER PC
- MODEL: DELL Optiplex 7040
- CPU: 8 x Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz (1 Socket
- RAM: 32GB DDR4 Speed 2133 MHz

# Download Debian OS ISO:
Go to Local storage - ISO (or other storage if added as directory from ZFS drives)

NOTE: To get the latest, go to https://debian.osuosl.org/debian-cdimage/current/amd64/iso-dvd/ and update the link below when downloading.

Download: https://debian.osuosl.org/debian-cdimage/12.8.0/amd64/iso-dvd/debian-12.8.0-amd64-DVD-1.iso

Note: This was the latest URL from the Debian Host as of 2024.11.30 - check latest for updated version

# Setup debian server VM for docker engine:
- name: vmdocker
- OS - Use CD/DVD - debian-12.8 (downloaded earlier)
- 150GiB HD on zkeg
- 250GiB HD on zbarrel
- CPU - 1 Sockets - 8 Cores, x86-64-v2-AES - leave all other defaults
- Memory: 20480 MB (use most, i.e. 20 GB of the 32GB of RAM from proxmox host so that Docker can use most resources)
	- checked "top" command in linux and saw that there is ~25570 MiB free, so taking about 80-90% of this for the VM is recommended
	- set minumum to 8 GB: 8192 MB - Minimum Memory: Typically, setting the minimum memory to around 25-50% of the maximum memory is a good practice. For a VM with 20GB maximum memory, this would be:
		- 25% of 20GB: ( 20 \times 0.25 = 5 ) GB
		- 50% of 20GB: ( 20 \times 0.5 = 10 ) GB
		- Suggested Minimum Memory:
		- 5GB to 10GB: This range should provide a balance between ensuring the VM can start and run essential services while leaving room for dynamic memory allocation as needed.
	- make sure ballooning is checked to ensure memory can be dynamically adjusted based on needs of the host and other VMs
- Network: Leave default
- Finish and start VM - run through Debian install
- hostname: vmdocker.network.local <or whatever you want here>

_see **vmdocker.md** for remaining setup after debian server is installed_