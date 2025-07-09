# Lab Server (hosts Docker and Other VMs)
SETUP DATE: 2024.11.29 (TBD)
Specified ZFS RAID0 for root system - 65GB partition
Installed Proxmox VE 8.2 (updated 2024.04.24)
fullname: benolilab.krimmhouse.local
URL: https://192.168.1.102:8006 (TBD)
2024.11.29 - installed new SSD:
	500GB capacity
	Samsung 870 EVO - V-NAND SSD
	Model: MZ-77E500

# Physical Machine info:
Product: MINI TOWER PC
MODEL: DELL Optiplex 7040
CPU: 8 x Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz (1 Socket
RAM: 32GB DDR4 Speed 2133 MHz

# Create ZFS Pool with remaining diskspace:
## See [partition-storage-device-linux.md](https://github.com/Three50seven/benoli-homelab/blob/main/linux-notes/partition-storage-device-linux.md) for notes on using the rest of the partition not used by the root file system of Proxmox
## Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
df -Th

# See [partition-storage-device-linux.md](https://github.com/Three50seven/benoli-homelab/blob/main/linux-notes/zfs-file-system-notes.md) FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
zpool list
root@benolilab:~# zpool list
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
rpool    63.5G  1.35G  62.2G        -         -     0%     2%  1.00x    ONLINE  -
zbarrel   464G   106K   464G        -         -     0%     0%  1.00x    ONLINE  -
zkeg      173G   108K   173G        -         -     0%     0%  1.00x    ONLINE  -

# Potentially remove the nag (popop warning) about licensing in Proxmox Web Manager:
https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/
2 Easy method:
2.1 Copy and paste following command to the terminal
(8.2.8 8.2.9 8.3.0 and up)
sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service

# Update the APT (Advance Package Tool) Repositories in Proxmox Host:
# Guide: https://benheater.com/bare-metal-proxmox-laptop/amp/
	# Comment out the enterprise repositories - using Command Line:
	sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/pve-enterprise.list
	sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/ceph.list

# Add the community repositories
	echo -e '\n# Proxmox community package repository' >> /etc/apt/sources.list
	echo "deb http://download.proxmox.com/debian/pve $(grep CODENAME /etc/os-release | cut -d '=' -f 2) pve-no-subscription" >> /etc/apt/sources.list

# Then run the following to clean and update:
	apt clean && apt update
	
# Run upgrade to upgrade all packages to latest:
	#NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
	#Reference: https://www.baeldung.com/linux/list-upgradable-packages
	apt upgrade
	
# Make sure zpool is listed as storage option for VMs and OSs:
go to the Proxmox of host machine on local IP, them go to Datacenter > Storage > Add > ZFS > Choose the zpool you wanted to add.

# NOTE: It was determined to just use the Proxmox host of the NAS machine to burn disks and use the Linux CLI burning disks
- The information regarding IOMMU and DVD RW+ is optional
- Ideally a SATA-to-USB converter could be purchased/used to passthrough just the DVD play/burner to a VM on the host, but not necessary when the host can just be used on the NAS machine instead (with minimal overhead)
- Basically it was discovered that the entire SATA controller would have to be passed through, but this would cause resources (such as the boot drive for Proxmox) to also be passed through to the VM and obviously cause Proxmox host boot failure/issues.

# Enable IOMMU for hardware passthrough in Proxmox (e.g. DVD for burning files/mp3s, GPUs etc.)
- Make sure IOMMU (Input-Output Memory Management Unit) is enabled for Proxmox kernel boot
```
cat /proc/cmdline
# You should see something like 'intel_iommu=on'
```
- If you do not see intel_iommu=on when checking the kernal command line (above), you will need to figuer out if grub or systemd-boot is used as the bootloader
```
# Determine the bootloader:
proxmox-boot-tool status
# Look at the "Bootloader" line in the output. It will tell you if it's "grub" or "systemd-boot".
# Edit grup config: 
nano /etc/default/grub
# Look for GRUB_CMDLINE_LINUX_DEFAULT="quiet" and add intel_iommu=on like this:
# optionally iommu=pt for some improved performance with GPUs and other high IO devices
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
# Close/Save the file and run 
update-grub
```
- Add VFIO modules (if you haven't already)

- It's good practice to ensure the necessary kernel modules for PCI passthrough are loaded at boot.
```
nano /etc/modules
# Add the following lines to the end of the file:
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
# Save and exit: (Ctrl+X, then Y, then Enter)
# Update the initramfs: This ensures the modules are included in the early boot process.
update-initramfs -u -k all
# Then reboot:
reboot
```
- After reboot, check the kernel command line again to make sure IOMMU is enabled after reboot
```
cat /proc/cmdline
# You should see something like 'intel_iommu=on' and iommu=pt (if enabled)
```
- Check IOMMU status in dmesg:
```
dmesg | grep -e DMAR -e IOMMU
# You should still see messages like DMAR: IOMMU enabled and DMAR: Using Queued invalidation (or similar for AMD).
# And check IOMMU groups again and you should still see the IOMMU groups:
for d in /sys/kernel/iommu_groups/*/devices/*; do n=${d#*/iommu_groups/*}; n=${n%%/*}; printf 'IOMMU group %s ' "$n"; lspci -nns "${d##*/}"; done
```

# Add DVD RW+ for passthrough device to VM hosting Docker
- Add the DVD drive identifier to the VM config for passthrough
```
# SSH To the Proxmox host and enter:
ls -l /dev/disk/by-id/ | grep sr

# This should give you something like: 
ata-HL-DT-ST_DVD+_-RW_GU90N_KL1G9MC0650 -> ../../sr1
# This is a stable identifier that won't shift like /dev/srX might
```
- Edit the VM config manually:
```
nano /etc/pve/qemu-server/<VMID>.conf
```
- Replace the existing sata0: or ide2: line with:
```
sata0: /dev/disk/by-id/ata-HL-DT-ST_DVD+_-RW_GU90N_KL1G9MC0650,media=cdrom
# Or optionally use scsi0 if you prefer SCSI passthrough
# Save and start the VM
```

