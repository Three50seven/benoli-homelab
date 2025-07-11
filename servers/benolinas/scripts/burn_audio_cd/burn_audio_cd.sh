#!/bin/bash

# --- Configuration ---
ALBUM_TITLE="Munchkin & Littles 2"
ALBUM_PERFORMER="Various Artists"
MP3_SOURCE_DIR="/opt/disc-burn/benolijamz-d2"
OUTPUT_DIR="/opt/disc-burn/audio_cd_project"
CD_BURNER_DEVICE="/dev/sr0"

# --- Script Variables ---
MASTER_WAV_FILE="${OUTPUT_DIR}/audio_cd_master.wav"
CUE_FILE="${OUTPUT_DIR}/audio_cd.cue"
TEMP_WAV_DIR="${OUTPUT_DIR}/temp_wavs"

# --- Function to convert total frames to MM:SS:FF format ---
frames_to_mmssff() {
    local total_frames=$1
    local minutes=$(( total_frames / (60 * 75) ))
    local remaining_frames=$(( total_frames % (60 * 75) ))
    local seconds=$(( remaining_frames / 75 ))
    local frames=$(( remaining_frames % 75 ))
    printf "%02d:%02d:%02d" "$minutes" "$seconds" "$frames"
}

echo "--- Audio CD Creation from MP3s ---"

# --- Tool Check ---
for cmd in sox mid3v2 wodim; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Command '$cmd' not found. Please install it."
        echo "  For sox: sudo apt install sox libsox-fmt-mp3"
        echo "  For mid3v2: sudo apt install python3-mutagen"
        echo "  For wodim: sudo apt install wodim"
        exit 1
    fi
done

# --- Directory Prep ---
echo "Preparing directories..."
mkdir -p "$TEMP_WAV_DIR" || { echo "ERROR: Cannot create '$TEMP_WAV_DIR'."; exit 1; }
rm -f "$TEMP_WAV_DIR"/*.wav "$MASTER_WAV_FILE" "$CUE_FILE"

# --- Gather MP3s ---
readarray -t MP3_FILES < <(find "$MP3_SOURCE_DIR" -maxdepth 1 -type f -name "*.mp3" | sort -V)
if [ ${#MP3_FILES[@]} -eq 0 ]; then
    echo "ERROR: No MP3 files found in '$MP3_SOURCE_DIR'."
    exit 1
fi
echo "Found ${#MP3_FILES[@]} MP3 files. Processing..."

# --- Cue Sheet Header ---
CUE_CONTENT="REM GENRE \"Audio CD\"\n"
CUE_CONTENT+="PERFORMER \"${ALBUM_PERFORMER:-Unknown Artist}\"\n"
CUE_CONTENT+="TITLE \"${ALBUM_TITLE:-Audio CD}\"\n"

# --- MP3 Tag Extractor ---
get_mp3_tag() {
    local mp3_path="$1"
    local tag_type="$2"
    case "$tag_type" in
        "Artist") grep_pattern="Artist:|TPE1=|TPE2=" ;;
        "Title") grep_pattern="Title:|TIT2=" ;;
        "Album") grep_pattern="Album:|TALB=" ;;
        *) grep_pattern="${tag_type}:|${tag_type^^}=" ;;
    esac
    local raw_output
    raw_output=$(mid3v2 -l "$mp3_path" 2>/dev/null | grep -E "$grep_pattern" | head -n 1)
    local extracted_value
    if [[ "$raw_output" == *":"* ]]; then
        extracted_value=$(echo "$raw_output" | cut -d: -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    elif [[ "$raw_output" == *"="* ]]; then
        extracted_value=$(echo "$raw_output" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    else
        extracted_value=""
    fi
    echo "$extracted_value"
}

# --- Convert MP3s to WAVs + Collect Track Info ---
TRACK_NUMBER=0
TRACK_DATA=()
echo "Converting MP3s to WAVs..."
for mp3_path in "${MP3_FILES[@]}"; do
    TRACK_NUMBER=$((TRACK_NUMBER + 1))
    TEMP_WAV_PATH="${TEMP_WAV_DIR}/track$(printf "%02d" "$TRACK_NUMBER").wav"
    echo "  [$TRACK_NUMBER] Converting '$(basename "$mp3_path")'..."

    TRACK_TITLE=$(get_mp3_tag "$mp3_path" "Title")
    TRACK_ARTIST=$(get_mp3_tag "$mp3_path" "Artist")

    sox "$mp3_path" -c 2 -r 44100 -b 16 "$TEMP_WAV_PATH" norm -0.5 || {
        echo "ERROR: SoX failed for '$mp3_path'. Skipping."
        continue
    }

    TRACK_DURATION_SECONDS=$(soxi -D "$TEMP_WAV_PATH")
    if [[ -z "$TRACK_DURATION_SECONDS" || "$TRACK_DURATION_SECONDS" == "0.00" ]]; then
        echo "WARNING: Bad duration. Skipping '$TEMP_WAV_PATH'."
        continue
    fi

    TRACK_DATA+=("${TRACK_TITLE:-Untitled Track}|${TRACK_ARTIST:-Unknown Artist}|${TRACK_DURATION_SECONDS}")
    echo "    - Title: $TRACK_TITLE | Artist: $TRACK_ARTIST | Duration: ${TRACK_DURATION_SECONDS}s"
done

# --- Concatenate All WAVs ---
echo "Concatenating WAVs into master file..."
CONCAT_WAV_FILES=()
for i in $(seq 1 ${#TRACK_DATA[@]}); do
    CONCAT_WAV_FILES+=("${TEMP_WAV_DIR}/track$(printf "%02d" "$i").wav")
done
sox "${CONCAT_WAV_FILES[@]}" "$MASTER_WAV_FILE" || {
    echo "ERROR: Failed to create master WAV."
    exit 1
}

# --- Pad master WAV to nearest multiple of 588 samples (CDDA frame = 2352 bytes) ---
echo "Checking alignment of master WAV for CDDA..."

sample_count=$(soxi -s "$MASTER_WAV_FILE")
remainder=$(( sample_count % 588 ))

if (( remainder != 0 )); then
    pad_samples=$(( 588 - remainder ))
    pad_seconds=$(echo "scale=8; $pad_samples / 44100" | bc)
    pad_bytes=$(( pad_samples * 4 ))

    echo "Padding master WAV with $pad_samples samples ($pad_bytes bytes, $pad_seconds seconds) of silence..."

    if (( pad_samples > 0 )); then
        PAD_FILE="${OUTPUT_DIR}/audio_cd_pad.wav"

        # Use trim (time-based silence) for compatibility with older SoX
        sox -n -r 44100 -c 2 -b 16 "$PAD_FILE" trim 0.0 "$pad_seconds" || {
            echo "ERROR: Failed to create silence WAV for padding."
            exit 1
        }

        FINAL_WAV="${MASTER_WAV_FILE%.wav}_final.wav"
        sox --combine concatenate "$MASTER_WAV_FILE" "$PAD_FILE" "$FINAL_WAV" || {
            echo "ERROR: Failed to append silence to master WAV."
            rm -f "$PAD_FILE"
            exit 1
        }

        mv "$FINAL_WAV" "$MASTER_WAV_FILE"
        rm -f "$PAD_FILE"
        echo " Master WAV padded and aligned successfully."
    else
        echo "No padding needed (pad_samples = 0)"
    fi
else
    echo "Master WAV is already aligned to CDDA frame (588 samples)."
fi

echo "Master WAV created: $MASTER_WAV_FILE"
echo "Doing final safety checks on the Master WAV file..."

sample_count=$(soxi -s "$MASTER_WAV_FILE")

if (( sample_count % 588 != 0 )); then
    echo "WARNING: Master WAV is NOT aligned to a CDDA frame boundary! ($sample_count samples)"
    echo "         --> Resulting disc may fail to burn with cuefile."
    exit 1
else
    echo "Master WAV is properly aligned ($sample_count samples, multiple of 588)"
fi

# Why 588?
# A CDDA sector = 1 frame = 588 stereo samples
# Each sample = 4 bytes (2 bytes per channel)
# 588 x 4 = 2352 bytes (1 CDDA sector)

echo "Converting padded master WAV to raw PCM..."
RAW_PCM_FILE="${MASTER_WAV_FILE%.wav}.raw"

sox "$MASTER_WAV_FILE" -t raw "$RAW_PCM_FILE" || {
    echo "ERROR: Failed to export raw PCM."
    exit 1
}

byte_size=$(stat -c %s "$RAW_PCM_FILE")
if (( byte_size % 2352 != 0 )); then
    echo "RAW PCM file is not a multiple of 2352 bytes! ($byte_size bytes)"
    exit 1
else
    echo "RAW PCM file is aligned to CDDA sector size ($byte_size bytes)"
fi

echo "Generating Cue file..."

# --- Generate Cue Sheet ---
CUE_CONTENT+="FILE \"$(basename "$RAW_PCM_FILE")\" BINARY\n"
CURRENT_CUMULATIVE_FRAMES=0
TRACK_NUMBER=0

for i in "${!TRACK_DATA[@]}"; do
    TRACK_NUMBER=$((i + 1))
    IFS='|' read -r TITLE ARTIST DURATION_SECONDS <<< "${TRACK_DATA[$i]}"
    DURATION_FRAMES=$(printf "%.0f" "$(echo "$DURATION_SECONDS * 75" | bc -l)")

    # --- Round up final track to nearest multiple of 2352 bytes ---
    if (( TRACK_NUMBER == ${#TRACK_DATA[@]} )); then
        duration_bytes=$(( DURATION_FRAMES * 2352 ))
        remainder=$(( duration_bytes % 2352 ))
        if (( remainder != 0 )); then
            pad_frames=$(( (2352 - remainder) / 2352 ))
            echo "NOTE: Padding last track with $pad_frames frames of silence"
            DURATION_FRAMES=$(( DURATION_FRAMES + pad_frames ))
        fi
    fi

    INDEX_TIME=$(frames_to_mmssff "$CURRENT_CUMULATIVE_FRAMES")

    CUE_CONTENT+="  TRACK $(printf "%02d" "$TRACK_NUMBER") AUDIO\n"
    CUE_CONTENT+="    TITLE \"$TITLE\"\n"
    CUE_CONTENT+="    PERFORMER \"$ARTIST\"\n"
    CUE_CONTENT+="    INDEX 01 $INDEX_TIME\n"

    CURRENT_CUMULATIVE_FRAMES=$(( CURRENT_CUMULATIVE_FRAMES + DURATION_FRAMES ))
done

echo -e "$CUE_CONTENT" > "$CUE_FILE" || {
    echo "ERROR: Failed to write CUE file."
    exit 1
}
echo "CUE sheet created: $CUE_FILE"

echo
echo "----- CD Capacity Check -----"

sample_count=$(soxi -s "$MASTER_WAV_FILE")
total_frames=$(( sample_count / 588 ))
max_frames=333000

echo "Total audio frames (CDDA): $total_frames"
echo "Maximum frames for 80min CD: $max_frames"

if (( total_frames > max_frames )); then
    frames_over=$(( total_frames - max_frames ))
    seconds_over=$(echo "$frames_over / 75" | bc -l)
    minutes_over=$(echo "scale=2; $seconds_over / 60" | bc -l)

    echo "WARNING: This disc is over capacity by $frames_over frames (~${minutes_over} minutes)."
    echo "You need to trim approximately ${minutes_over} minutes of audio to fit on a standard 80-minute CD."
    echo "  (Or use -overburn if your drive supports it, but it may be unreliable.)"
    echo

    read -rp "Press Enter to continue anyway, or Ctrl+C to cancel and adjust track list..."
else
    echo "Audio fits within standard CD capacity."
    echo
fi

# --- Burn CD ---
echo "--- Ready to Burn ---"
echo "Insert a blank CD into '$CD_BURNER_DEVICE'."
read -rp "Press Enter to continue, or Ctrl+C to cancel...."

if mountpoint -q "$CD_BURNER_DEVICE"; then
    echo "Unmounting '$CD_BURNER_DEVICE'..."
    umount "$CD_BURNER_DEVICE" || echo "WARNING: Could not unmount, proceeding anyway."
fi

echo "Burning disc..."
wodim dev="$CD_BURNER_DEVICE" -v -dao -cuefile "$CUE_FILE" || {
    echo "ERROR: wodim burning failed. Check output above for details."
    echo "Possible issues: incorrect device, no blank disc, permissions, or drive errors."
    exit 1
}
echo "Audio CD burn complete!"

# --- Cleanup ---
echo "Cleaning up temporary files..."
rm -rf "$TEMP_WAV_DIR"
# Uncomment the next line if you also want to delete the master WAV
# rm -f "$MASTER_WAV_FILE"
echo "Done."

echo "--- Script Finished ---"
