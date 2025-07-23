#!/bin/bash
set -euo pipefail
trap '' PIPE

: "${CRON_FILE:=/app/config/selfsigned-certgen.cron}"

# Setting timout so that the debug exits gracefully; otherwise supercronic will continue to run on the schedule
# TODO: Make the timeout customizable if a job list is very big, but 3s should be plenty of time for starting out
echo "[preview-schedule] - Previewing supercronic's job schedule from crontab file by running in DEBUG mode:"

if ! OUTPUT=$(timeout 3s supercronic --debug "$CRON_FILE" 2>&1); then
  CODE=$?
  case $CODE in
    0|124)
      echo "[preview-schedule] - Timeout hit, as expected, while previewing schedule (exit code 124). Partial output may follow:"
      echo "$OUTPUT" | awk '/^# job:/ {job=$0; next} /job will run next at/ {print job "\n" $0 "\n"}'
      ;;
    *)
      echo "[preview-schedule] - Supercronic failed with exit code $CODE."
      echo "$OUTPUT"
      ;;
  esac
else
  echo "$OUTPUT" | awk '/^# job:/ {job=$0; next} /job will run next at/ {print job "\n" $0 "\n"}'
fi

exit 0