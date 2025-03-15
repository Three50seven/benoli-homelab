# Convert docker host file to volume (using uptime_kuma and plex as examples):
To convert a Docker host file or directory (e.g., ./data) to a volume that you can mount into an already running container (e.g., uptime_kuma_data), you can't directly modify the volume of a running container, but you can follow these steps:

Create a Docker Volume: First, create the Docker volume that you want to map (in this case, uptime_kuma_data).
```
	# Uptime-Kuma:
	docker volume create uptime_kuma_data

	# Plex:
	docker volume create plex_server_config
	docker volume create plex_server_transcode
	docker volume create plex_server_media
```
Copy Data from Host to Volume: Use a temporary container to copy the data from the host (./data) into the volume.
```
	# Uptime-Kuma:
	docker run --rm -v $(pwd)/data:/data -v uptime_kuma_data:/volume busybox sh -c "cp -r /data/. /volume/"

	# Plex: 
	docker run --rm -v /plex/database:/plex/database -v plex_server_config:/volume busybox sh -c "cp -r /plex/database/. /volume/"
	docker run --rm -v /plex/transcode:/plex/transcode -v plex_server_transcode:/volume busybox sh -c "cp -r /plex/transcode/. /volume/"
	docker run --rm -v /plex/media:/plex/media -v plex_server_media:/volume busybox sh -c "cp -r /plex/media/. /volume/"
```
This will copy everything from ./data on the host to the uptime_kuma_data volume.

Stop the Running Container: Stop the container (uptime_kuma_container) that you want to apply the volume to.
```
	docker stop uptime-kuma
	docker stop plex
```
Update the Docker Container in the docker-compose file with the New Volume, don't forget to add the volume to the list of volumes

Re-run the compose command:
NOTE: You will get a warning unless you add external: true to each of the new volumes - this tells docker compose not to overwrite the volume or try to re-create it
- to avoid having the "external" flag, see "Copy docker volume and restore steps" below
```
	docker compose up -d
```

By following these steps, the host's ./data will be copied to the uptime_kuma_data volume, and the volume will be mounted in the container. You’ll have successfully migrated the data from the host to the Docker volume.
You can then clean-up the directory like so:
Use the find command on the host to see if there are any other remnants of the files you copied to the new volumes:
```
	find / -name "kuma.db" 2>/dev/null  # Find both
	find / -name "plex" 2>/dev/null  # Find both files and directories
```
!!!WARNING - THIS IS IRREVERSIBLE AND WILL DELETE EVERYTHING INSIDE THE DIRECTORIES:
- a safter way would be through FileZilla or another file explorer/editor
```
	rm -rf /data

```

# Manually Copy docker volume and restore steps (so that docker-compose takes full ownership and you don't get the "volume already exists" warning)
Remove the External Volume (If Data Persistence Is Needed, Back It Up) If you need to keep the data, you should back it up first:

```
docker run --rm -v plex_server_config:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /data/. /backup/plex_server_config/" && \
docker run --rm -v plex_server_media:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /data/. /backup/plex_server_media/" && \
docker run --rm -v plex_server_transcode:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /data/. /backup/plex_server_transcode/" && \
docker run --rm -v uptime_kuma_data:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /data/. /backup/uptime_kuma_data/" && \
docker run --rm -v portainer_data:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /data/. /backup/portainer_data/"

```
Then remove the external volume:
```
	docker volume rm plex_server_config plex_server_media plex_server_transcode uptime_kuma_data portainer_data
```
Modify docker-compose.yml to Define the Volume Without external: true Update your docker-compose.yml to define the volume under volumes: without marking it as external:

Recreate the Volume Using Docker Compose Run the following command to let Docker Compose create and take ownership of the volume:
```
	docker compose up -d
```

(Optional) Restore Data if You Backed It Up If you previously backed up the data, restore it to the new volume:
NOTE: Had to run docker compose down in order to recreate the server_net network again too. otherwise you may get an error that the network doesn't exist
```
docker run --rm -v plex_server_config:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /backup/plex_server_config/. /data/" && \
docker run --rm -v plex_server_media:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /backup/plex_server_media/. /data/" && \
docker run --rm -v plex_server_transcode:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /backup/plex_server_transcode/. /data/" && \
docker run --rm -v uptime_kuma_data:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /backup/uptime_kuma_data/. /data/" && \
docker run --rm -v portainer_data:/data -v $(pwd)/backup:/backup busybox sh -c "cp -r /backup/portainer_data/. /data/"
```
