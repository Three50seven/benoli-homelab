# Setup SFTP User
To use the script:

## Run the script (you'll need appropriate permissions):
```
chmod +x setup-sftp-user.sh
./setup-sftp-user.sh username
```
## Restart SSH service:
```
systemctl restart ssh
```

## Copy the private key to your Android device:

Transfer (e.g. `foldersync_key`) to your phone (via USB, email, etc.)
Store it in a secure location on your device
Delete the private key from your NAS after copying it

## Configure FolderSync:

Protocol: SFTP
Server: Your NAS IP address
Port: 22
Username: `foldersync`
Authentication: Private key
Private key file: Select the `foldersync_key` file
Remote folder: `/upload`

The user will be restricted to only use SFTP (no shell access). This provides a secure, password-less setup perfect for automated syncing.

## Immich setup:
In your `docker-compose.yml` for Immich
```
volumes:
  - /naspool/share/benolilab-docker/foldersync:/external/foldersync:ro
```