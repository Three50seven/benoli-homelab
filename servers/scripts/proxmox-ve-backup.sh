#!/bin/bash
# proxmox-ve-backup.sh - Full backup for Proxmox VE with restore manifest and versioning. 
# This script auto-detects all VMs and containers, backs them up, archives critical system configs, and generates a timestamped restore manifest. It also includes version tagging so you can track changes across iterations.
# Version: 1.1.0
# Author: Paul (via Copilot)
# Date: 2025-09-11

## === CONFIG ===
SCRIPT_VERSION="1.1.0"
BACKUP_ROOT="/mnt/usb-backup"
LOG_FILE="/var/log/pve-backup.log"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
MANIFEST_FILE="$BACKUP_DIR/restore-manifest.txt"

# === PRECHECK ===
echo "[$TIMESTAMP] Starting proxmox-ve-backup.sh v$SCRIPT_VERSION..." | tee -a "$LOG_FILE"

if ! mountpoint -q "$BACKUP_ROOT"; then
  echo "[$TIMESTAMP] ERROR: Backup drive not mounted at $BACKUP_ROOT" | tee -a "$LOG_FILE"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

# === INIT MANIFEST ===
echo "Restore Manifest - $TIMESTAMP" > "$MANIFEST_FILE"
echo "Script Version: $SCRIPT_VERSION" >> "$MANIFEST_FILE"
echo "======================================" >> "$MANIFEST_FILE"
echo "" >> "$MANIFEST_FILE"

# === BACKUP VMs ===
echo "[$TIMESTAMP] Detecting and backing up VMs..." | tee -a "$LOG_FILE"
for VMID in $(qm list | awk 'NR>1 {print $1}'); do
  VMNAME=$(qm config $VMID | grep -i name | cut -d ':' -f2 | xargs)
  echo "[$TIMESTAMP] Backing up VM $VMID ($VMNAME)..." | tee -a "$LOG_FILE"
  vzdump $VMID --dumpdir "$BACKUP_DIR" --mode stop --compress zstd
  echo "VM $VMID - $VMNAME" >> "$MANIFEST_FILE"
  qm config $VMID >> "$MANIFEST_FILE"
  echo "" >> "$MANIFEST_FILE"
done

# === BACKUP CTs ===
echo "[$TIMESTAMP] Detecting and backing up containers..." | tee -a "$LOG_FILE"
for CTID in $(pct list | awk 'NR>1 {print $1}'); do
  CTNAME=$(pct config $CTID | grep -i hostname | cut -d ':' -f2 | xargs)
  echo "[$TIMESTAMP] Backing up CT $CTID ($CTNAME)..." | tee -a "$LOG_FILE"
  vzdump $CTID --dumpdir "$BACKUP_DIR" --mode stop --compress zstd
  echo "CT $CTID - $CTNAME" >> "$MANIFEST_FILE"
  pct config $CTID >> "$MANIFEST_FILE"
  echo "" >> "$MANIFEST_FILE"
done

# === BACKUP CONFIGS ===
echo "[$TIMESTAMP] Archiving system configs..." | tee -a "$LOG_FILE"
tar czf "$BACKUP_DIR/pve-configs.tar.gz" \
  /etc/pve \
  /etc/network/interfaces \
  /etc/hosts \
  /etc/resolv.conf \
  /etc/udev/rules.d \
  /etc/systemd/network \
  /etc/pve/firewall \
  /etc/ssh \
  /root/.ssh \
  ~/.ssh

# === ADD NETWORK SUMMARY TO MANIFEST ===
echo "Network Configuration Summary:" >> "$MANIFEST_FILE"
echo "------------------------------" >> "$MANIFEST_FILE"
cat /etc/network/interfaces >> "$MANIFEST_FILE"
echo "" >> "$MANIFEST_FILE"

# === ADD ZFS POOL SUMMARY TO MANIFEST ===
echo "ZFS Pool Status:" >> "$MANIFEST_FILE"
echo "----------------" >> "$MANIFEST_FILE"
zpool list >> "$MANIFEST_FILE"
echo "" >> "$MANIFEST_FILE"
echo "ZFS Pool Details:" >> "$MANIFEST_FILE"
zpool status >> "$MANIFEST_FILE"
echo "" >> "$MANIFEST_FILE"

# === VERIFY ===
echo "[$TIMESTAMP] Backup complete. Contents:" | tee -a "$LOG_FILE"
ls -lh "$BACKUP_DIR" | tee -a "$LOG_FILE"
echo "Restore manifest saved to: $MANIFEST_FILE" | tee -a "$LOG_FILE"