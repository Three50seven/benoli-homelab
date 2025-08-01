#!/bin/bash

# SFTP User Setup Script with Key Authentication
# Usage: ./setup-sftp-user.sh <username>
# Run this script as a user with appropriate permissions

set -e  # Exit on any error

# Check if username is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <username>"
    echo "Example: $0 john"
    exit 1
fi

# Configuration
USERNAME="$1"
HOME_DIR="/naspool/share/benolilab-docker/foldersync/$USERNAME"  # Change this path to whatever you want
FOLDERSYNC_GROUP="foldersyncgroup"
SSH_DIR="$HOME_DIR/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
PRIVATE_KEY="${USERNAME}_key"
PUBLIC_KEY="${USERNAME}_key.pub"

echo "=== SFTP User Setup Script ==="
echo "Setting up user: $USERNAME"
echo

# Create foldersyncgroup if it doesn't exist
if ! getent group "$FOLDERSYNC_GROUP" > /dev/null 2>&1; then
    echo "Creating group $FOLDERSYNC_GROUP..."
    groupadd "$FOLDERSYNC_GROUP"
    echo "Group $FOLDERSYNC_GROUP created successfully."
else
    echo "Group $FOLDERSYNC_GROUP already exists."
fi

# Check if user already exists
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists. Adding to $FOLDERSYNC_GROUP if needed..."
    usermod -a -G "$FOLDERSYNC_GROUP" "$USERNAME"
else
    echo "Creating user $USERNAME..."
    useradd -m -d "$HOME_DIR" -s /bin/bash -G "$FOLDERSYNC_GROUP" "$USERNAME"
    echo "User $USERNAME created successfully and added to $FOLDERSYNC_GROUP."
fi

# Create SSH directory
echo "Setting up SSH directory..."
mkdir -p "$SSH_DIR"

# Generate SSH key pair
echo "Generating SSH key pair..."
ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "$USERNAME@foldersync"

# Set up authorized_keys
echo "Setting up authorized_keys..."
cp "$PUBLIC_KEY" "$AUTHORIZED_KEYS"

# Set proper permissions
echo "Setting permissions..."
chown -R "$USERNAME:$USERNAME" "$HOME_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTHORIZED_KEYS"
chmod 600 "$PRIVATE_KEY"
chmod 644 "$PUBLIC_KEY"

# Create SFTP chroot directory structure
echo "Setting up SFTP directory structure..."
SFTP_DIR="$HOME_DIR/sftp"
UPLOAD_DIR="$SFTP_DIR/upload"
mkdir -p "$UPLOAD_DIR"
chown root:root "$SFTP_DIR"
chmod 755 "$SFTP_DIR"
chown "$USERNAME:$USERNAME" "$UPLOAD_DIR"
chmod 755 "$UPLOAD_DIR"

# Backup original sshd_config
echo "Backing up SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# Add SFTP configuration to sshd_config
echo "Updating SSH configuration..."
if ! grep -q "Match Group $FOLDERSYNC_GROUP" /etc/ssh/sshd_config; then
    cat >> /etc/ssh/sshd_config << EOF

# SFTP Configuration for $FOLDERSYNC_GROUP
Match Group $FOLDERSYNC_GROUP
    ForceCommand internal-sftp
    PasswordAuthentication no
    PermitTunnel no
    AllowAgentForwarding no
    AllowTcpForwarding no
    X11Forwarding no
EOF
    echo "Added group-based SFTP configuration for $FOLDERSYNC_GROUP (no chroot)"
else
    echo "Group-based SFTP configuration already exists for $FOLDERSYNC_GROUP"
fi

# Update AllowUsers if it exists, or suggest using AllowGroups
echo "Checking SSH user access configuration..."
if grep -q "^AllowUsers" /etc/ssh/sshd_config; then
    # AllowUsers exists, check if our user is already in it
    if ! grep "^AllowUsers" /etc/ssh/sshd_config | grep -q "\b$USERNAME\b"; then
        echo "Adding $USERNAME to AllowUsers..."
        sed -i "s/^AllowUsers.*/& $USERNAME/" /etc/ssh/sshd_config
        echo "User $USERNAME added to AllowUsers."
    else
        echo "User $USERNAME already in AllowUsers."
    fi
    echo "Consider switching to 'AllowGroups $FOLDERSYNC_GROUP' for easier management."
elif grep -q "^AllowGroups" /etc/ssh/sshd_config; then
    # AllowGroups exists, check if our group is in it
    if ! grep "^AllowGroups" /etc/ssh/sshd_config | grep -q "\b$FOLDERSYNC_GROUP\b"; then
        echo "Adding $FOLDERSYNC_GROUP to AllowGroups..."
        sed -i "s/^AllowGroups.*/& $FOLDERSYNC_GROUP/" /etc/ssh/sshd_config
        echo "Group $FOLDERSYNC_GROUP added to AllowGroups."
    else
        echo "Group $FOLDERSYNC_GROUP already in AllowGroups."
    fi
else
    echo "No AllowUsers or AllowGroups restriction found - user can connect."
    echo "Consider adding 'AllowGroups $FOLDERSYNC_GROUP' for better security."
fi

# Test SSH configuration
echo "Testing SSH configuration..."
sshd -t

echo
echo "=== Setup Complete! ==="
echo
echo "Generated files:"
echo "  Private key: $PRIVATE_KEY (copy this to your Android device)"
echo "  Public key:  $PUBLIC_KEY"
echo
echo "User details:"
echo "  Username: $USERNAME"
echo "  Group: $FOLDERSYNC_GROUP"
echo "  Home directory: $HOME_DIR"
echo "  SFTP upload directory: $UPLOAD_DIR"
echo
echo "Next steps:"
echo "1. Restart SSH service: systemctl restart ssh"
echo "2. Copy '$PRIVATE_KEY' to $USERNAME's Android device"
echo "3. Configure FolderSync with:"
echo "   - Server: your-nas-ip"
echo "   - Username: $USERNAME"
echo "   - Authentication: Private key"
echo "   - Private key file: (select the copied $PRIVATE_KEY file)"
echo "   - Remote folder: /upload"
echo
echo "Test the connection:"
echo "  sftp -i $PRIVATE_KEY $USERNAME@localhost"
echo
echo "IMPORTANT: Keep the private key file secure and delete it from this server after copying to Android!"