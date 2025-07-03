# benoli-homelab
Homelab for the home - all the things, network - vms, plex, etc.

# Server naming convention:

[benoli-physical box, ct-container, vm-virtual machine] + [primary function] + [optional number when there are multiple servers with same function]

For example:  
DNS: ctdns, ctadguard, ctpihole

OPNSense Router/fw: benolinet, vmopnsense

NAS: benolinas, vmnas

File Server: ctfileserver, ctfileserver1, ctfileserver2

Domain Controller: vmdc

Omada Controller: ctomada

Virtual Environment Host: benolivehost

# Potential Services/Servers - Sketch:
opnsense - router/firewall software
Plex - Music and Videos - handles streaming
music option: Navidrome - iTunes migrator: https://github.com/Stampede/itunes-navidrome-migration
openmediavault - nas and fileshare (Samba etc.)
omada - wifi controller for tp-link devices
proxmox backups - handles backups of vm's and containers on proxmox
Nextcloud - local cloud storage and photo browser for android

# Etcher - Flash drive image creation software:
https://etcher.balena.io/#download-etcher

# Help for Nintendo Switch NAT Type: 
https://www.reddit.com/r/OPNsenseFirewall/comments/g3sx2l/tip_opnsense_and_nintendo_switch_nat_rules/
Step 1: Give Each Device a Static IP
Assign a static DHCP lease for your Switch and any consoles/devices.
This ensures NAT rules consistently match their IPs.
To give your Nintendo Switch a static IP via DHCP in OPNsense (recommended), follow these steps:

A. Find the Switch's MAC Address
On the Switch: System Settings -> Internet -> Connection Status

Write down the MAC address

B. Set Up a DHCP Static Mapping in OPNsense
Navigate to Services -> DHCPv4 -> LAN (or whichever interface your Switch is on).

Scroll to DHCP Static Mappings for this Interface and click +Add.

Fill in:

MAC Address: (from your Switch)

IP Address: e.g., 192.168.1.150 (choose outside DHCP pool)

Hostname: Nintendo-Switch (optional but helpful)

Click Save and then Apply Changes. This ensures your Switch always receives this IP via DHCP 
docs.opnsense.org
+15
zenarmor.com
+15
reddit.com
+15
forum.opnsense.org
.

Why Use DHCP Static Mapping
You centrally define the static IP on your router-not inside the Switch.

Simplifies management: no need to configure the Switch manually.

Ensures outbound NAT and port-forward rules remain valid across reboots.

C. Confirm & Restart
Reboot the Switch or toggle Wi-Fi to renew its DHCP lease.

Under Connection Status, verify it has the static IP.

Step 2: Enable Hybrid Outbound NAT & Static Port
Go to Firewall -> NAT -> Outbound

Set Mode to Hybrid (or Manual)

Add a rule:

Source: Your device's IP (/32)

Enable Static-port (keeps the same source port during NAT)
This moves you from Nintendo NAT Type D to B. 
linustechtips.com
+8
tyzbit.blog
+8
kenfinnigan.me
+8
blog.jamie.ie
+1
github.com
+1
forum.opnsense.org
+1
reddit.com
+1
reddit.com

Step 3: (Optional) Port Forward UDP 45000-65535
To achieve NAT Type A, Nintendo recommends forwarding all UDP ports (1-65535) or at least 45000-65535.
Using a large range alias:

Create an Alias (Firewall -> Aliases) for UDP ports 45000-65535

Create a Port Forward rule on WAN:

Destination: WAN address

Port range: select alias

Redirect to your device IP, same port

Enable NAT reflection and export matching filter rules

This gives NAT Type A, but can open many ports on your LAN. 
reddit.com

Bonus: Use UPnP for Dynamic Mappings
Enable UPnP/NAT-PMP in OPNsense to let devices request ports on-the-fly.
However, note that older miniupnpd versions have bugs handling multiple devices. Review community fixes if needed. 
reddit.com
github.com

TL;DR: What Each Step Achieves
Goal	What to Do	Resulting NAT Type
Basic connectivity	DHCP static + Static-port outbound NAT	B
Best performance & compatibility	+ Port-forward UDP 45000-65535	A
Dynamic, multi-device NAT	Enable UPnP/NAT-PMP	B-A, but review UPnP bugs

Next Steps
Assign static DHCP IP to Switch

Configure Hybrid Outbound NAT + Static-port

(Optional) Set up UDP port-forward alias for Type A

Test Switch NAT type in its Internet -> Test Connection