#!/bin/bash

# Description: Script to monitor the progress of a ZFS send from the source pool to the target pool.
# Usage: ./zfs_snapshot_send_progress.sh "YYYY-MM-DD HH:MM:SS" [INCREMENTAL_GB_TO_SEND]
# Example: ./zfs_snapshot_send_progress.sh "2025-09-18 11:45:00" 219

START_TIME_STR="$1"
INCREMENTAL_GB_TO_SEND="$2"

# --- Argument Validation ---
if [ -z "$START_TIME_STR" ] || [ -z "$INCREMENTAL_GB_TO_SEND" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 \"START_TIME\" [INCREMENTAL_GB]"
    echo "Example: $0 \"2025-09-18 11:45:00\" 219"
    exit 1
fi

# --- Pool Detection & Validation ---
SOURCE_POOL="naspool"
TARGET_POOL=$(zpool list -H -o name | grep -m1 "naspool_backup")

if ! zpool list | grep -q "$SOURCE_POOL"; then
    echo "Error: Source pool '$SOURCE_POOL' is offline."
    exit 1
fi
if ! zpool list | grep -q "$TARGET_POOL"; then
    echo "Error: Target pool '$TARGET_POOL' is offline."
    exit 1
fi

# --- Time Calculation ---
START_TIME=$(date -d "$START_TIME_STR" +%s)
CURRENT_TIME=$(date +%s)
ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
if (( ELAPSED_TIME < 1 )); then ELAPSED_TIME=1; fi # Avoid division by zero

# Convert incremental GB to bytes for calculations
INCREMENTAL_BYTES_TO_SEND=$(awk "BEGIN {printf \"%.0f\", $INCREMENTAL_GB_TO_SEND * 1024 * 1024 * 1024}")

# --- Helper Functions ---
format_time() {
    local SECONDS=$(printf "%.0f" "$1")
    local H=$((SECONDS / 3600))
    local M=$(((SECONDS % 3600) / 60))
    local S=$((SECONDS % 60))
    printf "%02dh:%02dm:%02ds" $H $M $S
}

format_bytes() {
    local RAW="$1"
    local CLEAN=$(printf "%.0f" "$RAW")
    numfmt --to=iec --suffix=B "$CLEAN"
}

get_dataset_info() {
    zfs list -p -H -r -o name,used,available "$1" | sort
}

# --- Data Collection ---
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

# Calculate total remaining bytes across all datasets (source - target)
total_remaining_bytes=0

for name in "${TARGET_NAMES[@]}"; do
    # Skip top-level pool to avoid double-counting
    if [ "$name" == "$TARGET_POOL" ]; then
        continue
    fi
    src_name="${name/$TARGET_POOL/$SOURCE_POOL}"
    src_used=${SOURCE_USED["$src_name"]}
    tgt_used=${TARGET_USED["$name"]}

    if [ -n "$src_used" ] && [ "$src_used" -gt 0 ]; then
        dataset_remaining=$((src_used - tgt_used))
        if (( dataset_remaining > 0 )); then
            total_remaining_bytes=$((total_remaining_bytes + dataset_remaining))
        fi
    fi
done

# Convert remaining bytes to GB
remaining_gb=$(awk "BEGIN {printf \"%.2f\", $total_remaining_bytes / (1024 * 1024 * 1024)}")

# Calculate how much of the incremental has been transferred
gb_transferred=$(awk "BEGIN {printf \"%.2f\", $INCREMENTAL_GB_TO_SEND - $remaining_gb}")

# Calculate transfer rate based on data actually transferred
transfer_rate_gb_per_sec=$(awk "BEGIN {printf \"%.6f\", $gb_transferred / $ELAPSED_TIME}")
transfer_rate_gb_per_min=$(awk "BEGIN {printf \"%.3f\", $transfer_rate_gb_per_sec * 60}")

# Estimate time remaining using incremental-based rate
est_time_remaining=0
if (( $(awk 'BEGIN {print ('$transfer_rate_gb_per_sec' > 0)}') )); then
    est_time_remaining=$(awk "BEGIN {printf \"%.0f\", $remaining_gb / $transfer_rate_gb_per_sec}")
fi

# Calculate overall completion percentage based on incremental size
overall_percent=$(awk "BEGIN {printf \"%.2f\", ($gb_transferred / $INCREMENTAL_GB_TO_SEND) * 100}")

elapsed_fmt=$(format_time "$ELAPSED_TIME")
est_time_fmt=$(format_time "$est_time_remaining")

# --- Output ---
echo ""
echo "## ZFS Incremental Send Progress"
echo "- Elapsed Time: $elapsed_fmt"
echo "- Transfer Rate: $(printf "%.3f" $transfer_rate_gb_per_min) GB/min ($(printf "%.2f" $transfer_rate_gb_per_sec) GB/s)"
echo "- Data Transferred: ${gb_transferred} GB / ${INCREMENTAL_GB_TO_SEND} GB"
echo "- Overall Completion: $overall_percent%"
echo "- Estimated Time Remaining: $est_time_fmt"
echo "- Remaining Data: $(printf "%.2f" $remaining_gb) GB"
echo ""

echo "## Source Pool: $SOURCE_POOL"
printf "%-26s %10s %10s\n" "NAME" "USED" "AVAIL"
for name in "${SOURCE_NAMES[@]}"; do
    printf "%-26s %10s %10s\n" "$name" "$(format_bytes ${SOURCE_USED[$name]})" "$(format_bytes ${SOURCE_AVAIL[$name]})"
done

echo ""
echo "## Target Pool: $TARGET_POOL"
printf "%-26s %10s %10s %7s %15s %10s\n" "NAME" "USED" "AVAIL" "PERC" "EST TIME" "REMAINING"

for name in "${TARGET_NAMES[@]}"; do
    src_name="${name/$TARGET_POOL/$SOURCE_POOL}"
    src_used=${SOURCE_USED["$src_name"]}
    tgt_used=${TARGET_USED["$name"]}

    if [ -n "$src_used" ] && [ "$src_used" -gt 0 ]; then
        # For individual datasets, calculate percentage based on their actual size difference
        percent=$(awk "BEGIN {printf \"%.2f\", ($tgt_used / $src_used) * 100}")
        remaining_bytes=$((src_used - tgt_used))
        
        # Per-dataset ETR calculation using the global transfer rate
        est_time_fmt="--:--:--"
        if (( $(awk 'BEGIN {print ('$transfer_rate_gb_per_sec' > 0)}') )); then
            dataset_remaining_gb=$(awk "BEGIN {printf \"%.2f\", $remaining_bytes / (1024 * 1024 * 1024)}")
            dataset_est_time=$(awk "BEGIN {printf \"%.0f\", $dataset_remaining_gb / $transfer_rate_gb_per_sec}")
            est_time_fmt="$(format_time "$dataset_est_time")"
        fi

        # Use overall ETR for the top-level pool row (based on incremental calculation)
        if [ "$name" == "$TARGET_POOL" ]; then
            est_time_fmt="$est_time_fmt"
            percent="$overall_percent"
            remaining_bytes=$(awk "BEGIN {printf \"%.0f\", $remaining_gb * 1024 * 1024 * 1024}")
        fi

        printf "%-26s %10s %10s %6s%% %15s %10s\n" \
            "$name" \
            "$(format_bytes $tgt_used)" \
            "$(format_bytes ${TARGET_AVAIL[$name]})" \
            "$percent" \
            "$est_time_fmt" \
            "$(format_bytes $remaining_bytes)"
    else
        printf "%-26s %10s %10s %7s %15s %10s\n" \
            "$name" \
            "$(format_bytes $tgt_used)" \
            "$(format_bytes ${TARGET_AVAIL[$name]})" \
            "N/A" "N/A" "N/A"
    fi
done