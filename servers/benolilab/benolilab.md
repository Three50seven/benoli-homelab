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
Product: MINI TOWER PC
MODEL: DELL Optiplex 7040
CPU: 8 x Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz (1 Socket
RAM: 32GB DDR4 Speed 2133 MHz

# Create ZFS Pool with remaining diskspace:
- See [partition-storage-device-linux.md](https://github.com/Three50seven/benoli-homelab/blob/main/linux-notes/partition-storage-device-linux.md) for notes on using the rest of the partition not used by the root file system of Proxmox
- Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
df -Th

- See [partition-storage-device-linux.md](https://github.com/Three50seven/benoli-homelab/blob/main/linux-notes/zfs-file-system-notes.md) FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
```
zpool list
root@benolilab:~# zpool list
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
rpool    63.5G  1.35G  62.2G        -         -     0%     2%  1.00x    ONLINE  -
zbarrel   464G   106K   464G        -         -     0%     0%  1.00x    ONLINE  -
zkeg      173G   108K   173G        -         -     0%     0%  1.00x    ONLINE  -
```

# Potentially remove the nag (popop warning) about licensing in Proxmox Web Manager:
https://dannyda.com/2020/05/17/how-to-remove-you-do-not-have-a-valid-subscription-for-this-server-from-proxmox-virtual-environment-6-1-2-proxmox-ve-6-1-2-pve-6-1-2/
For Proxmox versions 8+ use the following "one-shot":
```
sed -i.backup -z "s/res === null || res === undefined || \!res || res\n\t\t\t.data.status.toLowerCase() \!== 'active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service
```
Or follow the manual process in the link above.

# Update the APT (Advance Package Tool) Repositories in Proxmox Host:
- Guide: https://benheater.com/bare-metal-proxmox-laptop/amp/
	# Comment out the enterprise repositories - using Command Line:
```
sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/pve-enterprise.list
sed '/^[^#]/ s/^/# /' -i /etc/apt/sources.list.d/ceph.list
```

# Add the community repositories
```
echo -e '\n# Proxmox community package repository' >> /etc/apt/sources.list
echo "deb http://download.proxmox.com/debian/pve $(grep CODENAME /etc/os-release | cut -d '=' -f 2) pve-no-subscription" >> /etc/apt/sources.list
```

# Then run the following to clean and update:
```
apt clean && apt update
```

# Run upgrade to upgrade all packages to latest:
- NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
- Reference: https://www.baeldung.com/linux/list-upgradable-packages
```
apt upgrade
```

# Make sure zpool is listed as storage option for VMs and OSs:
go to the Proxmox GUI of host machine on local IP, them go to Datacenter > Storage > Add > ZFS > Choose the zpool you wanted to add.
