# Installing OS on Bare Metal (Server Setup)
I prefer Proxmox VE.  You can grab the latest ISO and create a bootable USB here:
https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso

Next, prepare the ISO file as a bootable USB and see each server's readme (servername.md) in this project for setup specifics.

# Prepare ISO file as bootable USB
reference: https://pve.proxmox.com/wiki/Prepare_Installation_Media

The flash drive needs to have at least 1 GB of storage available.

Make sure that the USB flash drive is not mounted and does not contain any important data.

Since Etcher works out of the box, here are those instructions, but Rufus can be used as well, as long as you use DD mode.

## Using Etcher

Download Etcher from https://etcher.io. It will guide you through the process of selecting the ISO and your USB flash drive.

Preferences: create a 50GB partition on ZFS for initial setup
Additional storage can then be used to create a netpool ZFS pool for backups etc.

## Boot your Server from the USB Flash Drive

Connect the USB flash drive to your server and make sure that booting from USB is enabled (check your servers firmware settings). Then follow the steps in the [installation wizard](https://pve.proxmox.com/wiki/Installation#chapter_installation).

For DNS resolution - make sure to set to a public DNS or internal (if already configured and this is not your first time setting up proxmox) - for example, set this to the docker container IP running adguard or pihole for example - whatever your primary DNS is.  This can also be configured through the GUI via node > System > DNS

Setting DNS will allow apt packages etc. to reach where they need to in order to keep Proxmox updated.

Once this is set, ping google.com from the shell and see if it resolves.  If so, update the packages under node > Update and set it to the non-paid version. Disabe the enterprise sources.

# Create ZFS Pool with remaining diskspace:
- See [partition-storage-device-linux.md](https://github.com/Three50seven/benoli-homelab/blob/main/linux-notes/partition-storage-device-linux.md) for notes on using the rest of the partition not used by the root file system of Proxmox
- Run Command to view free space and disk usage stats in human readable format - note the "Type", you should see ZFS pools that can be imported
```
df -Th
```

- See [zfs-file-system-notes.md](https://github.com/Three50seven/benoli-homelab/blob/main/linux-notes/zfs-file-system-notes.md) FOR MORE ZFS POOL COMMANDS, SPECIFICALLY NOTES ABOUT IMPORTING POOL FROM PREV. SYSTEM IF THIS IS A REINSTALL OF PROXMOX:
```
zpool list
OUTPUT SHOULD LOOK SOMETHING LIKE THIS:
NAME      SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
naspool  7.25T   356G  6.90T        -         -     0%     4%  1.00x    ONLINE  -
rpool    63.5G  1.78G  61.7G        -         -     0%     2%  1.00x    ONLINE  -
zbarrel   928G   305G   623G        -         -     0%    32%  1.00x    ONLINE  -
zkeg      400G  1.95M   400G        -         -     0%     0%  1.00x    ONLINE  -
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

# If you get an error trying to get apt packages:
```
ping www.google.com
nano /etc/resolv.conf
confirm nameserver is correct
```
- also, you can run: dpkg --configure -a
- if apt is interrupted for some reason, packages that have been downloaded and unpacked may not have been fully configured, or installed.
- the --configure option causes dpkg to finish configuration of partially installed packages, and the -a indicates that rather than a specific package, all unpacked, but unconfigured packages should be processed.

# Then run the following to clean and update:
```
apt clean && apt update
```

# Run upgrade to upgrade all packages to latest:
```
#NOTE: You can use "apt --dry-run upgrade" for a dry-run before upgrading
#Reference: https://www.baeldung.com/linux/list-upgradable-packages
apt upgrade	
```
	
# Make sure zpool is listed as storage option for VMs and OSs:
go to the Proxmox of host machine on local IP, them go to Datacenter > Storage > Add > ZFS > Choose the zpool you wanted to add.

You can also setup ZFS storage (for VM and Container Disks) as thin provisioned disks

**_Warning:_** - you can over-provision the disk if you are not careful with the assignment of storage space to each VM and Container you create.

# Disable the local-zfs or local storage disk (where the root of Proxmox is installed) to avoid over-provisioning and potentially freezing proxmox etc.
Go to Datacenter > Storage > click "local-zfs" or whatever local storage is called, > Edit > uncheck "Enable"

This prevents the local storage where the OS is installed from being used by containers, ISO storage, etc.;

Per the homenetworkguy, this can cause the web GUI and even SSH to freeze

# Upgrading Proxmox VE
Here are the steps to upgrade a machine to a newer version of Proxmox Virtual Environment.  I typically choose to just to a full wipe and upgrade as opposed to upgrading in place.

Clean-install method (for upgrading PVE 8 -> 9):

🧱 Phase 1: Pre-Install Prep

🔍 Audit & Backupdf (see backup Proxmox VE section below which mentions a script to complete this phase)
- Inventory VMs/CTs: Export VM configs (`qm config <vmid>`) and container settings.
- Backup storage volumes: Use `vzdump` for VMs/CTs or snapshot/export ZFS datasets.
- Export custom configs: `/etc/network/interfaces`, `/etc/pve/storage.cfg`, firewall rules, hooks, etc.
- Note PCI passthrough mappings, if applicable (GPU, NICs, etc.)

📦 Download & Verify ISO
- Get the latest Proxmox VE 9 ISO
- Verify checksum (`sha256sum`) for integrity
_______________

⚙️ Phase 2: Installation

🧭 Boot & Install
- Use UEFI if supported; enable Secure Boot if desired
- Choose ZFS, LVM, or ext4 depending on your storage strategy
- Set hostname, timezone, and root password

🛡️ Post-Install Hardening
- Disable root SSH login (PermitRootLogin no)
- Set up SSH key auth
- Configure firewall zones and rules
- Install `fail2ban` or similar intrusion prevention

_______________

🧬 Phase 3: Rebuild Environment

🧠 Recreate Storage Pools
- Rebuild ZFS pools or LVM volumes
- Reattach NFS/CIFS/Gluster/ceph if used

🧩 Restore VMs/CTs
- Use `qmrestore` or `pct restore` from backups
- Reapply passthrough configs and network bridges

🔗 Reconfigure Networking
- Rebuild bridges (`vmbr0`, etc.)
- Reapply VLANs, NAT, or routing rules
- Rebind static IPs and DNS

_______________

🧰 Phase 4: Tooling & Automation

🧼 Install Packages
- `pve-headers`, `pve-qemu-kvm`, `pve-container`, `pve-manager`, etc.
- Add monitoring tools (Prometheus node exporter, sysstat, etc.)

🧪 Reintegrate Automation
- Reapply PowerShell/SQL-driven reporting logic
- Rebuild GUI preview scripts and logging modules
- Reconnect to external APIs or LLM orchestration layers

_______________

📊 Phase 5: Observability & Testing
- Validate backups, snapshots, and restore paths
- Test VM performance, passthrough, and network throughput
- Monitor logs (`journalctl`, `dmesg`, `/var/log/syslog`) for anomalies


# Backing up Proxmox VE (containers and VMs included)
There is a backup script in the ./scripts/ directory of this repo.  See proxmox-ve-backup.sh
How to Use
- Mount your external drive:
```
mkdir -p /mnt/usb-backup
mount /dev/sdX1 /mnt/usb-backup  # Replace sdX1 with your actual device
```
- Run the script as root:
```
chmod +x proxmox-ve-backup.sh
./proxmox-ve-backup.sh
```

## Other notes regarding proxmox VE backups
- References: https://www.vinchin.com/vm-backup/proxmox-offsite-backup.html
- https://pve.proxmox.com/wiki/Backup_and_Restore
- By default additional mount points besides the Root Disk mount point are not included in backups. 
- For volume mount points you can set the Backup option to include the mount point in the backup. 
- Device and bind mounts are never backed up as their content is managed outside the Proxmox VE storage library.


# Update Linux Welcome message for SSH sessions:
## motd = Message of the Day
Update/replace the /etc/motd file on a Linux machine where you want to change the welcome message after logging in via SSH

# Use an art-to-ASCII or something similar to generate a custom logo
ref: https://www.asciiart.eu/image-to-ascii
ref: https://patorjk.com/software/taag/#p=display&f=Graffiti&t=t