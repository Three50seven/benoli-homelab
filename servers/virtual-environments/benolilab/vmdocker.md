#Download Debian OS ISO:
Go to Local storage - ISO (or other storage if added as directory from ZFS drives)
Download: https://debian.osuosl.org/debian-cdimage/12.8.0/amd64/iso-dvd/debian-12.8.0-amd64-DVD-1.iso
Note: This was the latest URL from the Debian Host as of 2024.11.30 - check latest for updated version

#Setup debian server VM for docker engine:
name: vmdocker
OS - Use CD/DVD - debian-12.8 (downloaded earlier)
150GiB HD on zkeg
250GiB HD on zbarrel
CPU - 1 Sockets - 8 Cores, x86-64-v2-AES - leave all other defaults
Memory: 20480 MB (use most, i.e. 20 GB of the 32GB of RAM from proxmox host so that Docker can use most resources)
	-checked "top" command in linux and saw that there is ~25570 MiB free, so taking about 80-90% of this for the VM is recommended
	-set minumum to 8 GB: 8192 MB - Minimum Memory: Typically, setting the minimum memory to around 25-50% of the maximum memory is a good practice. For a VM with 20GB maximum memory, this would be:
		25% of 20GB: ( 20 \times 0.25 = 5 ) GB
		50% of 20GB: ( 20 \times 0.5 = 10 ) GB
		Suggested Minimum Memory:
		5GB to 10GB: This range should provide a balance between ensuring the VM can start and run essential services while leaving room for dynamic memory allocation as needed.
	-make sure ballooning is checked to ensure memory can be dynamically adjusted based on needs of the host and other VMs
Network: Leave default
Finish and start VM - run through Debian install
hostname: vmdocker.krimmhouse.local

#Install and check SSH server:
apt install openssh-server
systemctl status ssh

#Permit SSH Root login:
nano /etc/ssh/sshd_config
Find # Authentication: section > PermitRootLogin
Remove "#" from line that says PermitRootLogin and change value to "yes"
exit and save the nano editor

#Setup Debian apt sources:
sudo nano /etc/apt/sources.list
 - view latest: https://wiki.debian.org/SourcesList
 - e.g. (comment out deb cdrom line)
deb-src http://deb.debian.org/debian bookworm main non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main non-free-firmware

#Update Debian installation:
apt update
apt upgrade

#Set static IP on Debian 12 VM (note you'll need root user for this):
https://www.linuxtechi.com/configure-static-ip-address-debian/
ip add show
 - get the name of the network interface (in this case it's ens18)
nano /etc/network/interfaces

Replace the line ‘allow-htplug ens18’ with ‘auto ens18‘ and change dhcp parameter to static.  Below is my sample file, change interface name and ip details as per your environment.

auto ens18
iface ens18 inet static
        address 192.168.1.63/24
        network 192.168.1.0
        broadcast 192.168.1.255
        gateway 192.168.1.1
        dns-nameservers 8.8.8.8

#Setup Docker on new Debian Server (vmdocker):
- NOTE: SSH into new debian server so that commands can be copy pasted:
- src: https://docs.docker.com/engine/install/debian/
	## Add Docker's official GPG key:
	apt-get update
	apt-get install ca-certificates curl
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	
echo \ 
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

#Install Docker packages:  
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#Verify installation was successful:
docker run hello-world

--remove hello-world container after test:
docker rm <container_id>

-view version and other info: 
docker info
--results:
Client: Docker Engine - Community
 Version:    27.3.1
 Context:    default
 Debug Mode: false
 Plugins:
  buildx: Docker Buildx (Docker Inc.)
    Version:  v0.17.1
    Path:     /usr/libexec/docker/cli-plugins/docker-buildx
  compose: Docker Compose (Docker Inc.)
    Version:  v2.29.7
    Path:     /usr/libexec/docker/cli-plugins/docker-compose
	
#Mount the NAS server directory and localmedia directory for library files:
https://support.plex.tv/articles/201122318-mounting-network-resources/
-install cifs-utils:
	apt install cifs-utils
-install nfs-common:
	apt install nfs-common
-make mount directories:
	mkdir /mnt/naspool
	mkdir /mnt/sdb
--NOTE: CHOOSE EITHER CIFS OR NFS:
-mount NAS directory as CIFS (SMB):
	mount -t cifs //192.168.1.103/naspool /mnt/naspool -o rw,user=krimmhouse
-mount NAS directory as NFS:
	mount -t nfs 192.168.1.103:/naspool/share /mnt/naspool
-create partition on sdb in docker server:
	fdisk -l (list partitions)
	fdisk /dev/sdb (start fdisk on target disk)
	n (for new partition)
	-accept all defaults by just hitting enterprise
	w - write the new partition if everything looks correct
	lsblk - to show all disks and partitions (should now see sdb1 partition)
	- create an ext4 file-system (WARNING - THIS WILL ERASE ALL CONTENT ON THE DISK):
	mkfs.ext4 /dev/sdb1
	- finally mount the new ext4 disk partition:
	mount /dev/sdb1 /mnt/sdb	

#Edit fstab to auto-mount at boot:
--copy fstab file to backup directory (after making a backups directory, if it doesn't exist, update date in backup as needed)
	mkdir /backups
	cp  /etc/fstab   /backups/fstab_bak_20241204
<!--NO LONGER NEEDED FOR NFS DRIVE: 
	create credentials file for naspool:
	nano /etc/naspoolcredentials.txt 
	username=krimmhouse
	password=<PW FOR USER>
	CTRL+X, y to save/write new file-->
--list uuid for each drive:
	ls -al /dev/disk/by-uuid/
--edit fstab file:
	nano /etc/fstab
--add the lines:
	# local drive sdb1
	UUID=cbd4143f-b99b-4a77-93c8-714ea3d25325       /mnt/sdb        ext4    defaults        0       0
	# naspool (network)
	192.168.1.103:/naspool/share /mnt/naspool nfs defaults 0 0
	<!--OR, if you're using CIFS (note, you'll need the credentials file created - see above)
	//192.168.1.43/naspool  /mnt/naspool    cifs    iocharset=utf8,rw,credentials=/etc/naspoolcredentials.txt  0  0
	-->
	CTRL+X, y to save/write new file
--test fstab - check the last line for errors):
	findmnt --verify
	NOTE: Ignored udf,iso9660
--if everything looks okay, reload the mount fstab:
	systemctl daemon-reload

#Add TV Tuner device for plex container to use:
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

# Setup Docker directory and Docker Compose
mkdir /opt/benolilab-docker
mkdir /opt/benolilab-docker/secrets
- upload the secrets from secure location (each file is specified in the "secrets" top level section of the docker-compose)
- NOTE: for SSH_HOST_NAME on volume_backups service, use format: <user-name>@<ip-address-or-host-name>:<port> (e.g. user@10.0.0.53:22)
- After updating a secret, you will need to restart the service (see below) to get the new value
- upload docker-compose.yml to /opt/benolilab-docker
- run docker compose up
```
	cd /opt/benolilab-docker
	docker ps -a
	docker compose up -d

# To restart a service (by service name, not container name) - e.g. needed after updating a secret value
# List docker compose services and ports etc.:
	docker compose ps 
# Restart the service (to get new secret etc.)
	docker compose restart <service_name>
```
- The -d option in the docker compose up command stands for "detached mode." When you use this option, Docker Compose runs the containers in the background and returns control to your terminal. This allows you to continue using your terminal for other tasks while the containers run.


# Setup Plex in Docker Container (PRE Full Docker-compose - mentioned above - see benolilab-docker):
ref: https://www.rapidseedbox.com/blog/plex-on-docker
- login to the docker vm and create the plex directories:
mkdir /plex
mkdir /plex/{database,transcode,media}
mkdir /opt/plex
- create docker compose file with nano editor (OR USE THE docker-compose.yml file from this repo and follow the steps in setup-docker-directory-and-docker-compose):
nano /opt/plex/docker-compose.yml
- add contents of docker-compose:
--NOTE: if you want to add a new volume (i.e. for library files), add it to the volumes list Below
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
	network_mode: host
	ports:
		- "32400:32400/tcp"
	restart: unless-stopped
	environment:
		- TZ=America/New_York
		- PLEX_CLAIM=<GET CLAIM FROM https://www.plex.tv/claim/>
		- PUID=1000
		- PGID=1000
	volumes:
		- /plex/database:/config
		- /plex/transcode:/transcode
		- /plex/media:/data
		- /mnt/naspool:/naspool
		- /mnt/sdb:/localmedia
	devices:
		- /dev/bus/usb:/dev/bus/usb	
		- /dev/dvb:/dev/dvb
```
=======================
cd /opt/plex
-deploy container as detached:
docker compose up -d
-view info about docker container (with -a shows all, even non-running containers):
docker ps -a

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

#Connect to Plex server via browser (on machine that is on the same local network):
http://192.168.1.63:32400/

#Add TV Tuner and do a channel scan:
Go to Settings > Manage > Live TV & DVR
--The USB device should now show - run a scan of channels and select "Local Broadcast Listings" as the guide info source
--Plex should then show you Live TV channels it found

#Migrate Media data as needed:
See benolinas-migrate-data.md for details

#Add plex library directories via settings to view media
Go to Settings > Manage > Libraries and add libraries as needed
You should see the NAS drive and local drive as added in the volumes within the docker-compose file

#Trouble-shooting memory issues - out of memory (OOM)
- set minumum memory to 16 GB on VM
- backup and modify sysctl.conf
mkdir /backups
	<!--NOTE: THIS DID NOT WORK WELL AND STOPPED CONNECTIONS TO PROXMOX
	cp /etc/sysctl.conf /backups/sysctl.conf_bak_20241211
	nano /etc/sysctl.conf
	- add line to sysctl and save:
	vm.overcommit_memory=2
	- apply changes:
	sysctl -p 

	reverted changes
	-->
cp /etc/modprobe.d/zfs.conf /backups/zfs.conf_bak_20241211
nano /etc/modprobe.d/zfs.conf
--change arc max from default of 3 GB to 8 GB: 
	--e.g. change: options zfs zfs_arc_max=3357540352 
	--to: options zfs zfs_arc_max=8589934592
--save file and apply changes:
update-initramfs -u
reboot


#Setup Portainer (GUI Docker Mgmt)
ref: https://docs.portainer.io/start/install-ce/server/docker/linux
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.21.5
login via web browser:
https://localhost:9443
Replace localhost with the relevant IP address or FQDN if needed, and adjust the port if you changed it earlier.

```
portainer:
    container_name: "portainer"
    image: "portainer/portainer-ce:2.21.5"
    ports:
      - "9443:9443/tcp"
    restart: "always"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "portainer_data:/data"
    healthcheck:
      test: "wget --no-verbose --tries=1 --spider --no-check-certificate https://localhost:9443 || exit 1"
      interval: 60s
      timeout: 5s
      retries: 3
      start_period: 10s
```

-Updating Portainer

-Backup Your Data: Before updating, it's a good idea to back up your Portainer data. This ensures you can restore your setup if anything goes wrong.
	Backing up your Portainer data before updating is a crucial step to ensure you can restore your setup if anything goes wrong. Here’s how you can do it:

	Create a Backup Volume: First, create a backup volume to store your Portainer data.

	docker volume create portainer_data_backup
	Copy Data to the Backup Volume: Use a temporary container to copy the data from your existing Portainer volume to the backup volume.

	docker run --rm --volumes-from portainer -v portainer_data_backup:/backup busybox cp -a /data /backup
	Verify the Backup: Ensure that the data has been copied correctly by inspecting the backup volume.

	docker run --rm -v portainer_data_backup:/backup busybox ls /backup
	Store the Backup Safely: Optionally, you can export the backup volume to a tar file for easier storage and transfer.

	docker run --rm -v portainer_data_backup:/backup -v $(pwd):/host busybox tar cvf /host/portainer_data_backup.tar /backup

-Stop and Remove the Existing Portainer Container:

docker stop portainer
docker rm portainer
Pull the Latest Portainer Image:

docker pull portainer/portainer-ce:latest
Start the Updated Portainer Container:

docker run -d -p 8000:8000 -p 9443:9443 --name=portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
Verify the Update: Log in to your Portainer instance and verify that the update was successful.


#Setup watchtower - to auto update docker images
ref: https://youtu.be/7PJ5jT4JkP4
src: https://containrrr.dev/watchtower/
In Portainer Web GUI, go to add new stack
Paste in the docker compose yml:
```
version: "3"
services:
  watchtower:
	container_name: watchtower
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
	restart: unless-stopped
    environment:
      WATCHTOWER_CLEANUP: true
      WATCHTOWER_DEBUG: true
      WATCHTOWER_ROLLING_RESTART: true
      WATCHTOWER_LABEL_ENABLE: true
      WATCHTOWER_SCHEDULE: 0 0 9 * * 5
      WATCHTOWER_NOTIFICATION_REPORT: true
      WATCHTOWER_NOTIFICATION_URL: discord://token@channel
      WATCHTOWER_NOTIFICATION_TEMPLATE: |
        {{- if .Report -}}
          {{- with .Report -}}
        {{len .Scanned}} Scanned, {{len .Updated}} Updated, {{len .Failed}} Failed
          {{- range .Updated}}
        - {{.Name}} ({{.ImageName}}): {{.CurrentImageID.ShortID}} updated to {{.LatestImageID.ShortID}}
          {{- end -}}
          {{- range .Fresh}}
        - {{.Name}} ({{.ImageName}}): {{.State}}
          {{- end -}}
          {{- range .Skipped}}
        - {{.Name}} ({{.ImageName}}): {{.State}}: {{.Error}}
          {{- end -}}
          {{- range .Failed}}
        - {{.Name}} ({{.ImageName}}): {{.State}}: {{.Error}}
          {{- end -}}
          {{- end -}}
        {{- else -}}
          {{range .Entries -}}{{.Message}}{{"\n"}}{{- end -}}
        {{- end -}}
    labels:
      - com.centurylinklabs.watchtower.enable=true
```
Here's the breakdown of the cron fields for WATCHTOWER_SCHEDULE_:

A cron expression represents a set of times, using 6 space-separated fields.

Field name   | Mandatory? | Allowed values  | Allowed special characters
----------   | ---------- | --------------  | --------------------------
Seconds      | Yes        | 0-59            | * / , -
Minutes      | Yes        | 0-59            | * / , -
Hours        | Yes        | 0-23            | * / , -
Day of month | Yes        | 1-31            | * / , - ?
Month        | Yes        | 1-12 or JAN-DEC | * / , -
Day of week  | Yes        | 0-6 or SUN-SAT  | * / , - ?

With WATCHTOWER_LABEL_ENABLE set to true, you need to go to each docker container and add the label:
com.centurylinklabs.watchtower.enable=true 
(NOTE: This can be done via portainer GUI once installed)

-Setup notifications:
--Format for shoutrrr service
https://discord.com/api/webhooks/webhookid/token
discord://token@webhookid

#Setup uptime-kuma - Notifications for containers
```
services:
  uptime-kuma:
	container_name: uptime-kuma
    image: louislam/uptime-kuma:1
    volumes:
      - ./data:/app/data
	  - /var/run/docker.sock:/var/run/docker.sock
    ports:
      # <Host Port>:<Container Port>
      - 3001:3001
    restart: unless-stopped
```

# Configure SSH to work in docker-volume-backup
```
	# From vmdocker, SSH into the docker-volume-backup <name_or_id_of_container> container:
	docker exec -it docker-volume-backup /bin/sh
	
	# Add SSH client:
	apk add --no-cache openssh
	
	# check version:
	ssh -V
```

# View/Configure routing on docker host to main home network:

- Identify the Docker Bridge Network: First, find the Docker bridge network's gateway IP address. You can do this by inspecting the Docker network:
```
    docker network inspect server_net
```
- Look for the Gateway field in the output.
- Add a Route on the Host Machine: Use the ip route add command to add a route on the host machine. This command will forward traffic from the Docker network to the target network (e.g., 192.168.x.x):
```
    ip route add 192.168.0.0/16 via <docker_gateway_ip>
	# Replace <docker_gateway_ip> with the gateway IP address you found in the previous step.
	# To remove, just change add to del:
	ip route del 192.168.0.0/16 via <docker_gateway_ip>
```
- Verify the Route: Check that the route has been added correctly by running:
```
    ip route
```
- You should see a route entry for the 192.168.0.0/16 network via the Docker gateway IP.
- Configure Firewall Rules (if necessary): Ensure that your firewall rules allow traffic between the Docker network and the target network. You might need to adjust iptables rules or your firewall configuration.
- Once the routing is set up, you should be able to SSH from your Docker container to the device on the 192.168.x.x network:
```
ssh user@192.168.x.x
```

# Test SSH or Tracert (Network issues) From a Container:
- To SSH into a Docker container, you typically use docker exec rather than traditional SSH. Here’s how you can do it:
- Find the Container ID or Name: List all running containers to find the container ID or name.
```
	docker ps
```
- Execute a Shell Inside the Container: Use the docker exec command to start an interactive shell session inside the container. For example, to start a bash shell:
```
	docker exec -it <container_id_or_name> /bin/bash
```
- If the container uses a different shell (e.g., sh), adjust the command accordingly:
```
	docker exec -it <container_id_or_name> /bin/sh
```
- Access the Container: You will now be inside the container and can run commands as needed.
