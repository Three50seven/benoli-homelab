#!/bin/bash
set -euo pipefail
trap '' PIPE

# Redirect logging to the docker compose log window so things like echo show in the docker compose logs
exec >> /proc/1/fd/1 2>&1

CONTAINERS="${QUIET_CONTAINERS:-immich-server}"
QUIET_PERIOD="${QUIET_PERIOD:-60}"
TIMEOUT="${QUIET_TIMEOUT:-300}"
MATCH_PATTERN="${QUIET_LOG_PATTERN:-upload}"

IFS=',' read -r -a CONTAINER_LIST <<< "$CONTAINERS"

echo "[QUIET] Monitoring containers: ${CONTAINERS} for '$MATCH_PATTERN' inactivity"

START=$(date +%s)
while true; do
  ACTIVITY_FOUND=0

  for CONTAINER in "${CONTAINER_LIST[@]}"; do
    echo "[QUIET] Checking logs for: $CONTAINER"
    if docker logs --since "${QUIET_PERIOD}s" "$CONTAINER" 2>&1 | grep -qi "$MATCH_PATTERN"; then
      echo "[QUIET] Activity detected in $CONTAINER"
      ACTIVITY_FOUND=1
      break
    fi
  done

  if [ "$ACTIVITY_FOUND" -eq 0 ]; then
    echo "[QUIET] All containers quiet. Proceeding with backup."
    break
  fi

  if [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ]; then
    echo "[QUIET] Timeout reached. Proceeding anyway."
    break
  fi

  echo "[QUIET] Waiting for quiet period..."
  sleep 10
done