#!/bin/bash

# Description: Script to monitor the progress of a ZFS send from the source pool to the target pool.
# Usage: ./zfs_snapshot_send_progress.sh "YYYY-MM-DD HH:MM:SS" [target_pool]
# Example: ./zfs_snapshot_send_progress.sh "2025-09-18 11:45:00" naspool_backup2

START_TIME_STR="$1"
TARGET_POOL="${2:-naspool_backup1}"
SOURCE_POOL="naspool"

# Convert human-readable time to epoch
START_TIME=$(date -d "$START_TIME_STR" +%s)
if [ -z "$START_TIME" ]; then
    echo "Error: Invalid date format. Use: \"YYYY-MM-DD HH:MM:SS\""
    exit 1
fi

CURRENT_TIME=$(date +%s)
ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

# Format seconds into HH:MM:SS
format_time() {
    local SECONDS=$(printf "%.0f" "$1")
    local H=$((SECONDS / 3600))
    local M=$(((SECONDS % 3600) / 60))
    local S=$((SECONDS % 60))
    printf "%02dh:%02dm:%02ds" $H $M $S
}

# Format bytes into human-readable IEC
format_bytes() {
    local RAW="$1"
    local CLEAN=$(printf "%.0f" "$RAW")
    numfmt --to=iec --suffix=B "$CLEAN"
}

# Get dataset info: name, used, avail
get_dataset_info() {
    zfs list -p -H -r -o name,used,available "$1" | sort
}

# Build associative arrays for source and target datasets
declare -A SOURCE_USED
declare -A SOURCE_AVAIL
declare -A TARGET_USED
declare -A TARGET_AVAIL
SOURCE_NAMES=()
TARGET_NAMES=()

while read -r name used avail; do
    SOURCE_NAMES+=("$name")
    SOURCE_USED["$name"]=$used
    SOURCE_AVAIL["$name"]=$avail
done < <(get_dataset_info "$SOURCE_POOL")

while read -r name used avail; do
    TARGET_NAMES+=("$name")
    TARGET_USED["$name"]=$used
    TARGET_AVAIL["$name"]=$avail
done < <(get_dataset_info "$TARGET_POOL")

# Calculate overall progress
total_source_bytes=0
total_target_bytes=0
total_remaining_bytes=0
total_est_time=0

for name in "${TARGET_NAMES[@]}"; do
 # Skip top-level pool to avoid double-counting
    if [ "$name" == "$TARGET_POOL" ]; then
        continue
    fi
    src_name="${name/$TARGET_POOL/$SOURCE_POOL}"
    src_used=${SOURCE_USED["$src_name"]}
    tgt_used=${TARGET_USED["$name"]}

    if [ -n "$src_used" ] && [ "$src_used" -gt 0 ]; then
        remaining_bytes=$(awk "BEGIN {printf \"%.0f\", $src_used - $tgt_used}")
        bytes_per_sec=$(awk "BEGIN {printf \"%.6f\", $tgt_used / $ELAPSED_TIME}")
        est_time=$(awk "BEGIN {printf \"%.0f\", $remaining_bytes / $bytes_per_sec}")
        total_remaining_bytes=$((total_remaining_bytes + remaining_bytes))
        total_est_time=$((total_est_time + est_time))
    fi

    total_source_bytes=$((total_source_bytes + src_used))
    total_target_bytes=$((total_target_bytes + tgt_used))
done

overall_percent=$(awk "BEGIN {printf \"%.2f\", ($total_target_bytes / $total_source_bytes) * 100}")
elapsed_fmt=$(format_time "$ELAPSED_TIME")
total_est_fmt=$(format_time "$total_est_time")
total_rem_fmt=$(format_bytes "$total_remaining_bytes")

# Header
echo ""
echo "# ZFS Dataset-Level Progress"
echo "- Elapsed Time: $elapsed_fmt"
echo "- Overall Completion: $overall_percent%"
echo "- Estimated Time Remaining: $total_est_fmt"
echo "- Remaining Data: $total_rem_fmt"
echo ""

echo "# Source Pool: $SOURCE_POOL"
printf "%-26s %10s %10s\n" "NAME" "USED" "AVAIL"
for name in "${SOURCE_NAMES[@]}"; do
    printf "%-26s %10s %10s\n" "$name" "$(format_bytes ${SOURCE_USED[$name]})" "$(format_bytes ${SOURCE_AVAIL[$name]})"
done

echo ""
echo "# Target Pool: $TARGET_POOL"
printf "%-26s %10s %10s %7s %15s %10s\n" "NAME" "USED" "AVAIL" "PERC" "ESTTIME" "REMAINING"

for name in "${TARGET_NAMES[@]}"; do
    src_name="${name/$TARGET_POOL/$SOURCE_POOL}"
    src_used=${SOURCE_USED["$src_name"]}
    tgt_used=${TARGET_USED["$name"]}

    if [ -n "$src_used" ] && [ "$src_used" -gt 0 ]; then
        percent=$(awk "BEGIN {printf \"%.2f\", ($tgt_used / $src_used) * 100}")
        remaining_bytes=$(awk "BEGIN {printf \"%.0f\", $src_used - $tgt_used}")
        bytes_per_sec=$(awk "BEGIN {printf \"%.6f\", $tgt_used / $ELAPSED_TIME}")
        est_time=$(awk "BEGIN {printf \"%.0f\", $remaining_bytes / $bytes_per_sec}")

        # Determine which time to show
        if [ "$name" == "$TARGET_POOL" ]; then
            est_time_fmt="$total_est_fmt"
        else
            est_time_fmt="$(format_time "$est_time")"
        fi

        printf "%-26s %10s %10s %6s%% %15s %10s\n" \
            "$name" \
            "$(format_bytes $tgt_used)" \
            "$(format_bytes ${TARGET_AVAIL[$name]})" \
            "$percent" \
            "$est_time_fmt" \
            "$(format_bytes $remaining_bytes)"
    else
        printf "%-26s %10s %10s %6s   %15s %10s\n" \
            "$name" \
            "$(format_bytes $tgt_used)" \
            "$(format_bytes ${TARGET_AVAIL[$name]})" \
            "N/A" \
            "N/A" \
            "N/A"
    fi
done