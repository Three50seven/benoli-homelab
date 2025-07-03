#!/bin/bash
trap '' PIPE
echo "$(date) healthcheck heartbeat" > $HEARTBEAT_LOG 2>&1
exit 0