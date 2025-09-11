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

## Boot your Server from the USB Flash Drive

Connect the USB flash drive to your server and make sure that booting from USB is enabled (check your servers firmware settings). Then follow the steps in the [installation wizard](https://pve.proxmox.com/wiki/Installation#chapter_installation).


# Update Linux Welcome message for SSH sessions:
## motd = Message of the Day
Update/replace the /etc/motd file on a Linux machine where you want to change the welcome message after logging in via SSH

# Use an art-to-ASCII or something similar to generate a custom logo
ref: https://www.asciiart.eu/image-to-ascii
ref: https://patorjk.com/software/taag/#p=display&f=Graffiti&t=t