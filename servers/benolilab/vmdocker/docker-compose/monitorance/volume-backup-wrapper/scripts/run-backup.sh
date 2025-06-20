#!/bin/bash
set -euo pipefail
# set -euo pipefail explained:
# -e: Exit immediately if any command returns a non-zero status
# -u: - Treat unset variables as an error and exit immediately
# -o pipefail: - If any command in a pipeline fails, the entire pipeline fails

# Ignore SIGPIPE errors from supercronic (status 141)
trap '' PIPE

# Redirect logging to the docker compose log window so things like echo show in the docker compose logs
exec >> /proc/1/fd/1 2>&1

SCRIPTPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPTPATH/lock.sh"
"$SCRIPTPATH/wait-for-quiet.sh"
"$SCRIPTPATH/service-toggle.sh" stop 3
"$SCRIPTPATH/backup-now.sh"
"$SCRIPTPATH/service-toggle.sh" start 5
"$SCRIPTPATH/unlock.sh"
"$SCRIPTPATH/preview-schedule.sh"