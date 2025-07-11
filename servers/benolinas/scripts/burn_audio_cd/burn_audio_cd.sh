#!/bin/bash

# --- Configuration ---
# IMPORTANT: Edit these paths to match your setup
ALBUM_TITLE="Munchkin & Littles 2"         # Set the Album Variable manually here, or otherwise comment this out and uncomment the line below to derive from MP3 files
MP3_SOURCE_DIR="/opt/disc-burn/benolijamz-d2"        # Directory containing your MP3 files
OUTPUT_DIR="/opt/disc-burn/audio_cd_project" # Working directory for WAVs and CUE sheet
CD_BURNER_DEVICE="/dev/sr0"                # Your CD/DVD burner device (e.g., /dev/sr0, /dev/cdrom)
                                           # Find this using 'sudo wodim --devices'

# --- Script Variables (do not edit unless you know what you're doing) ---
MASTER_WAV_FILE="${OUTPUT_DIR}/audio_cd_master.wav"
CUE_FILE="${OUTPUT_DIR}/audio_cd.cue"
TEMP_WAV_DIR="${OUTPUT_DIR}/temp_wavs"

# --- Function to convert seconds to MM:SS:FF format for CUE sheet ---
# MM:SS:FF (Minutes:Seconds:Frames) where FF is 1/75th of a second
sec_to_mmssff() {
    local total_seconds_float=$1
    local minutes=$(printf "%.0f" "$(echo "$total_seconds_float / 60" | bc -l)")
    local remaining_seconds_float=$(echo "$total_seconds_float - ($minutes * 60)" | bc -l)
    local seconds=$(printf "%.0f" "$(echo "$remaining_seconds_float" | bc -l)")
    local fractional_seconds=$(echo "$remaining_seconds_float - $seconds" | bc -l)
    local frames=$(printf "%.0f" "$(echo "$fractional_seconds * 75" | bc -l)")

    # Ensure two digits for seconds and frames, three for minutes (though usually less)
    printf "%02d:%02d:%02d" "$minutes" "$seconds" "$frames"
}

# --- Main Script ---

echo "--- Audio CD Creation from MP3s ---"

# 1. Check for necessary tools
for cmd in sox mid3v2 wodim; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Command '$cmd' not found. Please install it."
        echo "  For sox: sudo apt install sox libsox-fmt-mp3"
        echo "  For mid3v2: sudo apt install python3-mutagen"
        echo "  For wodim: sudo apt install wodim"
        exit 1
    fi
done

# 2. Create and prepare output directories
echo "Preparing directories..."
mkdir -p "$TEMP_WAV_DIR" || { echo "ERROR: Could not create '$TEMP_WAV_DIR'."; exit 1; }
rm -f "$TEMP_WAV_DIR"/*.wav # Clear temporary WAVs
rm -f "$MASTER_WAV_FILE"    # Clear master WAV
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

echo "Found ${#MP3_FILES[@]} MP3 files. Processing..."

# Initialize CUE sheet content and track data
CUE_CONTENT=""
TRACK_DATA=() # Array to store track info: "Title|Artist|Duration"
CURRENT_CUMULATIVE_SECONDS=0.0

# Extract album-level metadata from the first MP3 (assuming consistent tagging)
# ALBUM_TITLE=$(mid3v2 -l "${MP3_FILES[0]}" | grep "Album:" | cut -d: -f2- | xargs) # Uncomment to get album from MP3 files, otherwise use initial variable above
ALBUM_PERFORMER=$(mid3v2 -l "${MP3_FILES[0]}" | grep "Artist:" | cut -d: -f2- | xargs)

# Add album-level metadata to CUE sheet
CUE_CONTENT+="REM GENRE \"Audio CD\"\n" # You can customize genre if needed
CUE_CONTENT+="PERFORMER \"${ALBUM_PERFORMER:-Unknown Artist}\"\n"
CUE_CONTENT+="TITLE \"${ALBUM_TITLE:-Audio CD}\"\n"

# 4. Convert each MP3 to a temporary WAV and gather track info
TRACK_NUMBER=0
for mp3_path in "${MP3_FILES[@]}"; do
    TRACK_NUMBER=$((TRACK_NUMBER + 1))
    TEMP_WAV_PATH="${TEMP_WAV_DIR}/track$(printf "%02d" "$TRACK_NUMBER").wav"

    echo "  Converting track $TRACK_NUMBER: '$(basename "$mp3_path")'..."

    # Extract track-specific metadata
    TRACK_TITLE=$(mid3v2 -l "$mp3_path" | grep "Title:" | cut -d: -f2- | xargs)
    TRACK_ARTIST=$(mid3v2 -l "$mp3_path" | grep "Artist:" | cut -d: -f2- | xargs)

    # Convert MP3 to WAV (CD-Audio format) with normalization
    # norm -0.5: Normalizes peak volume to -0.5 dB to prevent clipping
    sox "$mp3_path" -c 2 -r 44100 -b 16 "$TEMP_WAV_PATH" norm -0.5 || {
        echo "ERROR: SoX conversion failed for '$mp3_path'. Skipping."
        continue # Skip to next MP3 if conversion fails
    }

    # Get duration of the converted WAV in seconds (float)
    TRACK_DURATION_SECONDS=$(soxi -D "$TEMP_WAV_PATH")

    # Store track data for CUE sheet generation later
    TRACK_DATA+=("${TRACK_TITLE:-Untitled Track}|${TRACK_ARTIST:-Unknown Artist}|${TRACK_DURATION_SECONDS}")

    echo "  Converted. Duration: $(printf "%.2f" "$TRACK_DURATION_SECONDS") seconds."
done

# 5. Concatenate all temporary WAVs into one master WAV file
echo "Concatenating WAV files into master: '$MASTER_WAV_FILE'..."
# Create an array of WAV files in sorted order for concatenation
CONCAT_WAV_FILES=()
for i in $(seq 1 ${#MP3_FILES[@]}); do
    CONCAT_WAV_FILES+=("${TEMP_WAV_DIR}/track$(printf "%02d" "$i").wav")
done

# Use sox to concatenate
sox "${CONCAT_WAV_FILES[@]}" "$MASTER_WAV_FILE" || {
    echo "ERROR: Failed to concatenate WAV files. Exiting."
    exit 1
}
echo "Concatenation complete."

# 6. Generate the CUE sheet content
CUE_CONTENT+="FILE \"$(basename "$MASTER_WAV_FILE")\" WAVE\n"

TRACK_NUMBER=0
for track_info in "${TRACK_DATA[@]}"; do
    TRACK_NUMBER=$((TRACK_NUMBER + 1))
    IFS='|' read -r TITLE ARTIST DURATION <<< "$track_info"

    # Convert cumulative seconds to MM:SS:FF for INDEX 01
    START_TIME_MMSSFF=$(sec_to_mmssff "$CURRENT_CUMULATIVE_SECONDS")

    CUE_CONTENT+="  TRACK $(printf "%02d" "$TRACK_NUMBER") AUDIO\n"
    CUE_CONTENT+="    TITLE \"$TITLE\"\n"
    CUE_CONTENT+="    PERFORMER \"$ARTIST\"\n"
    CUE_CONTENT+="    INDEX 01 $START_TIME_MMSSFF\n"

    # Update cumulative time for the next track
    CURRENT_CUMULATIVE_SECONDS=$(echo "$CURRENT_CUMULATIVE_SECONDS + $DURATION" | bc -l)
done

# 7. Write the CUE sheet file
echo -e "$CUE_CONTENT" > "$CUE_FILE" || { echo "ERROR: Failed to write CUE file."; exit 1; }
echo "CUE sheet generated: '$CUE_FILE'"

# 8. Burn the Audio CD using wodim and the CUE sheet
echo "--- Burning Audio CD ---"
echo "Please insert a blank CD-R into the drive '$CD_BURNER_DEVICE'."
echo "Press Enter to continue, or Ctrl+C to cancel."
read -r

# Unmount the CD-ROM device if it's mounted
if mountpoint -q "$CD_BURNER_DEVICE"; then
    echo "Unmounting '$CD_BURNER_DEVICE'..."
    sudo umount "$CD_BURNER_DEVICE" || { echo "WARNING: Could not unmount '$CD_BURNER_DEVICE'. Attempting to proceed anyway."; }
fi

echo "Starting burn process..."
# -v: verbose
# -dao: Disc At Once (recommended for audio CDs with CUE sheets)
# -pad: Pads audio data to ensure correct length
# -cuefile: Specifies the CUE sheet to use
# The master WAV file is implicitly burned as referenced in the CUE sheet
sudo wodim dev="$CD_BURNER_DEVICE" -v -dao -pad -cuefile "$CUE_FILE" || {
    echo "ERROR: wodim burning failed. Check output above for details."
    echo "Possible issues: incorrect device, no blank disc, permissions, or drive errors."
    exit 1
}

echo "Audio CD burning complete!"

# 9. Clean up temporary WAV files
echo "Cleaning up temporary files..."
rm -rf "$TEMP_WAV_DIR"
# rm -f "$MASTER_WAV_FILE" # Keep master WAV if you want to re-burn or archive
echo "Cleanup complete."

echo "--- Script Finished ---"
```