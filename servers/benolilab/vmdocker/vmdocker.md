# Download Debian OS ISO:
Go to Local storage - ISO (or other storage if added as directory from ZFS drives)
Download: https://debian.osuosl.org/debian-cdimage/12.8.0/amd64/iso-dvd/debian-12.8.0-amd64-DVD-1.iso
Note: This was the latest URL from the Debian Host as of 2024.11.30 - check latest for updated version

# Setup debian server VM for docker engine:
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

# Install and check SSH server:
apt install openssh-server
systemctl status ssh

# Permit SSH Root login:
nano /etc/ssh/sshd_config
Find # Authentication: section > PermitRootLogin
Remove "#" from line that says PermitRootLogin and change value to "yes"
exit and save the nano editor

# Setup Debian apt sources:
sudo nano /etc/apt/sources.list
 - view latest: https://wiki.debian.org/SourcesList
 - e.g. (comment out deb cdrom line)
deb-src http://deb.debian.org/debian bookworm main non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main non-free-firmware

# Update Debian installation:
apt update
apt upgrade

# Set static IP on Debian 12 VM (note you'll need root user for this):
https://www.linuxtechi.com/configure-static-ip-address-debian/
ip add show
 - get the name of the network interface (in this case it's ens18)
nano /etc/network/interfaces

Replace the line 'allow-htplug ens18' with 'auto ens18' and change dhcp parameter to static.  Below is my sample file, change interface name and ip details as per your environment.

auto ens18
iface ens18 inet static
        address 192.168.1.63/24
        network 192.168.1.0
        broadcast 192.168.1.255
        gateway 192.168.1.1
        dns-nameservers 8.8.8.8

# Setup Docker on new Debian Server (vmdocker):
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

# Install Docker packages:  
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation was successful:
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

# Mount the NAS server directory and localmedia directory for library files:
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

# Edit fstab to auto-mount at boot:
	--copy fstab file to backup directory (after making a backups directory, if it doesn't exist, update date in backup as needed)
		mkdir /backups
		cp  /etc/fstab   /backups/fstab_bak_20241204
	--list uuid for each drive:
		ls -al /dev/disk/by-uuid/
	--edit fstab file:
		nano /etc/fstab
	--add the lines:
		# local drive sdb1
		UUID=cbd4143f-b99b-4a77-93c8-714ea3d25325       /mnt/sdb        ext4    defaults        0       0
		# naspool (network)
		192.168.1.103:/naspool/share /mnt/naspool nfs defaults 0 0	
		CTRL+X, y to save/write new file
	--test fstab - check the last line for errors):
		findmnt --verify
		NOTE: Ignored udf,iso9660
	--if everything looks okay, reload the mount fstab:
		systemctl daemon-reload

# Setup Docker directory and Docker Compose (Preferred)
```
	mkdir /opt/benolilab-docker
	mkdir /opt/benolilab-docker/secrets
```
- upload the secrets from secure location (each file is specified in the "secrets" top level section of the docker-compose)
- environment variables for .env file:
- NOTE: Environment variables are exposed in the logs, so it is recommended to use docker secrets for passwords and other variables you do not want exposed in plain text in the logs
```	
	NAS_IP_ADDRESS=<nas_ip_or_host_name>
```
- upload the .env (environment variables) file to /opt/benolilab-docker
- After updating a secret or env-variable, you will need to restart the service (see below) to get the new value
- upload docker-compose.yml to /opt/benolilab-docker
- run docker compose up -d (detached option), note: without -d option, containers will run in foreground and show logs in terminal until stoped (w/ CTRL+C)
- NOTE: The -d option in the docker compose up command stands for "detached mode." When you use this option, Docker Compose runs the containers in the background and returns control to your terminal. This allows you to continue using your terminal for other tasks while the containers run.
- Add the --build flag after "up" like so in order to rebuild a container with new secrets or ext. files: docker compose up --build -d
```
	cd /opt/benolilab-docker
	docker ps -a
	docker compose up -d
	# Or for a specific container (e.g. after adding to docker compose, without updating all containers)
	docker compose up -d <container_name>
	# Or to rebuild: 
	docker compose up --build -d <container_name>
	# Or to just restart:
	docker compose restart <container_name>
```

# To restart a service (by service name, not container name) - e.g. needed after updating a secret value
- List docker compose services and ports etc.:
```
	docker compose ps 
```
- Restart the service (to get new secret etc.)
```
	docker compose restart <service_name>
```

# Custom filter process status of docker or docker compose:
```
	docker ps --format "table {{.Image}}\t{{.Names}}\t{{.Status}}"
	docker compose ps --format "table {{.Image}}\t{{.Name}}\t{{.Status}}\t{{.Service}}"
```

# Monitor Memory usage and process IDs of Containers (--no-stream option takes snapshot - leave this off to view real-time):
```
	docker stats --no-stream
```

# Trouble-shooting memory issues - out of memory (OOM)
- set minumum memory to 16 GB on VM
- backup and modify sysctl.conf
- it seemed there wasn't enough memory for zfs to perform maintenance and it was killing the docker vm, so adjusted memory settings on VM to fix this
```
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
```
--change arc max from default of 3 GB to 8 GB: 
	--e.g. change: options zfs zfs_arc_max=3357540352 
	--to: options zfs zfs_arc_max=8589934592
--save file and apply changes:
update-initramfs -u
reboot

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
- To SSH into a Docker container, you typically use docker exec rather than traditional SSH. Here's how you can do it:
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

# Docker Volumes and files location on host:
/var/lib/docker
e.g. Volumes are here: /var/lib/docker/volumes

# Syncthing Group and User setup
_also setup on NAS - see [benolinas.md](https://github.com/Three50seven/benoli-homelab/blob/main/servers/benolinas/benolinas.md)_

## Add syncthinguser Group:
	groupadd -g 1001 syncthinguser

## Add syncthinguser User (for managing syncthing service access to share without root access)
	useradd -u 1001 -g 1001 -m -s /bin/bash syncthinguser

## Create backup directories for docker containers (-p option will ensure parent directories are also created):
```
mkdir -p /mnt/naspool/benolilab-docker/syncthingdata
```
## Change owner and grant permissions to read/write for syncthinguser user on backup directory:
```
chown syncthinguser:syncthinguser -R /mnt/naspool/benolilab-docker/syncthingdata
chmod -R 770 /mnt/naspool/benolilab-docker/syncthingdata
```
## Update the default folder settings 
- Go to GUI via web URL - https://[DOCKER_HOST_IP]:8384 > Actions > Settings > Click "Edit Folder Defaults" in "General" tab > Click "Advanced" tab
- Change folder settings to receive only
- Check box to "Ignore Permissions"

## When adding a new folder in Syncthing GUI:
- Create a new folder for each device's backups to keep syncing easier to manage.
- Make sure default settings are used (as mentioned/set above)
- Make sure to use the full folder path, i.e. /syncthingdata/new-folder-name
- Use lowercase kebab formatting e.g. new-folder-name	

## Verify that the UID/GID mapping in the Syncthing container is correct:
```
# Run the following on the Docker host (vmdocker):
id syncthinguser
# Output should be something like: uid=1001(syncthinguser) gid=1001(syncthinguser) groups=1001(syncthinguser)
	
# Run the same on Docker host and you should see a similar output (make sure the UID and GIDs are the same)
# Verify the owner is syncthinguser for the mnt
ls -ld /mnt/naspool/benolilab-docker/syncthingdata
	
# If it's not, change ownership:
chown -R 1001:1001 /mnt/naspool/benolilab-docker/syncthingdata
	
# Verify the UID/GID is used by the container:
docker logs syncthing | grep "User UID" && docker logs syncthing | grep "User GID"
# Expected output: User UID:    1001 && User GID:    1001
	
# NOTE: You may need to take it down and rebuild it restart it if changes are made
docker compose down syncthing
docker compose up --build -d syncthing
```

# Immich - photo and video manager and backup service
- Add immichgroup Group && User (for managing immich service access to share without root access):
```
groupadd immichgroup
useradd -r -s /bin/false -g immichgroup immichuser
id immichuser # Get the user and group id for docker-compose.yml - see variable user:
```
- Create a storage directory for immich on the naspool and change owner to new user/group with rwx permissions:
```
mkdir -p /mnt/naspool/benolilab-docker/immichdata
chown -R immichuser:immichgroup /mnt/naspool/benolilab-docker/immichdata
chmod -R 770 /mnt/naspool/benolilab-docker/immichdata
```
- Create the docker-compose directory for the immich docker stack:
```
mkdir -p /opt/immich-docker
```
- Follow similar directions for running docker compose etc. for the immich compose file
```
cd /opt/immich-docker
docker ps -a
docker compose up -d
```

# Monitorance - Monitoring and Maintenance apps
- Create the docker-compose directory for the monitorance docker stack:
```
mkdir -p /opt/monitorance-docker
mkdir /opt/monitorance-docker/secrets
```
- Follow similar directions for running docker compose etc. for the monitorance compose file
```
cd /opt/monitorance-docker
docker ps -a
docker compose up -d
```

# Create Docker Container called volume-backup-wrapper for custom volume backup scripts
- This is a wrapper container for the offen\docker-volume-backup container
- Here are some common script commands for testing/debugging the docker container:
```
# Test-drive the app - make sure DRY_RUN is set to true in backup.env file before running the run-backup.sh script if you just want to test the command output
	docker compose run --rm -it volume-backup-wrapper /bin/sh
# breakdown of command: 
# -rm Automatically removes the container after it exits to prevent clutter with leftover containers
# -i stands for "Interactive" - keeps STDIN open so you can type into the shell
# -t Allocates a pseudo-TTY, which makes the shell experience feel like you're on a real terminal

# Or try running with the entrypoint specified:
	docker compose run --rm --entrypoint /app/entrypoint.sh volume-backup-wrapper

# Once inside the shell of the wrapper container, you can run this to test the backup scripts:
		/bin/sh -c '/app/scripts/run-backup.sh'

# Type 'exit' to quit the container shell and destroy the temp container.

# To rebuild after changing the Dockerfile, or other internal files (e.g. scripts) run:
	docker compose build --no-cache

# Or to rebuild with compose:
	docker compose up -d --build volume-backup-wrapper

# To run shell inside the composed container and examine file contents etc., run:
	docker compose exec volume-backup-wrapper sh

# You can also run the full docker command that the wrapper generates or a snippit to make sure volumes, environment variables, etc. are being mounted properly:
	docker run --rm -it --volume /var/run/docker.sock:/var/run/docker.sock:ro --volume "${HOST_SSH_USER_FILE}:${SSH_USER_FILE}:ro" --volume "${HOST_SSH_PASSWORD_FILE}:${SSH_PASSWORD_FILE}:ro" --volume "${HOST_NOTIFICATION_URLS_FILE}:${NOTIFICATION_URLS_FILE}:ro" --env BACKUP_FILENAME --env BACKUP_PRUNING_PREFIX --env BACKUP_RETENTION_DAYS --env SSH_HOST_NAME --env SSH_PORT --env SSH_USER_FILE="$SSH_USER_FILE" --env SSH_PASSWORD_FILE=${SSH_PASSWORD_FILE} --env SSH_REMOTE_PATH --env NOTIFICATION_LEVEL --env NOTIFICATION_URLS_FILE="$NOTIFICATION_URLS_FILE" alpine sh
```

# Create Docker Container called zfs-backup for custom ZFS Pool backup scripts
- This is a container for triggering the ZFS backup scripts on the NAS server.
- NOTE: Make sure the zfs_backup.sh and secrets exist on the NAS server, as this container is dependent on these._
- Generate a private ssh key:
```
ssh-keygen -t rsa -b 4096 -C "zfs-backup-key"
# optionally use ed25519 instead of rsa if the NAS supports it, -C is used to label the key
# when prompted, save or move the file to : /opt/monitorance-docker/secrets/.zfs_backup_ssh_key
# leave the passphrase blank for automated backups (recommended ONLY if you're using Docker secrets or another secure mechanism to protect it)
```
Once the key is generated, copy the public key to the nas server:
```
ssh-copy-id -i /opt/monitorance-docker/secrets/.zfs_backup_ssh_key.pub youruser@nas-host
# You should be required to enter the password for the SSH host to copy the public key to it's keychain
```
There is also a host fingerprint validation step, so make sure to add the host fingerprint to known_hosts in the '/opt/monitorance-docker/zfs-backup' path
```
# initialize the fingerprint - note to change the host IP in the following command to the proper NAS host: 
ssh-keyscan -t rsa 192.168.1.100 > /opt/monitorance-docker/zfs-backup/known_hosts

# Preview the fingerprint like so: 
ssh-keyscan -t rsa 192.168.1.100 | ssh-keygen -lf -

# You should see the full fingerprint and host metadata like so:
# 3072 SHA256:fingerprintalphanumeric3435343/updateThisWithYourHostsFingerPrint 192.168.1.100 (RSA)
# Copy this to the zfs_bcakup.env file variable: SSH_ZFS_HOST_FINGERPRINT
```

Here are some common script commands for testing/debugging the docker container:
```
# Test-drive the app - make sure DRY_RUN is set to true in the docker-compose file for the zfs-backup container
	docker compose run --rm -it zfs-backup /bin/sh
# breakdown of command: 
# -rm Automatically removes the container after it exits to prevent clutter with leftover containers
# -i stands for "Interactive" - keeps STDIN open so you can type into the shell
# -t Allocates a pseudo-TTY, which makes the shell experience feel like you're on a real terminal

# Or try running with the entrypoint specified:
	docker compose run --rm --entrypoint /app/entrypoint.sh zfs-backup

# Once inside the shell of the container, you can run this to test the backup scripts:
		/bin/sh -c '/app/scripts/zfs-backup-trigger.sh'

# Type 'exit' to quit the container shell and destroy the temp container.

# To rebuild after changing the Dockerfile, or other internal files (e.g. scripts) run:
	docker compose build --no-cache

# Or to rebuild with compose:
	docker compose up -d --build zfs-backup

# To run shell inside the composed container and examine file contents etc., run:
	docker compose exec zfs-backup sh

# Once inside the container's shell, you can run a script like the following to test various output.  
# Note, the ' >> /proc/1/fd/1 2>&1' part will redirect output to the docker logs and show in Portainer > logs for example.  
# Leave ' >> /proc/1/fd/1 2>&1' off the command, if you want to just see output in the same console window you're running.
scripts/zfs-backup-trigger.sh daily 7 >> /proc/1/fd/1 2>&1
```

# Removing special characters in text editor:
- Some special characters will cause some scripts to fail, so it's best to remove them
- Search for: [^\x00-\x7F]
- make sure to check or enable "use regular expressions"

## Also make sure line endings are Unix in shell scripts
- in Notepad++ you can open the file, and look in the bottom right corner to see if the file is Windows (CR LF) or Unix (LF)
- to convert to Unix (LF) open in Notepad++ and click Edit > EOL Conversion > Unix (LF)
- Save the file and upload to host machine needing/using the script

# Spin up a test container with bash and curl and start up interactive shell:
```
	docker run -it --rm alpine:latest /bin/sh -c "apk add --no-cache bash curl grep coreutils gettext && /bin/sh"

	# Example to add supercronic for testing custom volume-backup-wrapper
    curl -sLo /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/latest/download/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic
```
- Note: use 'apk add' manually, once inside the shell, to add any additional libraries or packages to the base Alpine OS.