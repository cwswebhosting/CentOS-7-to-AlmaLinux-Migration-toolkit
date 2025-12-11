#!/bin/bash
#===============================================================================
# Script: transfer-backups.sh
# Purpose: Helper script to transfer backups between servers
# Author: Migration Toolkit
# Usage: ./transfer-backups.sh [destination_ip]
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          BACKUP TRANSFER HELPER                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

DEST_IP="${1}"

if [ -z "$DEST_IP" ]; then
    echo "Usage: $0 <destination_server_ip>"
    echo ""
    echo "Example: $0 192.168.1.100"
    echo ""
    exit 1
fi

BACKUP_BASE="/root/migration-backup"

if [ ! -d "$BACKUP_BASE" ]; then
    echo -e "${RED}ERROR: Backup directory not found: $BACKUP_BASE${NC}"
    echo "Please run the backup scripts first:"
    echo "  ./02-full-backup.sh"
    echo "  ./03-virtualmin-backup.sh"
    exit 1
fi

echo "Found backups in $BACKUP_BASE:"
ls -lh "$BACKUP_BASE"
echo ""

TOTAL_SIZE=$(du -sh "$BACKUP_BASE" | awk '{print $1}')
echo "Total size to transfer: $TOTAL_SIZE"
echo ""

read -p "Transfer backups to root@$DEST_IP? (y/n): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Creating destination directory on remote server..."
ssh "root@$DEST_IP" "mkdir -p /root/migration-restore"

echo ""
echo "Transferring backups (this may take a while)..."
echo ""

rsync -avz --progress "$BACKUP_BASE/" "root@$DEST_IP:/root/migration-restore/"

echo ""
echo -e "${GREEN}Transfer complete!${NC}"
echo ""
echo "Next steps on the new server ($DEST_IP):"
echo "  1. cd /root/migration-restore"
echo "  2. ./06-restore-migration.sh"
echo ""
