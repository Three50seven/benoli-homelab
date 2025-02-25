# Retore Docker Container Volumes from Backup:
reference: https://offen.github.io/docker-volume-backup/how-tos/restore-volumes-from-backup.html

In case you need to restore a volume from a backup, the most straight forward procedure to do so would be:

Stop the container(s) that are using the volume
Untar the backup you want to restore
```
tar -C /tmp -xvf  backup.tar.gz
```
Using a temporary once-off container, mount the volume (the example assumes it’s named data) and copy over the backup. Make sure you copy the correct path level (this depends on how you mount your volume into the backup container), you might need to strip some leading elements
```
docker run -d --name temp_restore_container -v data:/backup_restore alpine
docker cp /tmp/backup/data-backup temp_restore_container:/backup_restore
docker stop temp_restore_container
docker rm temp_restore_container
```
Restart the container(s) that are using the volume
Depending on your setup and the application(s) you are running, this might involve other steps to be taken still.

If you want to rollback an entire volume to an earlier backup snapshot (recommended for database volumes):

Trigger a manual backup if necessary (see Manually triggering a backup).
Stop the container(s) that are using the volume.
If volume was initially created using docker-compose, find out exact volume name using:
```
docker volume ls
```
Remove existing volume (the example assumes it’s named data):
```
docker volume rm data
```
Create new volume with the same name and restore a snapshot:
```
docker run --rm -it -v data:/backup/my-app-backup -v /path/to/local_backups:/archive:ro alpine tar -xvzf /archive/full_backup_filename.tar.gz
```
Restart the container(s) that are using the volume.

# Specifics for vmdocker Host:
```
docker run -d --name temp_restore_container \
-v /plex/database:/backup_restore/plex_server_config \
-v /plex/transcode:/backup_restore/plex_server_transcode \
-v /plex/media:/backup_restore/plex_server_media \
-v portainer_data:/backup_restore/portainer_data \
-v ./data:/backup_retore/uptime_kuma_data \
-v nginx_proxy_config:/backup_restore/nginx_proxy_config \
-v nginx_proxy_data:/backup_restore/nginx_proxy_data \
-v nginx_proxy_letsencrypt:/backup_restore/nginx_proxy_letsencrypt \
alpine

docker cp /tmp/backup/plex_server_config/. temp_restore_container:/backup_restore/plex_server_config
docker cp /tmp/backup/plex_server_transcode/. temp_restore_container:/backup_restore/plex_server_transcode
docker cp /tmp/backup/plex_server_media/. temp_restore_container:/backup_restore/plex_server_media
docker cp /tmp/backup/portainer_data/. temp_restore_container:/backup_restore/portainer_data
docker cp /tmp/backup/uptime_kuma_data/. temp_restore_container:/backup_restore/uptime_kuma_data
docker cp /tmp/backup/nginx_proxy_config/. temp_restore_container:/backup_restore/nginx_proxy_config
docker cp /tmp/backup/nginx_proxy_data/. temp_restore_container:/backup_restore/nginx_proxy_data
docker cp /tmp/backup/nginx_proxy_letsencrypt/. temp_restore_container:/backup_restore/nginx_proxy_letsencrypt

docker stop temp_restore_container
docker rm temp_restore_container
```
