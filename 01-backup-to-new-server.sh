#!/bin/bash
#===============================================================================
# Script: 01-backup-to-new-server.sh
# Purpose: Backup everything from CentOS 7 and transfer to temporary new server
# Run On: OLD SERVER (CentOS 7) - BEFORE fresh install
# 
# This script will:
# 1. Create complete Virtualmin backups
# 2. Backup all databases
# 3. Backup all configurations
# 4. Transfer everything to the new temporary server
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#===============================================================================
# CONFIGURATION - EDIT THESE VALUES
#===============================================================================
NEW_SERVER_IP=""           # Will be prompted if empty
NEW_SERVER_USER="root"     # SSH user on new server
BACKUP_DIR="/root/full-migration-backup"
REMOTE_BACKUP_DIR="/root/migration-data"
#===============================================================================

LOG_FILE="/root/backup-transfer-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     STEP 1: BACKUP & TRANSFER TO TEMPORARY SERVER           ║${NC}"
echo -e "${BLUE}║     Run this on: OLD SERVER (CentOS 7)                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Get new server IP if not set
#-------------------------------------------------------------------------------
if [ -z "$NEW_SERVER_IP" ]; then
    read -p "Enter the IP address of the NEW (temporary) server: " NEW_SERVER_IP
fi

if [ -z "$NEW_SERVER_IP" ]; then
    echo -e "${RED}ERROR: New server IP is required${NC}"
    exit 1
fi

echo ""
echo "Configuration:"
echo "  Old Server (this): $(hostname) / $(hostname -I | awk '{print $1}')"
echo "  New Server (temp): $NEW_SERVER_IP"
echo "  Local Backup Dir:  $BACKUP_DIR"
echo "  Remote Backup Dir: $REMOTE_BACKUP_DIR"
echo ""

read -p "Is this correct? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

log "Starting backup process to transfer to $NEW_SERVER_IP"

#-------------------------------------------------------------------------------
# Test SSH connection
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[1/10] Testing SSH connection to new server...${NC}"

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "${NEW_SERVER_USER}@${NEW_SERVER_IP}" "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${YELLOW}SSH key authentication not set up. Setting up now...${NC}"
    
    # Generate key if doesn't exist
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
    fi
    
    # Copy key to new server
    echo "Please enter the password for ${NEW_SERVER_USER}@${NEW_SERVER_IP}:"
    ssh-copy-id "${NEW_SERVER_USER}@${NEW_SERVER_IP}"
fi

# Verify connection
if ssh -o BatchMode=yes -o ConnectTimeout=10 "${NEW_SERVER_USER}@${NEW_SERVER_IP}" "echo 'Connection verified'" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} SSH connection successful"
else
    echo -e "${RED}ERROR: Cannot connect to new server${NC}"
    exit 1
fi

# Create remote directory
ssh "${NEW_SERVER_USER}@${NEW_SERVER_IP}" "mkdir -p ${REMOTE_BACKUP_DIR}"
log "SSH connection verified"

#-------------------------------------------------------------------------------
# Create local backup directory
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[2/10] Creating backup directory...${NC}"

rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"/{virtualmin,mysql,home,www,config,mail,ssl,cron}

log "Backup directory created: $BACKUP_DIR"

#-------------------------------------------------------------------------------
# Backup Virtualmin domains
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/10] Backing up Virtualmin domains...${NC}"

if command -v virtualmin &> /dev/null; then
    # Get list of domains
    DOMAINS=$(virtualmin list-domains --name-only 2>/dev/null)
    echo "$DOMAINS" > "$BACKUP_DIR/virtualmin/domain-list.txt"
    
    DOMAIN_COUNT=$(echo "$DOMAINS" | grep -v "^$" | wc -l)
    log "Found $DOMAIN_COUNT domains"
    
    # Backup each domain
    echo "$DOMAINS" | while read domain; do
        if [ -n "$domain" ]; then
            echo "  Backing up: $domain"
            virtualmin backup-domain \
                --domain "$domain" \
                --all-features \
                --dest "$BACKUP_DIR/virtualmin/${domain}.tar.gz" \
                --newformat \
                2>&1 | tee -a "$LOG_FILE" || log "WARNING: Issues with $domain"
        fi
    done
    
    # Also create combined backup
    echo "  Creating combined backup..."
    virtualmin backup-domain \
        --all-domains \
        --all-features \
        --dest "$BACKUP_DIR/virtualmin/all-domains.tar.gz" \
        --newformat \
        2>&1 | tee -a "$LOG_FILE" || true
    
    echo -e "${GREEN}✓${NC} Virtualmin backup complete"
else
    echo -e "${YELLOW}! Virtualmin not found${NC}"
fi

#-------------------------------------------------------------------------------
# Backup MariaDB/MySQL
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/10] Backing up MariaDB databases...${NC}"

# Full dump
log "Creating full database dump"
mysqldump --all-databases --single-transaction --routines --triggers --events \
    > "$BACKUP_DIR/mysql/all-databases.sql" 2>/dev/null || \
    log "WARNING: Full dump may be incomplete"

# Individual databases
mysql -N -e "SHOW DATABASES" 2>/dev/null | grep -vE "^(information_schema|performance_schema|mysql|sys)$" | while read db; do
    echo "  Dumping: $db"
    mysqldump --single-transaction --routines --triggers "$db" \
        > "$BACKUP_DIR/mysql/${db}.sql" 2>/dev/null || true
done

# MySQL users and grants
mysql -N -e "SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session','mariadb.sys');" 2>/dev/null | while read cmd; do
    mysql -N -e "$cmd" 2>/dev/null >> "$BACKUP_DIR/mysql/all-grants.sql" || true
done

# MySQL config
cp /etc/my.cnf "$BACKUP_DIR/mysql/" 2>/dev/null || true
cp -r /etc/my.cnf.d "$BACKUP_DIR/mysql/" 2>/dev/null || true

# Compress
gzip "$BACKUP_DIR/mysql/"*.sql 2>/dev/null || true

echo -e "${GREEN}✓${NC} Database backup complete"
log "Database backup complete"

#-------------------------------------------------------------------------------
# Backup Home Directories
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/10] Backing up home directories...${NC}"

log "Backing up /home"
tar -czf "$BACKUP_DIR/home/home.tar.gz" \
    --exclude='*.log' \
    --exclude='*/cache/*' \
    --exclude='*/.cache/*' \
    --exclude='*/tmp/*' \
    -C / home 2>/dev/null || log "WARNING: Some home files skipped"

echo -e "${GREEN}✓${NC} Home directories backed up"

#-------------------------------------------------------------------------------
# Backup Web Content
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/10] Backing up /var/www...${NC}"

if [ -d /var/www ]; then
    tar -czf "$BACKUP_DIR/www/var-www.tar.gz" -C /var www 2>/dev/null || true
fi

echo -e "${GREEN}✓${NC} Web content backed up"

#-------------------------------------------------------------------------------
# Backup Configuration Files
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/10] Backing up configuration files...${NC}"

# Full /etc backup
tar -czf "$BACKUP_DIR/config/etc-full.tar.gz" -C / etc 2>/dev/null

# Individual critical configs
mkdir -p "$BACKUP_DIR/config/services"

# Apache
cp -r /etc/httpd "$BACKUP_DIR/config/services/" 2>/dev/null || true

# Postfix
cp -r /etc/postfix "$BACKUP_DIR/config/services/" 2>/dev/null || true

# Dovecot
cp -r /etc/dovecot "$BACKUP_DIR/config/services/" 2>/dev/null || true

# Webmin/Virtualmin
cp -r /etc/webmin "$BACKUP_DIR/config/services/" 2>/dev/null || true
cp -r /etc/usermin "$BACKUP_DIR/config/services/" 2>/dev/null || true

# PHP
cp /etc/php.ini "$BACKUP_DIR/config/services/" 2>/dev/null || true
cp -r /etc/php.d "$BACKUP_DIR/config/services/" 2>/dev/null || true
cp -r /etc/php-fpm.d "$BACKUP_DIR/config/services/" 2>/dev/null || true

# DNS
cp -r /etc/named* "$BACKUP_DIR/config/services/" 2>/dev/null || true
cp -r /var/named "$BACKUP_DIR/config/services/" 2>/dev/null || true

# Users
cp /etc/passwd "$BACKUP_DIR/config/passwd"
cp /etc/shadow "$BACKUP_DIR/config/shadow"
cp /etc/group "$BACKUP_DIR/config/group"
cp /etc/gshadow "$BACKUP_DIR/config/gshadow" 2>/dev/null || true

# Network
cp /etc/hosts "$BACKUP_DIR/config/"
cp /etc/hostname "$BACKUP_DIR/config/"
cp /etc/resolv.conf "$BACKUP_DIR/config/"

echo -e "${GREEN}✓${NC} Configuration backed up"

#-------------------------------------------------------------------------------
# Backup SSL Certificates
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[8/10] Backing up SSL certificates...${NC}"

if [ -d /etc/letsencrypt ]; then
    tar -czf "$BACKUP_DIR/ssl/letsencrypt.tar.gz" -C /etc letsencrypt
    log "Let's Encrypt certificates backed up"
fi

tar -czf "$BACKUP_DIR/ssl/etc-ssl.tar.gz" -C /etc ssl 2>/dev/null || true
tar -czf "$BACKUP_DIR/ssl/etc-pki.tar.gz" -C /etc pki 2>/dev/null || true

echo -e "${GREEN}✓${NC} SSL certificates backed up"

#-------------------------------------------------------------------------------
# Backup Mail
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[9/10] Backing up mail data...${NC}"

if [ -d /var/mail ]; then
    tar -czf "$BACKUP_DIR/mail/var-mail.tar.gz" -C /var mail 2>/dev/null || true
fi

if [ -d /var/spool/mail ]; then
    tar -czf "$BACKUP_DIR/mail/spool-mail.tar.gz" -C /var/spool mail 2>/dev/null || true
fi

# Mail aliases
cp /etc/aliases "$BACKUP_DIR/mail/" 2>/dev/null || true

echo -e "${GREEN}✓${NC} Mail backed up"

#-------------------------------------------------------------------------------
# Backup Cron Jobs
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[10/10] Backing up cron jobs...${NC}"

cp /etc/crontab "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.d "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.daily "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.hourly "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.weekly "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.monthly "$BACKUP_DIR/cron/" 2>/dev/null || true

# User crontabs
mkdir -p "$BACKUP_DIR/cron/users"
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -l -u "$user" > "$BACKUP_DIR/cron/users/${user}.cron" 2>/dev/null || true
done

echo -e "${GREEN}✓${NC} Cron jobs backed up"

#-------------------------------------------------------------------------------
# Create manifest
#-------------------------------------------------------------------------------
cat << EOF > "$BACKUP_DIR/MANIFEST.txt"
================================================================================
                    FULL MIGRATION BACKUP MANIFEST
================================================================================

Created: $(date)
Source Server: $(hostname) - $(hostname -I | awk '{print $1}')
Source OS: $(cat /etc/redhat-release)
Target Server: $NEW_SERVER_IP (temporary storage)

BACKUP CONTENTS:
----------------
virtualmin/     - Virtualmin domain backups (most important!)
mysql/          - All databases and grants
home/           - All home directories
www/            - /var/www content
config/         - System configurations
ssl/            - SSL certificates
mail/           - Mail data
cron/           - Cron jobs

DOMAINS BACKED UP:
------------------
$(cat "$BACKUP_DIR/virtualmin/domain-list.txt" 2>/dev/null || echo "None")

BACKUP SIZES:
-------------
$(du -sh "$BACKUP_DIR"/* 2>/dev/null)

TOTAL SIZE: $(du -sh "$BACKUP_DIR" | awk '{print $1}')

================================================================================
EOF

#-------------------------------------------------------------------------------
# Transfer to new server
#-------------------------------------------------------------------------------
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  TRANSFERRING TO NEW SERVER: $NEW_SERVER_IP${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "Total data to transfer: $TOTAL_SIZE"
echo "This may take a while depending on your connection speed..."
echo ""

log "Starting transfer to $NEW_SERVER_IP"

# Use rsync for efficient transfer with progress
rsync -avz --progress --human-readable \
    "$BACKUP_DIR/" \
    "${NEW_SERVER_USER}@${NEW_SERVER_IP}:${REMOTE_BACKUP_DIR}/"

RSYNC_STATUS=$?

if [ $RSYNC_STATUS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           BACKUP & TRANSFER COMPLETE!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    log "Transfer completed successfully"
else
    echo ""
    echo -e "${RED}WARNING: Transfer may have had issues (exit code: $RSYNC_STATUS)${NC}"
    log "Transfer completed with warnings"
fi

echo ""
echo "Backup stored on new server at: ${NEW_SERVER_IP}:${REMOTE_BACKUP_DIR}"
echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                      NEXT STEPS                              ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║  1. VERIFY backup on new server:                             ║${NC}"
echo -e "${YELLOW}║     ssh root@$NEW_SERVER_IP 'ls -la ${REMOTE_BACKUP_DIR}'${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║  2. FRESH INSTALL AlmaLinux 8 on THIS server                 ║${NC}"
echo -e "${YELLOW}║     (through your hosting provider's control panel)          ║${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║  3. After fresh install, copy scripts to this server and run:║${NC}"
echo -e "${YELLOW}║     ./03-setup-fresh-almalinux.sh                            ║${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║  4. Then restore with:                                       ║${NC}"
echo -e "${YELLOW}║     ./02-restore-from-new-server.sh $NEW_SERVER_IP${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Save transfer info for later
cat << EOF > /root/migration-transfer-info.txt
NEW_SERVER_IP=$NEW_SERVER_IP
REMOTE_BACKUP_DIR=$REMOTE_BACKUP_DIR
BACKUP_DATE=$(date)
EOF

echo "Transfer info saved to /root/migration-transfer-info.txt"
echo ""
