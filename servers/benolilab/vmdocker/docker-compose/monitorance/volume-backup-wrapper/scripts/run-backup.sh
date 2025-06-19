#!/bin/bash
set -euo pipefail

SCRIPTPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPTPATH/lock.sh"
"$SCRIPTPATH/wait-for-quiet.sh"
"$SCRIPTPATH/service-toggle.sh" stop 3
"$SCRIPTPATH/backup-now.sh"
"$SCRIPTPATH/service-toggle.sh" start 5
"$SCRIPTPATH/unlock.sh"