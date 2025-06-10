# Plex Host Setup 
	- also see fstab setup for naspool in [vmdocker.md](https://github.com/Three50seven/benoli-homelab/blob/main/servers/benolilab/vmdocker/vmdocker.md)
# Add TV Tuner device for plex container to use:
--To pass a USB device from Proxmox to a virtual machine (VM), 
	navigate to the VM's settings within the Proxmox web interface, go to the "Hardware" section, 
	and select "Add > USB Device"; then choose the specific USB device you want to passthrough by 
	either selecting it using its Vendor/Device ID or specifying the physical USB port it's 
	connected to on the Proxmox host.
device should be named something like: Hauppauge 955D
on docker vm, you should see the usb device now:
	lsusb
--install the following packages:
	apt update
	apt-get install wget bzip2 build-essential libncurses5-dev	
	apt-get install software-properties-common
	apt install python3-launchpadlib
	apt update
	nano /etc/apt/sources.list
	--add repo line manually (note jammy is the closest version of ubuntu that matches to debian 12 - you may need to check the site for newer versions if you have a newer OS install):
	--source: https://launchpad.net/~b-rad/+archive/ubuntu/kernel+mediatree+hauppauge
	--source for ubuntu debian matchup: https://askubuntu.com/questions/445487/what-debian-version-are-the-different-ubuntu-versions-based-on
	-- reference: https://forums.plex.tv/t/cannot-connect-usb-tuner-wih-the-official-plex-docker-image/228823
	deb [trusted=yes] https://ppa.launchpadcontent.net/b-rad/kernel+mediatree+hauppauge/ubuntu jammy main 
	deb-src [trusted=yes] https://ppa.launchpadcontent.net/b-rad/kernel+mediatree+hauppauge/ubuntu jammy main 	
	apt-get install linux-mediatree
	--firmware install if needed (Most North American TV Tuners DO NOT NEED THIS): apt-get install linux-firmware-hauppauge 
	--restart the vmdocker server via proxmox or ssh command (reboot)
	--install wscan for channel scanning:
	apt install w-scan -y
	--make tvtuner directory:
	mkdir /opt/tvtuner
	cd /opt/tvtuner
	--scan for ATSC channels in the United States
	w_scan -fa -c US > channels.conf
	--should see results e.g. ...
	473000: 8VSB(time: 00:51.098)         signal ok:        8VSB     f=473000 kHz (0:0:0)
	479000: 8VSB(time: 00:51.938)         signal ok:        8VSB     f=479000 kHz (0:0:0)
	485000: 8VSB(time: 00:52.778)
	...	
	803000: 8VSB(time: 03:40.331)
	tune to: 8VSB     f=473000 kHz (0:0:0) (time: 03:43.431)
	service is running. Channel number: 32:1. Name: 'WLKY-HD'
	service is running. Channel number: 32:2. Name: 'ME TV'
	service is running. Channel number: 32:4. Name: 'STORY'
	WARNING: unhandled stream_type: 1B
	---
	You should now be able to setup plex with docker-compose file below.

# Setup Plex in Docker Container (PRE recommended method of using Docker-Compose - mentioned in vmdocker.md - see benolilab-docker):

- In the docker-compose file NOTE: if you want to add a new volume (i.e. for library files), add it to the volumes list Below
	- left of the : is the actual path and to the right is the path Plex will see.  
	- map the USB bus and dev/dvb directories so that the TVTuner can be used by the container from the host
	- add write permissions to allow plex to write to media directory for dvr recordings
		stat /mnt/naspool/Plex/library
		- use command above to confirm that localadmin is UID 1000 and Gid 1000 before adding to below record
		- Verify Permissions: Check that the permissions are correctly set by listing the directory contents:
		ls -l /mnt/naspool/Plex/library
=======================
```
services:
  plex:
        container_name: plex
        image: linuxserver/plex
        networks:
          server_net:
            ipv4_address: 172.18.0.13
        ports:
            - "32400:32400/tcp"
        restart: unless-stopped
        environment:
            - TZ=America/New_York
            #GET CLAIM FROM https://www.plex.tv/claim/
            - PLEX_CLAIM=/run/secrets/plex_claim
            - PUID=1000
            - PGID=1000
        volumes:
            - plex_server_config:/config
            - plex_server_transcode:/transcode
            - plex_server_media:/data
            - /mnt/naspool:/naspool
            - /mnt/sdb:/localmedia
        devices:
            - /dev/bus/usb:/dev/bus/usb	
            - /dev/dvb:/dev/dvb
        healthcheck:
              test: "curl --connect-timeout 15 --max-time 100 --silent --show-error --fail 'http://localhost:32400/identity' >/dev/null"
              interval: 1m
              timeout: 15s
              retries: 3
              start_period: 1m
        secrets:
            - plex_claim
        labels:
            - com.centurylinklabs.watchtower.enable=true 
```

# Update Plex when needed (PRE WATCHTOWER):
cd /opt/plex
docker compose pull plex
docker compose down 
docker compose up -d
--when creating a new container, run with restart unless-stopped flag to restart on reboot
docker run -d --restart unless-stopped <image_name>
--for an existing container, run:
docker update --restart unless-stopped <container_name_or_id>
- remove old images (optional):
docker image prune

# Connect to Plex server via browser (on machine that is on the same local network):
http://192.168.1.63:32400/

# Add TV Tuner and do a channel scan:
Go to Settings > Manage > Live TV & DVR
--The USB device should now show - run a scan of channels and select "Local Broadcast Listings" as the guide info source
--Plex should then show you Live TV channels it found

# Migrate Media data as needed:
See benolinas-migrate-data.md for details

# Add plex library directories via settings to view media
Go to Settings > Manage > Libraries and add libraries as needed
You should see the NAS drive and local drive as added in the volumes within the docker-compose file
