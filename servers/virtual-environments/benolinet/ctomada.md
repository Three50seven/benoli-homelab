2024.08.17
Omada TP-Link SDN Controller
192.168.1.252/24
gw: 192.168.1.1
8gb RAM, 1 CPU, 10GB Disk size

# Tutorial link:
https://www.youtube.com/watch?v=e86G-B-nT6U

# Install Debian 12 as OS

# Clean and install:
apt-get clean && apt-get update
apg-get upgrade

# View dependencies and prereq's for Omada (Page 9): 
https://static.tp-link.com/upload/manual/2024/202405/20240517/1910013634_Omada%20SDN%20Controller_User%20Guide_REV5.14.pdf

# Install Java 8 (required for Omada):
https://stackoverflow.com/questions/60806605/debian-apt-cant-find-openjdk-8-jdk

	cd /etc/apt
	cp sources.list sources.list.backupyyyymmdd
    add the following line to via: nano /etc/apt/sources.list

    deb http://deb.debian.org/debian/ sid main

    install openjdk8

    //Update the repositories<br/>
    $ sudo apt-get update<br/>
    $ sudo apt-get install -y openjdk-8-jdk

# Install jsvc and curl:
apt-get install jsvc
apt-get install curl

# Update Source list and Install Mongo DB 3.0.15–3.6.18 (Note, couldn't find 3.6.18, so just installed latest Mongo DB at the time (7.0.12):
apt-get install gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get install -y mongodb-org

# Get the latest Omada software:
https://www.tp-link.com/us/support/download/omada-software-controller/#Controller_Software
e.g.: download to linux home directory for installing
wget https://static.tp-link.com/upload/software/2024/202407/20240710/Omada_SDN_Controller_v5.14.26.1_linux_x64.deb

# Install Omada packages (or whatever the latest file name is):
dpkg -i Omada_SDN_Controller_v5.14.26.1_linux_x64.deb

OUTPUT:
Selecting previously unselected package omadac.
(Reading database ... 25703 files and directories currently installed.)
Preparing to unpack Omada_SDN_Controller_v5.14.26.1_linux_x64.deb ...
Unpacking omadac (5.14.26.1) ...
Setting up omadac (5.14.26.1) ...
Install Omada Controller succeeded!
==========================
current data is empty
Omada Controller will start up with system boot. You can also control it by [/usr/bin/tpeap]. 
check omada
Starting Omada Controller. Please wait..................................................................
Started successfully.
You can visit http://localhost:8088 on this host to manage the wireless network.
========================

# SDN Should be installed correctly:
NOTE: Use the IP instead of localhost
http://192.168.3.253:8088

# Allow SSH:
Update Config:
nano /etc/ssh/sshd_config
Change
PermitRootLogin without-password
to
PermitRootLogin yes

then service sshd restart and then ssh should work with password authentication.

# Setup Heat Map:
src: https://www.tp-link.com/us/support/faq/3687/