# Setup Portainer (GUI Docker Mgmt)
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


# Setup watchtower - to auto update docker images
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

# Setup uptime-kuma - Notifications for containers
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