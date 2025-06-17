# Retore Docker Container Volumes from Backup:
reference: https://offen.github.io/docker-volume-backup/how-tos/restore-volumes-from-backup.html

In case you need to restore a volume from a backup, the most straight forward procedure to do so would be:

## Check which containers are using the volume:
```
	docker ps -a --filter volume=<VOLUME_NAME_HERE> --format "{{.Names}}"
```

Stop the container(s) that are using the volume
```
	docker stop <container_name>
	docker rm <containera_name> # This step is needed to stop the container from using the volume
	docker run --rm -v <volume_name>:/data -v /host_backup:/backup alpine cp -r /data /backup
	docker volume rm <volume_name> # Only remove the volume after making a backup
```
Untar the backup you want to restore
```
tar -C /tmp -xvf  backup.tar.gz
```
Using a temporary once-off container, mount the volume (the example assumes it's named data) and copy over the backup. Make sure you copy the correct path level (this depends on how you mount your volume into the backup container), you might need to strip some leading elements
You may be able to alternatively run docker compose up -d for all the containers and just let it recreate the volume after removing the old or corrupt one.
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
Remove existing volume (the example assumes it's named data):
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

-v plex_server_config:/backup_restore/plex_server_config \
-v plex_server_transcode:/backup_restore/plex_server_transcode \
-v plex_server_media:/backup_restore/plex_server_media \
-v portainer_data:/backup_restore/portainer_data \
-v uptime_kuma_data:/backup_retore/uptime_kuma_data \
-v nginx_proxy_config:/backup_restore/nginx_proxy_config \
-v nginx_proxy_data:/backup_restore/nginx_proxy_data \
-v nginx_proxy_letsencrypt:/backup_restore/nginx_proxy_letsencrypt \
-v adguard_work:/backup_restore/adguard_work \
-v adguard_conf:/backup_restore/adguard_conf \
alpine

docker cp /tmp/backup/plex_server_config/. temp_restore_container:/backup_restore/plex_server_config
docker cp /tmp/backup/plex_server_transcode/. temp_restore_container:/backup_restore/plex_server_transcode
docker cp /tmp/backup/plex_server_media/. temp_restore_container:/backup_restore/plex_server_media
docker cp /tmp/backup/portainer_data/. temp_restore_container:/backup_restore/portainer_data
docker cp /tmp/backup/uptime_kuma_data/. temp_restore_container:/backup_restore/uptime_kuma_data
docker cp /tmp/backup/nginx_proxy_config/. temp_restore_container:/backup_restore/nginx_proxy_config
docker cp /tmp/backup/nginx_proxy_data/. temp_restore_container:/backup_restore/nginx_proxy_data
docker cp /tmp/backup/nginx_proxy_letsencrypt/. temp_restore_container:/backup_restore/nginx_proxy_letsencrypt
docker cp /tmp/backup/adguard_work/. temp_restore_container:/backup_restore/adguard_work
docker cp /tmp/backup/adguard_conf/. temp_restore_container:/backup_restore/adguard_conf

docker stop temp_restore_container
docker rm temp_restore_container
```
