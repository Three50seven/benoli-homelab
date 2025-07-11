#!/bin/bash

# NOTE: This script does not include all the steps of generating wav files and padding the final master file like burn_audio_cd.sh script does, but it should be a good test of the steps involved.
# --- Configuration ---
# IMPORTANT: Edit these paths to match your setup
ALBUM_TITLE="Munchkin & Littles 2"         # Set the Album Variable manually here, or otherwise comment this out and uncomment the line below to derive from MP3 files
ALBUM_PERFORMER="Various Artists"          # Similarly do the same for ALBUM_PERFORMER
MP3_SOURCE_DIR="/opt/disc-burn/benolijamz-d2"        # Directory containing your MP3 files
OUTPUT_DIR="/opt/disc-burn/audio_cd_project" # Working directory for CUE sheet

# --- Script Variables (do not edit unless you know what you're doing) ---
CUE_FILE="${OUTPUT_DIR}/audio_cd.cue"

# --- Function to convert total frames to MM:SS:FF format for CUE sheet ---
# MM:SS:FF (Minutes:Seconds:Frames) where FF is 1/75th of a second
# This function now takes total frames as input, ensuring integer arithmetic throughout
frames_to_mmssff() {
    local total_frames=$1

    local minutes=$(( total_frames / (60 * 75) ))
    local remaining_frames_after_minutes=$(( total_frames % (60 * 75) ))
    local seconds=$(( remaining_frames_after_minutes / 75 ))
    local frames=$(( remaining_frames_after_minutes % 75 ))

    # Ensure two digits for seconds and frames, three for minutes (though usually less)
    printf "%02d:%02d:%02d" "$minutes" "$seconds" "$frames"
}

# --- Main Script ---

echo "--- Audio CD Cue File Creation from MP3s ---"

# 1. Check for necessary tools
for cmd in mid3v2; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Command '$cmd' not found. Please install it."
        echo "  For mid3v2: apt install python3-mutagen"
        exit 1
    fi
done

# 2. Create and prepare output directories
echo "Preparing directories..."
rm -f "$CUE_FILE"           # Clear old CUE sheet

# 3. Get sorted list of MP3 files
# Using 'find' for robustness with spaces and subdirectories, then 'sort'
# 'sort -V' for natural (version) sorting, so 1, 2, 10, 11 instead of 1, 10, 11, 2
# 'readarray' requires Bash 4+
readarray -t MP3_FILES < <(find "$MP3_SOURCE_DIR" -maxdepth 1 -type f -name "*.mp3" | sort -V)

if [ ${#MP3_FILES[@]} -eq 0 ]; then
    echo "ERROR: No MP3 files found in '$MP3_SOURCE_DIR'. Exiting."
    exit 1
fi

echo "Found ${#MP3_FILES[@]} MP3 files. Processing Cue File..."

# Initialize CUE sheet content and track data
CUE_CONTENT=""
TRACK_DATA=() # Array to store track info: "Title|Artist|Duration"
CURRENT_CUMULATIVE_FRAMES=0 # Accumulate total time in frames

# --- Robust Metadata Extraction Function ---
# This function takes the MP3 path and the tag type (e.g., "Title", "Artist", "Album")
# It tries to extract the tag robustly and trims whitespace.
get_mp3_tag() {
    local mp3_path="$1"
    local tag_type="$2"
    local grep_pattern
    local raw_output

    # Determine the grep pattern based on tag_type for more specific matching
    case "$tag_type" in
        "Artist")
            grep_pattern="Artist:|TPE1=|TPE2=" # Include TPE1 and TPE2 for artist
            ;;
        "Title")
            grep_pattern="Title:|TIT2="
            ;;
        "Album")
            grep_pattern="Album:|TALB="
            ;;
        *)
            grep_pattern="${tag_type}:|${tag_type^^}=" # Default for other tags
            ;;
    esac

    # Use mid3v2 -l and grep for common patterns, then sed to extract and trim
    # This handles both "Tag: Value" and "TAG=Value" formats and trims whitespace
    raw_output=$(mid3v2 -l "$mp3_path" 2>/dev/null | grep -E "$grep_pattern" | head -n 1)

    # Extract value after colon or equals, then trim leading/trailing whitespace
    local extracted_value
    if [[ "$raw_output" == *":"* ]]; then
        extracted_value=$(echo "$raw_output" | cut -d: -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    elif [[ "$raw_output" == *"="* ]]; then
        extracted_value=$(echo "$raw_output" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    else
        extracted_value="" # No match found
    fi

    echo "$extracted_value"
}

# Extract album-level metadata from the first MP3 (assuming consistent tagging)
# Uncomment the next lines to get album from MP3 files, otherwise use initial variable above
#ALBUM_TITLE=$(get_mp3_tag "${MP3_FILES[0]}" "Album")
#ALBUM_PERFORMER=$(get_mp3_tag "${MP3_FILES[0]}" "Artist") # Often Album Artist is same as Artist

# Add album-level metadata to CUE sheet
CUE_CONTENT+="REM GENRE \"Audio CD\"\n" # You can customize genre if needed
CUE_CONTENT+="PERFORMER \"${ALBUM_PERFORMER:-Unknown Artist}\"\n"
CUE_CONTENT+="TITLE \"${ALBUM_TITLE:-Audio CD}\"\n"

# 4. Gather track info for each MP3
TRACK_NUMBER=0
for mp3_path in "${MP3_FILES[@]}"; do
    TRACK_NUMBER=$((TRACK_NUMBER + 1))

    echo "  Converting track $TRACK_NUMBER: '$(basename "$mp3_path")'..."

    # Extract track-specific metadata using the robust function
    TRACK_TITLE=$(get_mp3_tag "$mp3_path" "Title")
    TRACK_ARTIST=$(get_mp3_tag "$mp3_path" "Artist")

    # Get duration of the MP3 in seconds (float)
    TRACK_DURATION_SECONDS=$(soxi -D "$mp3_path")
    echo "DEBUG: Raw TRACK_DURATION_SECONDS for $(basename "$mp3_path"): $TRACK_DURATION_SECONDS" # DEBUG

    # Validate TRACK_DURATION_SECONDS and ensure it's a positive number for calculations
    if [[ -z "$TRACK_DURATION_SECONDS" || "$(echo "$TRACK_DURATION_SECONDS <= 0" | bc -l)" -eq 1 ]]; then
        echo "WARNING: SoX returned invalid or zero duration for '$mp3_path'. Defaulting to 4.0 seconds (300 frames)."
        TRACK_DURATION_SECONDS="4.0" # Default to a valid minimum duration for CDDA
    fi

    # Convert track duration to frames for integer-based accumulation
    # Add 0.5 for proper rounding before truncation by printf
    TRACK_DURATION_FRAMES_FLOAT=$(echo "($TRACK_DURATION_SECONDS * 75) + 0.5" | bc -l)
    TRACK_DURATION_FRAMES=$(printf "%.0f" "$TRACK_DURATION_FRAMES_FLOAT")

    # Ensure TRACK_DURATION_FRAMES is at least 1, to prevent zero-length tracks in CUE
    if (( TRACK_DURATION_FRAMES < 1 )); then
        TRACK_DURATION_FRAMES=1
    fi
    echo "DEBUG: Calculated TRACK_DURATION_FRAMES for $(basename "$mp3_path"): $TRACK_DURATION_FRAMES" # DEBUG

    # Store track data for CUE sheet generation later
    TRACK_DATA+=("${TRACK_TITLE:-Untitled Track}|${TRACK_ARTIST:-Unknown Artist}|${TRACK_DURATION_FRAMES}")

    echo "  MP3 Metadata Retrieved. Duration: $(printf "%.2f" "$TRACK_DURATION_SECONDS") seconds. Track Title: $TRACK_TITLE. Track Artist: $TRACK_ARTIST."
done

# 5. Generate the CUE sheet content
CUE_CONTENT+="FILE \"test_cue_file.wav\" WAVE\n"

TRACK_NUMBER=0
for track_info in "${TRACK_DATA[@]}"; do
    TRACK_NUMBER=$((TRACK_NUMBER + 1))
    IFS='|' read -r TITLE ARTIST DURATION_FRAMES <<< "$track_info" # Read duration as frames

    echo "DEBUG in loop: Track $TRACK_NUMBER - DURATION_FRAMES (read from array): '$DURATION_FRAMES'" # DEBUG
    echo "DEBUG in loop: Track $TRACK_NUMBER - CURRENT_CUMULATIVE_FRAMES before adding: '$CURRENT_CUMULATIVE_FRAMES'" # DEBUG

    # Convert cumulative frames to MM:SS:FF for INDEX 01
    START_TIME_MMSSFF=$(frames_to_mmssff "$CURRENT_CUMULATIVE_FRAMES")

    CUE_CONTENT+="  TRACK $(printf "%02d" "$TRACK_NUMBER") AUDIO\n"
    CUE_CONTENT+="    TITLE \"$TITLE\"\n"
    CUE_CONTENT+="    PERFORMER \"$ARTIST\"\n"
    CUE_CONTENT+="    INDEX 01 $START_TIME_MMSSFF\n"

    # Update cumulative time for the next track, adding frames
    CURRENT_CUMULATIVE_FRAMES=$((CURRENT_CUMULATIVE_FRAMES + DURATION_FRAMES))
done

# 7. Write the CUE sheet file
echo -e "$CUE_CONTENT" > "$CUE_FILE" || { echo "ERROR: Failed to write CUE file."; exit 1; }
echo "Audio CD CUE sheet generated: '$CUE_FILE'"

echo "--- Script Finished ---"