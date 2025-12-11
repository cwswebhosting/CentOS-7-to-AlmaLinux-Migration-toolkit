#!/bin/bash
#===============================================================================
# Script: 03-virtualmin-backup.sh
# Purpose: Create Virtualmin-specific backups for easy migration
# Author: Migration Toolkit
# Usage: sudo ./03-virtualmin-backup.sh [backup_destination]
#
# This creates backups that can be directly restored on a new Virtualmin server
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_BASE="${1:-/root/migration-backup}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_BASE/virtualmin-backup-$TIMESTAMP"
LOG_FILE="$BACKUP_DIR/backup.log"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          VIRTUALMIN BACKUP SCRIPT                            ║${NC}"
echo -e "${BLUE}║          Backup Directory: $BACKUP_DIR${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if virtualmin command exists
if ! command -v virtualmin &> /dev/null; then
    echo -e "${RED}ERROR: Virtualmin is not installed or not in PATH${NC}"
    echo "This script requires Virtualmin. Exiting."
    exit 1
fi

log "Starting Virtualmin backup..."

#-------------------------------------------------------------------------------
# Get list of domains
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[1/5] Getting list of virtual servers...${NC}"

DOMAINS=$(virtualmin list-domains --name-only 2>/dev/null)
DOMAIN_COUNT=$(echo "$DOMAINS" | wc -l)

if [ -z "$DOMAINS" ]; then
    echo -e "${YELLOW}No virtual servers found.${NC}"
    DOMAIN_COUNT=0
fi

log "Found $DOMAIN_COUNT virtual servers"
echo "$DOMAINS" | tee "$BACKUP_DIR/domain-list.txt"

#-------------------------------------------------------------------------------
# Backup each domain individually
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[2/5] Backing up individual domains...${NC}"
mkdir -p "$BACKUP_DIR/domains"

if [ "$DOMAIN_COUNT" -gt 0 ]; then
    echo "$DOMAINS" | while read domain; do
        if [ -n "$domain" ]; then
            echo -e "  Backing up: ${BLUE}$domain${NC}"
            log "Backing up domain: $domain"
            
            # Full backup including all features
            virtualmin backup-domain \
                --domain "$domain" \
                --all-features \
                --dest "$BACKUP_DIR/domains/${domain}.tar.gz" \
                --newformat \
                2>&1 | tee -a "$LOG_FILE" || log "WARNING: Backup of $domain may be incomplete"
            
            # Also get domain info
            virtualmin list-domains --domain "$domain" --multiline \
                > "$BACKUP_DIR/domains/${domain}-info.txt" 2>/dev/null || true
        fi
    done
fi

#-------------------------------------------------------------------------------
# Backup all domains in one file (alternative)
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[3/5] Creating combined backup of all domains...${NC}"

if [ "$DOMAIN_COUNT" -gt 0 ]; then
    log "Creating combined backup..."
    virtualmin backup-domain \
        --all-domains \
        --all-features \
        --dest "$BACKUP_DIR/all-domains-backup.tar.gz" \
        --newformat \
        2>&1 | tee -a "$LOG_FILE" || log "WARNING: Combined backup may be incomplete"
fi

#-------------------------------------------------------------------------------
# Backup Virtualmin configuration
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[4/5] Backing up Virtualmin configuration...${NC}"
mkdir -p "$BACKUP_DIR/virtualmin-config"

log "Backing up Virtualmin settings..."

# Backup Webmin/Virtualmin configuration
tar -czf "$BACKUP_DIR/virtualmin-config/webmin-etc.tar.gz" -C /etc webmin 2>/dev/null || true
tar -czf "$BACKUP_DIR/virtualmin-config/usermin-etc.tar.gz" -C /etc usermin 2>/dev/null || true

# Export Virtualmin settings
if [ -d /etc/webmin/virtual-server ]; then
    cp -r /etc/webmin/virtual-server "$BACKUP_DIR/virtualmin-config/" 2>/dev/null || true
fi

# Backup server templates
virtualmin list-templates --name-only 2>/dev/null | while read template; do
    if [ -n "$template" ]; then
        virtualmin list-templates --name "$template" --multiline \
            > "$BACKUP_DIR/virtualmin-config/template-${template}.txt" 2>/dev/null || true
    fi
done

# Backup plans
virtualmin list-plans --name-only 2>/dev/null | while read plan; do
    if [ -n "$plan" ]; then
        virtualmin list-plans --name "$plan" --multiline \
            > "$BACKUP_DIR/virtualmin-config/plan-${plan}.txt" 2>/dev/null || true
    fi
done

# Backup script installers settings
if [ -d /etc/webmin/virtual-server/scripts ]; then
    cp -r /etc/webmin/virtual-server/scripts "$BACKUP_DIR/virtualmin-config/" 2>/dev/null || true
fi

log "Virtualmin configuration backed up"

#-------------------------------------------------------------------------------
# Backup additional Virtualmin data
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[5/5] Backing up additional data...${NC}"
mkdir -p "$BACKUP_DIR/additional"

# Pro license key (if exists)
if [ -f /etc/virtualmin-license ]; then
    cp /etc/virtualmin-license "$BACKUP_DIR/additional/" 2>/dev/null || true
    log "Virtualmin license backed up"
fi

# Backup DNS zones
if [ -d /var/named ]; then
    tar -czf "$BACKUP_DIR/additional/named-zones.tar.gz" -C /var named 2>/dev/null || true
    log "DNS zones backed up"
fi

# DKIM keys
if [ -d /etc/opendkim ]; then
    tar -czf "$BACKUP_DIR/additional/opendkim.tar.gz" -C /etc opendkim 2>/dev/null || true
    log "DKIM configuration backed up"
fi

# SpamAssassin configuration
if [ -d /etc/mail/spamassassin ]; then
    tar -czf "$BACKUP_DIR/additional/spamassassin.tar.gz" -C /etc/mail spamassassin 2>/dev/null || true
fi

# ClamAV configuration
if [ -d /etc/clamd.d ]; then
    tar -czf "$BACKUP_DIR/additional/clamav.tar.gz" -C /etc clamd.d 2>/dev/null || true
fi

# Fail2ban configuration
if [ -d /etc/fail2ban ]; then
    tar -czf "$BACKUP_DIR/additional/fail2ban.tar.gz" -C /etc fail2ban 2>/dev/null || true
fi

#-------------------------------------------------------------------------------
# Create restore instructions
#-------------------------------------------------------------------------------
cat << 'EOF' > "$BACKUP_DIR/RESTORE-INSTRUCTIONS.md"
# Virtualmin Backup Restore Instructions

## Quick Restore (Recommended Method)

### On New AlmaLinux 8 Server with Fresh Virtualmin:

1. **Install Virtualmin on new server first:**
   ```bash
   wget https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh
   chmod +x virtualmin-install.sh
   ./virtualmin-install.sh
   ```

2. **Copy backup files to new server:**
   ```bash
   scp -r /path/to/virtualmin-backup-* root@newserver:/root/
   ```

3. **Restore individual domains:**
   ```bash
   # Restore single domain
   virtualmin restore-domain \
       --source /root/virtualmin-backup-*/domains/example.com.tar.gz \
       --all-features
   
   # Or restore all domains from combined backup
   virtualmin restore-domain \
       --source /root/virtualmin-backup-*/all-domains-backup.tar.gz \
       --all-domains \
       --all-features
   ```

4. **For each domain, you may need to:**
   - Update DNS records to point to new server IP
   - Re-issue SSL certificates if needed
   - Test email delivery
   - Verify website functionality

## Restore Via Web Interface

1. Log into Virtualmin on new server
2. Go to: Virtualmin → Backup and Restore → Restore Virtual Servers
3. Select backup file location
4. Choose domains to restore
5. Select features to restore
6. Click "Restore Now"

## Important Notes

- Restore preserves: users, databases, email, files, DNS, SSL, etc.
- User passwords are preserved
- Database content is preserved
- Email is preserved in Maildir format

## Troubleshooting

### Domain already exists
```bash
virtualmin delete-domain --domain example.com
```
Then restore again.

### Permission issues after restore
```bash
virtualmin validate-domains --domain example.com --all-features
virtualmin modify-domain --domain example.com --apply-template
```

### SSL certificate issues
```bash
virtualmin generate-letsencrypt-cert --domain example.com
```

### Email not working
```bash
virtualmin modify-domain --domain example.com --mail
postfix reload
dovecot reload
```

EOF

#-------------------------------------------------------------------------------
# Create manifest
#-------------------------------------------------------------------------------
cat << EOF > "$BACKUP_DIR/MANIFEST.txt"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    VIRTUALMIN BACKUP MANIFEST                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

Backup Created: $(date)
Hostname: $(hostname)
Source OS: $(cat /etc/redhat-release)
Virtualmin Version: $(rpm -q virtualmin-base 2>/dev/null || echo "Unknown")
Webmin Version: $(rpm -q webmin 2>/dev/null || echo "Unknown")

DOMAINS BACKED UP:
==================
$(cat "$BACKUP_DIR/domain-list.txt" 2>/dev/null || echo "None")

BACKUP CONTENTS:
================
domains/                    - Individual domain backups
  └── *.tar.gz             - Each domain as separate backup
  └── *-info.txt           - Domain configuration details

all-domains-backup.tar.gz  - Combined backup of all domains

virtualmin-config/         - Virtualmin configuration
  └── webmin-etc.tar.gz    - Webmin configuration
  └── usermin-etc.tar.gz   - Usermin configuration
  └── virtual-server/      - Virtualmin settings
  └── template-*.txt       - Server templates
  └── plan-*.txt           - Account plans

additional/                - Additional data
  └── named-zones.tar.gz   - DNS zone files
  └── opendkim.tar.gz      - DKIM configuration
  └── spamassassin.tar.gz  - SpamAssassin rules
  └── fail2ban.tar.gz      - Fail2ban configuration

BACKUP SIZES:
=============
$(du -sh "$BACKUP_DIR"/* 2>/dev/null | sort -rh)

TOTAL SIZE: $(du -sh "$BACKUP_DIR" | awk '{print $1}')

EOF

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               VIRTUALMIN BACKUP COMPLETE                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Backup location: ${BLUE}$BACKUP_DIR${NC}"
echo -e "Total size: ${BLUE}$TOTAL_SIZE${NC}"
echo -e "Domains backed up: ${BLUE}$DOMAIN_COUNT${NC}"
echo ""
echo "Backup files:"
ls -lh "$BACKUP_DIR/domains/"*.tar.gz 2>/dev/null || echo "  No individual domain backups"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "  1. Read RESTORE-INSTRUCTIONS.md for restore process"
echo "  2. Copy backups to external storage"
echo "  3. These backups can be restored on ANY Virtualmin server"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "  1. Set up new AlmaLinux 8 server with Virtualmin"
echo "  2. Transfer these backups to new server"
echo "  3. Use virtualmin restore-domain to restore"
echo ""

log "Virtualmin backup completed. Total size: $TOTAL_SIZE"
