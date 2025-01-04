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