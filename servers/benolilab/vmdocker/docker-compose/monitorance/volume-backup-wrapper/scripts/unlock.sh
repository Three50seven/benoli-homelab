#!/bin/bash
trap '' PIPE
LOCKFILE="/tmp/docker_backup.lock"
[ -f "$LOCKFILE" ] && rm -f "$LOCKFILE" && echo "[LOCK] Lock released."