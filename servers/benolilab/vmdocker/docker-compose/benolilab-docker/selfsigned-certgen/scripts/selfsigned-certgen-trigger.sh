#!/bin/bash

# ========== CONFIG ==========
KEY_NAME="${KEY_NAME:-mylab}" # Second level domain (SLD) e.g. mylab portion of mylab.home
CA_TLD="${CA_TLD:-home}" # Top level domain (TLD) e.g. home portion of mylab.home
CA_ALT_NAME="${CA_ALT_NAME:-svc}" # Alternate name used in DNS SANs, e.g. svc.mylab.home and *.svc.mylab.home
ROOT_CA_NAME="${ROOT_CA_NAME:-mylab-rootCA}"
COUNTRY="${COUNTRY:-US}"
STATE="${STATE:-StateName}"
CITY="${CITY:-CityName}"
ORG="${ORG:-OrgName}"
KEY_SIZE="${KEY_SIZE:-4096}"
DAYS_CA="${DAYS_CA:-1825}" # Default to ~5 years
DAYS_CERT="${DAYS_CERT:-731}" # Default to ~2yrs + 1 day
ARCHIVE_DIR="${ARCHIVE_DIR:-/archive}"
CERT_RENEWAL_THRESHOLD_DAYS="${CERT_RENEWAL_THRESHOLD_DAYS-30}" # Number of days before cert is renewed e.g. once the cert is <= threshold, renew the cert.
DATESTAMP=$(date +%Y%m%d)

CERT_FILES=("${KEY_NAME}.key" "${KEY_NAME}.csr" "${KEY_NAME}.crt" "extfile.cnf")
NEW_ROOT_GENERATED=false

# Attempt to Read webhook URL from the file specified in the variable
if [[ -f "$NOTIFICATION_URLS_FILE" ]]; then
    DISCORD_WEBHOOK_URL=$(awk 'NR==1' "$NOTIFICATION_URLS_FILE")
else
    log_message "Error: Notifications Webhook file not found!"
    exit 1
fi

LOG_DATE_FORMAT=${LOG_DATE_FORMAT:-"%Y-%m-%dT%H:%M:%S%z"}  # Default to ISO 8601

# Validate LOG_DATE_FORMAT (must contain recognized format specifiers)
if ! date +"$LOG_DATE_FORMAT" &>/dev/null; then
    log_message "Warning: Invalid LOG_DATE_FORMAT detected. Falling back to ISO 8601."
    LOG_DATE_FORMAT="%Y-%m-%dT%H:%M:%S%z"
fi

# Change to correct working directory for certificate generation
cd /certs || { echo "Failed to switch to /certs"; exit 1; }

# ========== SANITY CHECKS ==========

# Set floor and bounds
MIN_DAYS_CERT=30
MAX_DAYS_CERT=3980
MIN_DAYS_CA=365
MAX_DAYS_CA=7300

# Clamp DAYS_CERT
if (( DAYS_CERT < MIN_DAYS_CERT || DAYS_CERT > MAX_DAYS_CERT )); then
  log_message ":warning: DAYS_CERT out of bounds. Resetting to 731."
  DAYS_CERT=731
fi

# Clamp DAYS_CA
if (( DAYS_CA < MIN_DAYS_CA || DAYS_CA > MAX_DAYS_CA )); then
  log_message ":warning: DAYS_CA out of bounds. Resetting to 1825."
  DAYS_CA=1825
fi

# Set CERT_RENEWAL_THRESHOLD_DAYS to be at least 4% of DAYS_CERT
min_threshold=$(awk "BEGIN { printf \"%d\", $DAYS_CERT * 0.04 }")
if (( CERT_RENEWAL_THRESHOLD_DAYS < min_threshold )); then
  log_message ":warning: CERT_RENEWAL_THRESHOLD_DAYS too low. Setting to minimum safe value: $min_threshold"
  CERT_RENEWAL_THRESHOLD_DAYS=$min_threshold
fi

# ========== FUNCTIONS ==========

# Function to log messages
log_message() {
    local message="$1"
    local timestamped_msg="$(date +"$LOG_DATE_FORMAT") - $message"

    # Echo to stdout
    echo -e "$timestamped_msg"
}

# Function to send a Discord notification - note this will also log the message, so no need to call both the log and send functions
# Note: when adding any new markdown (used by Discord), make sure it's replaced in the function for cleaner logging
send_discord_notification() {
    local message=$1

    # Convert markdown symbols to plain text for logging
    local markdown_replaced_message=$(echo "$message" | sed -e 's/:x:/Error:/g' \
                                                   -e 's/\*\*//g' \
                                                   -e 's/:warning:/Warning:/g' \
                                                   -e 's/:white_check_mark:/Info:/g' \
                                                   -e 's/__//g' \
                                                   -e 's/:test_tube:/Test:/g')
    log_message "$markdown_replaced_message" # Log cleaned message

    # Dynamically determine embed color based on the message content
    local message_color=16777215 # Default: White
    if echo "$markdown_replaced_message" | grep -q "Error[:.!?-]*"; then
        message_color=16711680 # Red
    elif echo "$markdown_replaced_message" | grep -q "Warning[:.!?-]*"; then
        message_color=16776960 # Yellow
    elif echo "$markdown_replaced_message" | grep -iq "Test[:.!?-]*"; then
        message_color=2003199 # Blue
    elif echo "$markdown_replaced_message" | grep -Eiq "Success|Successfully|Succeeded"; then
    message_color=65280 # Green
    fi

    # Extract bold title (text inside the first set of bold markdown **...**)
    local message_title=$(echo "$message" | grep -o '\*\*[^*]*\*\*' | sed 's/\*\*//g')

    # Construct JSON payload for Discord webhook - using embedded JSON for more customization (like changing colors)
    local embed_json=$(jq -n \
        --arg title "$message_title" \
        --arg desc "$message" \
        --argjson color "$message_color" \
        '{embeds: [{title: $title, description: $desc, color: $color}]}')

    # Send to Discord webhook
    curl -H "Content-Type: application/json" -X POST -d "$embed_json" "$DISCORD_WEBHOOK_URL"
}

check_ca_validity() {
    if [[ ! -f "${ROOT_CA_NAME}.crt" || ! -f "${ROOT_CA_NAME}.key" ]]; then
        return 1
    fi
    openssl x509 -checkend 0 -noout -in "${ROOT_CA_NAME}.crt" > /dev/null
    return $?
}

check_cert_validity() {
    if [[ ! -f "${KEY_NAME}.crt" || ! -f "${KEY_NAME}.key" ]]; then
        return 1
    fi

    if [[ "$NEW_ROOT_GENERATED" == "true" ]]; then
        return 3
    fi

    expiration_date=$(openssl x509 -enddate -noout -in "${KEY_NAME}.crt" | cut -d= -f2)
    log_message "Checking Certificate Validity...Certificate expires on: $expiration_date"

    # Check if cert expires in less than X seconds (e.g., 30 days)
    local threshold=$((${CERT_RENEWAL_THRESHOLD_DAYS} * 24 * 60 * 60)) # 30 days
    if ! openssl x509 -checkend $threshold -noout -in "${KEY_NAME}.crt"; then
        return 0 # cert expires soon, regenerate
    fi

    return 2 # cert is valid
}

archive_old_files() {
    mkdir -p "$ARCHIVE_DIR"
    for file in "${CERT_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            mv "$file" "${ARCHIVE_DIR}/${file}_${DATESTAMP}"
        fi
    done
}

archive_old_ca() {
    mkdir -p "$ARCHIVE_DIR"
    if [[ -f "${ROOT_CA_NAME}.crt" && -f "${ROOT_CA_NAME}.key" ]]; then
        echo "Archiving existing CA..."
        mv "${ROOT_CA_NAME}.crt" "${ARCHIVE_DIR}/${ROOT_CA_NAME}.crt_${DATESTAMP}"
        mv "${ROOT_CA_NAME}.key" "${ARCHIVE_DIR}/${ROOT_CA_NAME}.key_${DATESTAMP}"
    fi
}

generate_root_ca() {
    echo "Generating new Root CA..."
    archive_old_ca
    openssl genrsa -out "${ROOT_CA_NAME}.key" $KEY_SIZE
    openssl req -x509 -new -nodes -key "${ROOT_CA_NAME}.key" \
        -sha256 -days $DAYS_CA -out "${ROOT_CA_NAME}.crt" \
        -subj "/C=US/ST=${STATE}/L=${CITY}/O=${ORG}/CN=${ORG} Root CA"

    NEW_ROOT_GENERATED=true
}

generate_wildcard_key() {
    echo "Generating wildcard private key..."
    openssl genrsa -out "${KEY_NAME}.key" $KEY_SIZE
}

generate_extfile() {
    cat > extfile.cnf <<EOF
[ req ]
default_bits       = $KEY_SIZE
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[ dn ]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
CN = ${KEY_NAME}.${CA_TLD}

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = *.${KEY_NAME}.${CA_TLD}
DNS.2 = *.${CA_ALT_NAME}.${KEY_NAME}.${CA_TLD}
DNS.3 = ${KEY_NAME}.${CA_TLD}
DNS.4 = ${CA_ALT_NAME}.${KEY_NAME}.${CA_TLD}
EOF
}

generate_csr() {
    echo "Generating CSR..."
    openssl req -new -key "${KEY_NAME}.key" -out "${KEY_NAME}.csr" -config extfile.cnf
}

sign_certificate() {
    echo "Signing certificate with Root CA..."
    openssl x509 -req -in "${KEY_NAME}.csr" \
        -CA "${ROOT_CA_NAME}.crt" -CAkey "${ROOT_CA_NAME}.key" -CAcreateserial \
        -out "${KEY_NAME}.crt" -days $DAYS_CERT -sha256 \
        -extfile extfile.cnf -extensions req_ext
}

verify_cert() {
    echo ""
    echo "Certificate Summary:"
    openssl x509 -in "${KEY_NAME}.crt" -noout -text | grep -A 15 "Subject:"
}

generate_selfsigned_certificate() {
    generate_wildcard_key
    generate_extfile
    generate_csr
    sign_certificate
}

# ========== EXECUTION ==========

# DRY_RUN logic
if [ "${DRY_RUN}" = "true" ]; then
    log_message "[selfsigned-certgen-trigger] DRY_RUN enabled - testing selfsigned-certgen script and notifications ONLY..."
    # TEST Send a notification
    send_discord_notification ":white_check_mark::test_tube: **_Test_ run of selfsigned-certgen Completed Successfully** - This was a test only."
else
    log_message "[selfsigned-certgen-trigger] DRY_RUN disabled - generating new certificate if needed..."
    echo "Archiving old cert/key files..."
    archive_old_files

    echo "Checking existing Root CA..."
    if check_ca_validity; then
        echo "Valid CA found. Reusing existing CA."
    else
        generate_root_ca
    fi

    check_cert_validity
    status=$?

    if [[ $status -eq 2 ]]; then
        send_discord_notification "Valid certificate found. No need to generate a new certificate."
    elif [[ $status -eq 0 ]]; then
        send_discord_notification "Certificate expired. Regenerating..."
        generate_selfsigned_certificate
    elif [[ $status -eq 3 ]]; then
        send_discord_notification "Root CA updated. Regenerating certificate..."
        generate_selfsigned_certificate
    else
        send_discord_notification "Certificate or key missing. Regenerating..."
        generate_selfsigned_certificate
    fi

    verify_cert

    echo ""
    echo "Wildcard certificate issued successfully."
fi

# Get next scheduled run:
"/app/scripts/preview-schedule.sh"