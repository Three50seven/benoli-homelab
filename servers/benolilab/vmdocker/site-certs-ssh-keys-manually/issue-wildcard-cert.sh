#!/bin/bash
# Usage:
# chmod +x issue-wildcard-cert.sh
# ./issue-wildcard-cert.sh

# ========== CONFIG ==========
KEY_NAME="mylab" # Second level domain (SLD) e.g. mylab portion of mylab.home
CA_TLD="home" # Top level domain (TLD) e.g. home porttion of mylab.home
CA_ALT_NAME="svc" # Alternate name used in DNS SANs, e.g. svc.mylab.home and *.svc.mylab.home
ROOT_CA_NAME="mylab-rootCA"
STATE="StateName"
CITY="CityName"
ORG="OrgName"
KEY_SIZE=4096
DAYS_CA=1825 # Default to ~5 years
DAYS_CERT=731 # Default to ~2yrs + 1 day
ARCHIVE_DIR="./archive"
DATESTAMP=$(date +%Y%m%d)

CERT_FILES=("${KEY_NAME}.key" "${KEY_NAME}.csr" "${KEY_NAME}.crt" "extfile.cnf")

# ========== FUNCTIONS ==========

check_ca_validity() {
    if [[ ! -f "${ROOT_CA_NAME}.crt" || ! -f "${ROOT_CA_NAME}.key" ]]; then
        return 1
    fi
    openssl x509 -checkend 0 -noout -in "${ROOT_CA_NAME}.crt" > /dev/null
    return $?
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
        -subj "/C=US/ST=${STATE}/L=${CITY}/O=${ORG}/CN=MyLab Root CA"
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
C = US
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

# ========== EXECUTION ==========

echo "Archiving old cert/key files..."
archive_old_files

echo "Checking existing Root CA..."
if check_ca_validity; then
    echo "Valid CA found. Reusing existing CA."
else
    generate_root_ca
fi

generate_wildcard_key
generate_extfile
generate_csr
sign_certificate
verify_cert

echo ""
echo "Wildcard certificate issued successfully."