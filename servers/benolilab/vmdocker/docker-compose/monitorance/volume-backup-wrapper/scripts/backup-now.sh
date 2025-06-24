#!/bin/bash
set -euo pipefail

# Redirect logging to the docker compose log window so things like echo show in the docker compose logs
exec >> /proc/1/fd/1 2>&1

echo "[backup] Starting backup-now.sh..."

# Volume assembly logic (as before)
VOLUME_ARGS=(--volume /var/run/docker.sock:/var/run/docker.sock:ro)
IFS=',' read -r -a VOLS <<< "${BACKUP_VOLUMES:-}"
for vol in "${VOLS[@]}"; do
  VOLUME_ARGS+=("--volume" "${vol}:/backup/${vol}:ro")
done

# Manually mount secrets passed in as volumes from the host:
VOLUME_ARGS+=("--volume" "${HOST_SSH_USER_FILE}:${SSH_USER_FILE}:ro")
VOLUME_ARGS+=("--volume" "${HOST_SSH_PASSWORD_FILE}:${SSH_PASSWORD_FILE}:ro")
VOLUME_ARGS+=("--volume" "${HOST_NOTIFICATION_URLS_FILE}:${NOTIFICATION_URLS_FILE}:ro")

# Environment variables
ENV_ARGS=(
  --env BACKUP_FILENAME
  --env BACKUP_PRUNING_PREFIX
  --env BACKUP_RETENTION_DAYS
  --env SSH_HOST_NAME
  --env SSH_PORT
  --env SSH_USER_FILE="$SSH_USER_FILE"
  --env SSH_PASSWORD_FILE="$SSH_PASSWORD_FILE"
  --env SSH_REMOTE_PATH
  --env NOTIFICATION_LEVEL
  --env NOTIFICATION_URLS_FILE="$NOTIFICATION_URLS_FILE"
)

# Label args (optional)
LABEL_ARGS=(
  '--label=description="Docker Volume Backup handles backing up named volumes within the host."'
)

# Build final docker command - note: this locks the volume-backup to a specific version - TODO: Make this an env. variable
DOCKER_CMD=(docker run --rm)
DOCKER_CMD+=("${VOLUME_ARGS[@]}" "${ENV_ARGS[@]}" "${LABEL_ARGS[@]}")
DOCKER_CMD+=(--entrypoint backup)
DOCKER_CMD+=(offen/docker-volume-backup:v2)

# Show the full docker command in logs
echo '[backup] Docker command:'
printf '%q ' "${DOCKER_CMD[@]}"
echo

# Dry-run check
if [ "${DRY_RUN:-}" = "true" ]; then
  echo "[backup] Dry run enabled - the full docker command will not be executed and only displayed."  
else
  echo "[backup] Executing docker-volume-backup..."
  "${DOCKER_CMD[@]}"
fi