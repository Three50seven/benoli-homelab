#!/bin/sh
set -e

: "${BACKUP_SERVICES:=}"
ACTION="$1"
DELAY_SECONDS="${2:-0}" # Optional delay in seconds, defaults to 0

if [ -z "$ACTION" ]; then
  echo "[service-toggle] - No action provided. Usage: $0 <start|stop|restart> [delay_secs]"
  exit 1
fi

IFS=','

SERVICES_LIST=""

# Reverse only for start/restart actions
if [ "$ACTION" = "start" ] || [ "$ACTION" = "restart" ]; then
  REVERSED_LIST=""
  for SERVICE in $BACKUP_SERVICES; do
    REVERSED_LIST="$SERVICE ${REVERSED_LIST}"
  done
  # Rejoin with commas
  SERVICES_LIST=$(echo "$REVERSED_LIST" | tr ' ' ',' | sed 's/,$//')
else
  SERVICES_LIST="$BACKUP_SERVICES"
fi

get_restart_policy_label() {
    local SERVICE_NAME="$1"
    docker inspect "$SERVICE_NAME" \
    --format '{{ index .Config.Labels "com.docker.backup.restart-policy" }}'
}

restore_restart_policy() {
    local SERVICE_NAME="$1"
    local LABEL_POLICY="$(get_restart_policy_label "$SERVICE_NAME")"

    if [ -n "$LABEL_POLICY" ]; then
        docker update --restart="$LABEL_POLICY" "$SERVICE_NAME"
        echo "[service-toggle] - Restored restart policy from label: $LABEL_POLICY"
    else
        echo "[service-toggle] - No restart policy label found on $SERVICE_NAME. Skipping restore."
    fi
}

for SERVICE in $SERVICES_LIST; do
  case "$ACTION" in
    start)
      echo "[service-toggle] - Starting $SERVICE..."
      docker start "$SERVICE" || echo "[service-toggle] - Failed to start $SERVICE"
      restore_restart_policy "$SERVICE"
      ;;
    stop)
      echo "[service-toggle] - Setting restart to 'no' for $SERVICE..."
      docker update --restart=no "$SERVICE"
      echo "[service-toggle] - Stopping $SERVICE..."
      docker stop "$SERVICE" || echo "[service-toggle] - Failed to stop $SERVICE"
      ;;
    restart)
      echo "[service-toggle] - Restarting $SERVICE..."
      docker stop "$SERVICE" || echo "[service-toggle] - Failed to stop $SERVICE (already stopped?)"
      sleep "$DELAY_SECONDS"
      docker start "$SERVICE" || echo "[service-toggle] - Failed to start $SERVICE"
      restore_restart_policy "$SERVICE"
      ;;
    *)
      echo "[service-toggle] - Unknown action: $ACTION"
      exit 1
      ;;
  esac

  if [ "$ACTION" = "start" ] || [ "$ACTION" = "stop" ]; then
    if [ "$DELAY_SECONDS" -gt 0 ]; then
      echo "[service-toggle] - Delaying $DELAY_SECONDS seconds..."
      sleep "$DELAY_SECONDS"
    fi
  fi
done