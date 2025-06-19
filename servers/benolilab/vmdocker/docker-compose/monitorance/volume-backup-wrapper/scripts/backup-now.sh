#!/bin/bash
set -euo pipefail

echo "[backup] Starting backup-now.sh..."

# Volume assembly logic (as before)
VOLUME_ARGS=(--volume /var/run/docker.sock:/var/run/docker.sock:ro)
IFS=',' read -r -a VOLS <<< "${BACKUP_VOLUMES:-}"
for vol in "${VOLS[@]}"; do
  VOLUME_ARGS+=("--volume" "${vol}:/backup/${vol}:ro")
done

# Environment variables
ENV_ARGS=(
  --env BACKUP_FILENAME
  --env BACKUP_PRUNING_PREFIX
  --env BACKUP_RETENTION_DAYS
  --env SSH_HOST_NAME
  --env SSH_PORT
  --env SSH_USER_FILE
  --env SSH_PASSWORD_FILE
  --env SSH_REMOTE_PATH
  --env NOTIFICATION_LEVEL
  --env NOTIFICATION_URLS_FILE
)

# Label args (optional)
LABEL_ARGS=(
  "--label=description=Docker Volume Backup handles backing up named volumes within the host."
)

# Build final docker command
DOCKER_CMD=(docker run --rm --name docker-volume-backup)
DOCKER_CMD+=("${VOLUME_ARGS[@]}" "${ENV_ARGS[@]}" "${LABEL_ARGS[@]}")
DOCKER_CMD+=(offen/docker-volume-backup:latest)

# Dry-run check
if [ "${DRY_RUN:-}" = "true" ]; then
  echo "[backup] Dry run enabled - displaying full docker command:"
  echo
  printf '%q ' "${DOCKER_CMD[@]}"
  echo
else
  echo "[backup] Executing docker-volume-backup..."
  "${DOCKER_CMD[@]}"
fi