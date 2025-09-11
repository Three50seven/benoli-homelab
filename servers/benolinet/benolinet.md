# Network Server
- 2024.08.07
- Press DEL Key to enter BIOS
- Specified ZFS RAID0 for root system - 100GB partition
- Installed Proxmox VE 8.2 (updated 2024.04.24)
- fullname: benolinet.krimmhouse.local
- URL: https://192.168.1.253:8006 (Temp until installed as main router)
- MGMT interface: enp2s0

# Physical Machine info:
- Product: MINI PC
- MODEL: Beeline-EQ12-A
- Amazon Description:
    * Beelink Dual LAN 2.5Gb Mini PC, 
    * EQ12 Intel Alder-Lake N100 (up to 3.4GHz), 
    * 16GB DDR5 RAM 500GB M.2 SSD Mini Computers, 
    * WiFi6, 
    * BT5.2, 
    * USB3.2, 
    * 4K Triple Display, 
    * Home/Office Desktop PC

# Beelink EQ12 & EQ12Pro - How to Set Auto Power On (for power outages and restore)
* Requirements - must be physically connected to the PC via HDMI or monitor connection - this cannot be done remotely
* ref: https://www.reddit.com/r/BeelinkOfficial/comments/13lqrz4/beelink_eq12_eq12pro_how_to_set_auto_power_on/
1. Press the Del key repeatedly after powering on the mini PC to enter the BIOS setup
2. Enter BIOS setup.
3. Use the arrow keys to enter the Chipset page. Select "PCH-IO Configuration" and press the Enter key.
4. Select "State After G3".
5. Select "S0 State". "S0 State" is to enable auto power on and "S5 State" is to disable auto power on.
6. Press the F4 and select "Yes" to save the configuration.
* You can unplug the power supply and then plug it back to test whether the setup succeeded

# Proxmox Memory considerations for Benolinet:
Recommended memory distribution 16GB Proxmox host:

Proxmox Host OS: ~2-3 GiB

ZFS ARC (max): ~1.54 GiB (should be default)

OPNsense VM: 4 GiB (4096 MiB) (This should be plenty for most services running - note if ZenArmor is used, you may need more or get a bigger host)

Omada Controller CT: 2 GiB (2048 MiB) - set swap to 1GB (1024 MiB)

- Notes on Swap: Allocate a small amount of swap for the Omada CT as a "safety net."  Setting swap for a 2GB memory allocation to 512 MiB or 1024 MiB (0.5GB to 1GB) is generally sufficient for this purpose. It gives the container some breathing room if it experiences a temporary memory spike, preventing an immediate crash.

Total: 3 GiB (Proxmox) + 1.54 GiB (ZFS ARC) + 4 GiB (OPNsense) + 2 GiB (Omada) = 10.54 GiB

This leaves you with 16 GiB - 10.54 GiB = ~5.46 GiB of buffer/free RAM for bursty needs, caching, and overall system stability. This is a much healthier balance.

# Setup VM with OPNSense:
Guide: https://homenetworkguy.com/how-to/virtualize-opnsense-on-proxmox-as-your-primary-router/

Network setup Guide: https://www.youtube.com/watch?v=CXp0CgilMRA

Memory: (May need to check "Advanced")
- Set minimum memory of 4096 (4GB) - see above regarding Memory considerations
- Set max to the same for better stability
- Disable Ballooning for OPNsense VM - users report better stability on FreeBSD devices like OPNsense

# OPNSense Configuration with ISP Gateway:
- https://homenetworkguy.com/how-to/use-opnsense-router-behind-another-router/
- https://www.pcguide.com/router/how-to/use-with-att-fiber/
- https://github.com/owenthewizard/opnatt

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
- Select Subnets & DHCP.
- Change the Subnet:

In the Private LAN Subnet section, you can change the IP Address and Subnet Mask to your desired settings.
- For example, you might change the IP Address to 192.168.2.1 and the Subnet Mask to 255.255.255.0.
- Save Changes:

After making the changes, click Save.
- Your gateway will likely restart to apply the new settings.
- Reconfigure Devices:

Ensure that all devices on your network are updated to use the new subnet.

# CREATE PROXMOX BACKUPS
References: https://www.vinchin.com/vm-backup/proxmox-offsite-backup.html
- https://pve.proxmox.com/wiki/Backup_and_Restore
- By default additional mount points besides the Root Disk mount point are not included in backups. 
- For volume mount points you can set the Backup option to include the mount point in the backup. 
- Device and bind mounts are never backed up as their content is managed outside the Proxmox VE storage library.

# OPNSense Config Backups:
ref: https://docs.opnsense.org/manual/backups.html

Offsite backup stored in Dropbox

# WireGuard Config and setup
ref: https://docs.opnsense.org/manual/how-tos/wireguard-client.html

# Setup Dynamic DNS (to update hostname with public IP if it changes from ISP)
Make sure to add os-ddclient (Dynamic DNS Service) to OPNsense to update the noip domain with an updated IP if it every changes

ref: https://homenetworkguy.com/how-to/configure-dynamic-dns-opnsense/

# Create a 2nd VM for Migrating/Upgrading OPNsense:
Set up a second OPNsense VM in Proxmox and restore the configuration from your current setup! This is a very common and recommended way to upgrade, test new versions, or migrate to new virtual hardware with minimal downtime.

However, there are a few critical considerations, especially regarding IP settings and network interface assignments.

Here's a step-by-step approach and what you need to be aware of:

Step-by-Step Migration Process
## Backup Your Current OPNsense Configuration:

- Log into your current OPNsense GUI.

- Navigate to System -> Configuration -> Backups.

- Click "Download Configuration".

- Crucially: Choose to download an unencrypted configuration file. While OPNsense supports encrypted backups, it's much easier to deal with interface remapping if the file is unencrypted (XML). If you have plugins, it's best to back up the "RRD and DHCP Leases" as well, though the main config file is paramount.

- Document Current Network Interface Names/MACs:

- In your current OPNsense VM: Note down which Proxmox network interface (e.g., vmbr0, vmbr1) is assigned to WAN, LAN, and any other VLANs/interfaces.

- Inside the OPNsense GUI: Go to Interfaces -> Assignments. Note the names OPNsense uses for these interfaces (e.g., vtnet0, vtnet1, etc.).

- In Proxmox: Go to the "Hardware" tab of your current OPNsense VM. Note the MAC addresses associated with each network device. This will help you identify them in the new VM.

## Create the New OPNsense VM in Proxmox:

- Create a brand new VM in Proxmox.

- Allocate memory: Use optimized memory settings (e.g., Min/Max 4096 MiB, no ballooning).

- Add network devices: Add the same number of network devices (VirtIO recommended) as your current OPNsense VM. Crucially, map them to the same Proxmox bridges (vmbrX) as your current OPNsense setup. For example, if your current WAN is vmbr0 and LAN is vmbr1, configure the new VM's first NIC to vmbr0 and the second to vmbr1. This is very important for a smooth transition.

- Install OPNsense: Install the desired new version of OPNsense on this new VM. Follow the standard installation process.

- Initial Configuration of the New OPNsense VM (Crucial for IP Conflicts):

- During installation, or immediately after first boot:

- Do NOT assign the same LAN IP address as your current OPNsense instance. This is vital to avoid an IP conflict when both are running. Assign a temporary, unused IP address on the same subnet as your LAN, or even better, assign an IP on a completely different, isolated network segment if you have one.

- Do NOT connect the new OPNsense VM's WAN interface to your actual WAN until you're ready to switch over. You can either leave it disconnected, or connect it to an isolated network where it won't interfere.

- You'll primarily be working with its LAN interface to access the GUI.

## Restore Configuration to the New OPNsense VM:

- Once the new OPNsense VM is installed and has its temporary LAN IP (and you can access its GUI), log in.

- Navigate to System -> Configuration -> Backups.

- Click "Restore Configuration" or "Choose File" and upload the unencrypted config.xml file you downloaded earlier.

- OPNsense will process the restore and likely prompt you for a reboot.

- Address Network Interface Mismatches (Most Common Issue):

- After the restore and reboot, the new OPNsense VM might not have network connectivity. This is usually because the new VM's virtual NICs (e.g., vtnet0, vtnet1) might be enumerated differently than the old VM's.

- Access the new OPNsense VM's console in Proxmox.

- At the console menu, choose option 1) Assign interfaces.

- OPNsense will show you the detected physical interfaces (e.g., vtnet0, vtnet1). It will then ask you to assign them to your WAN, LAN, etc.

- Carefully re-map the interfaces based on your knowledge from Step 2 and the MAC addresses you noted. For instance, if your WAN vmbr0 connects to vtnet0 in the new VM, and LAN vmbr1 connects to vtnet1, assign them accordingly.

- Confirm the changes. If successful, the new OPNsense VM should now have the correct interface assignments and the IP addresses from your restored configuration.

## Final Testing and Cutover:

- Verify all services on the new OPNsense VM. Can you access the internet through it (if you temporarily connected its WAN)? Are all your firewall rules, VPNs, DHCP, DNS, etc., working as expected?

- Disable your old OPNsense VM. The easiest way is to power it off in Proxmox.

- Enable the WAN interface on the new OPNsense VM (if you had it isolated) and ensure it's connected to your actual WAN network.

- Important: If you temporarily changed the new OPNsense VM's LAN IP address in Step 4, you'll now need to change it back to the original LAN IP address that your network expects. You can do this via the GUI or the console.

- Test your network: Your devices should now be routing through the new OPNsense VM. Confirm internet access, internal network access, and any specific services.

## Key IP and Network Considerations:
- IP Conflicts: The biggest risk is having two OPNsense instances (old and new) trying to use the same LAN IP (and potentially WAN IP if it's static) simultaneously. This will cause network chaos. Always have the "old" one offline or on a different IP when the "new" one is configured with the production IPs.

- Interface Names: This is the most common hurdle when restoring a config to different (even virtual) hardware. OPNsense assigns internal names (like vtnet0) to its detected network interfaces. If the new VM presents them differently, you must re-assign them in the console after the config restore.

- MAC Addresses: While less common to cause direct issues after remapping interfaces, if you have any static DHCP assignments or firewall rules tied to specific MAC addresses, ensure they align with the new VM's NICs. In most VM scenarios, the new VM will get new MAC addresses unless you manually assign the old ones in Proxmox (which is generally not recommended unless you absolutely need to for a specific reason).

- By following these steps carefully, especially managing IP addresses during the transition and re-assigning interfaces, you should be able to smoothly migrate your OPNsense setup to a new VM.
