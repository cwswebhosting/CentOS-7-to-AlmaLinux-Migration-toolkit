#!/bin/bash
#===============================================================================
# Script: 02-full-backup.sh
# Purpose: Create comprehensive backup of CentOS 7 server before migration
# Author: Migration Toolkit
# Usage: sudo ./02-full-backup.sh [backup_destination]
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
BACKUP_DIR="$BACKUP_BASE/full-backup-$TIMESTAMP"
LOG_FILE="$BACKUP_DIR/backup.log"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           FULL SYSTEM BACKUP SCRIPT                          ║${NC}"
echo -e "${BLUE}║           Backup Directory: $BACKUP_DIR${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Starting full system backup..."

#-------------------------------------------------------------------------------
# Check disk space
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[1/10] Checking disk space...${NC}"

# Estimate required space
ESTIMATED_SIZE=$(du -s /home /var/www /var/lib/mysql /etc 2>/dev/null | awk '{sum+=$1} END {print sum}')
ESTIMATED_GB=$((ESTIMATED_SIZE / 1024 / 1024))
AVAILABLE=$(df "$BACKUP_BASE" | awk 'NR==2 {print $4}')
AVAILABLE_GB=$((AVAILABLE / 1024 / 1024))

log "Estimated backup size: ${ESTIMATED_GB}GB"
log "Available space: ${AVAILABLE_GB}GB"

if [ "$AVAILABLE" -lt "$ESTIMATED_SIZE" ]; then
    echo -e "${RED}⚠ WARNING: May not have enough space for backup!${NC}"
    echo "Estimated need: ${ESTIMATED_GB}GB, Available: ${AVAILABLE_GB}GB"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

#-------------------------------------------------------------------------------
# Stop services (optional - comment out for hot backup)
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[2/10] Preparing for backup...${NC}"

read -p "Stop services for consistent backup? (recommended) (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Stopping services..."
    systemctl stop httpd 2>/dev/null || true
    systemctl stop postfix 2>/dev/null || true
    systemctl stop dovecot 2>/dev/null || true
    # MariaDB will use mysqldump instead of stopping
    SERVICES_STOPPED=true
else
    SERVICES_STOPPED=false
fi

#-------------------------------------------------------------------------------
# Backup MariaDB/MySQL
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[3/10] Backing up MariaDB databases...${NC}"
mkdir -p "$BACKUP_DIR/mysql"

log "Creating MySQL dump..."

# Try to dump all databases
if mysqldump --all-databases --single-transaction --routines --triggers \
   --events > "$BACKUP_DIR/mysql/all-databases.sql" 2>/dev/null; then
    log "Full database dump created successfully"
    gzip "$BACKUP_DIR/mysql/all-databases.sql"
    log "Database dump compressed"
else
    log "Full dump failed, trying individual databases..."
    
    # Dump each database individually
    for db in $(mysql -e "SHOW DATABASES;" -s --skip-column-names 2>/dev/null | grep -v "^information_schema$\|^performance_schema$\|^mysql$\|^sys$"); do
        log "Dumping database: $db"
        mysqldump --single-transaction --routines --triggers "$db" \
            > "$BACKUP_DIR/mysql/$db.sql" 2>/dev/null && gzip "$BACKUP_DIR/mysql/$db.sql" || \
            log "WARNING: Could not dump $db"
    done
fi

# Backup MySQL users and grants
log "Backing up MySQL users and grants..."
mysql -e "SELECT CONCAT('CREATE USER IF NOT EXISTS ''',user,'''@''',host,''' IDENTIFIED BY PASSWORD ''',authentication_string,''';') FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session');" 2>/dev/null > "$BACKUP_DIR/mysql/users.sql" || true
mysql -e "SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user NOT IN ('root','mysql.sys','mysql.session');" 2>/dev/null | while read line; do
    mysql -e "$line" 2>/dev/null >> "$BACKUP_DIR/mysql/grants.sql" || true
done

# Copy MySQL configuration
cp /etc/my.cnf "$BACKUP_DIR/mysql/" 2>/dev/null || true
cp -r /etc/my.cnf.d "$BACKUP_DIR/mysql/" 2>/dev/null || true

DB_SIZE=$(du -sh "$BACKUP_DIR/mysql" | awk '{print $1}')
log "MySQL backup complete: $DB_SIZE"

#-------------------------------------------------------------------------------
# Backup Home Directories
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[4/10] Backing up home directories...${NC}"
mkdir -p "$BACKUP_DIR/home"

log "Backing up /home..."
tar -czf "$BACKUP_DIR/home/home.tar.gz" -C / home \
    --exclude='*.log' \
    --exclude='*/cache/*' \
    --exclude='*/.cache/*' \
    --exclude='*/tmp/*' \
    2>/dev/null || log "WARNING: Some files in /home could not be backed up"

HOME_SIZE=$(du -sh "$BACKUP_DIR/home" | awk '{print $1}')
log "Home backup complete: $HOME_SIZE"

#-------------------------------------------------------------------------------
# Backup Web Content
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[5/10] Backing up web content...${NC}"
mkdir -p "$BACKUP_DIR/www"

if [ -d /var/www ]; then
    log "Backing up /var/www..."
    tar -czf "$BACKUP_DIR/www/var-www.tar.gz" -C /var www 2>/dev/null || \
        log "WARNING: Some files in /var/www could not be backed up"
fi

WWW_SIZE=$(du -sh "$BACKUP_DIR/www" | awk '{print $1}')
log "Web content backup complete: $WWW_SIZE"

#-------------------------------------------------------------------------------
# Backup Configuration Files
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[6/10] Backing up configuration files...${NC}"
mkdir -p "$BACKUP_DIR/config"

log "Backing up /etc..."
tar -czf "$BACKUP_DIR/config/etc.tar.gz" -C / etc 2>/dev/null

# Individual important configs
mkdir -p "$BACKUP_DIR/config/individual"
cp -r /etc/httpd "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/postfix "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/dovecot "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/webmin "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/usermin "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/letsencrypt "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/ssl "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/pki "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/php.ini "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/php.d "$BACKUP_DIR/config/individual/" 2>/dev/null || true
cp -r /etc/php-fpm.d "$BACKUP_DIR/config/individual/" 2>/dev/null || true

CONFIG_SIZE=$(du -sh "$BACKUP_DIR/config" | awk '{print $1}')
log "Configuration backup complete: $CONFIG_SIZE"

#-------------------------------------------------------------------------------
# Backup SSL Certificates
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[7/10] Backing up SSL certificates...${NC}"
mkdir -p "$BACKUP_DIR/ssl"

if [ -d /etc/letsencrypt ]; then
    log "Backing up Let's Encrypt certificates..."
    tar -czf "$BACKUP_DIR/ssl/letsencrypt.tar.gz" -C /etc letsencrypt 2>/dev/null
fi

# Other SSL locations
for ssldir in /etc/ssl /etc/pki/tls; do
    if [ -d "$ssldir" ]; then
        dirname=$(basename "$ssldir")
        tar -czf "$BACKUP_DIR/ssl/$dirname.tar.gz" -C "$(dirname $ssldir)" "$dirname" 2>/dev/null || true
    fi
done

SSL_SIZE=$(du -sh "$BACKUP_DIR/ssl" | awk '{print $1}')
log "SSL backup complete: $SSL_SIZE"

#-------------------------------------------------------------------------------
# Backup Mail
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[8/10] Backing up mail data...${NC}"
mkdir -p "$BACKUP_DIR/mail"

if [ -d /var/mail ]; then
    log "Backing up /var/mail..."
    tar -czf "$BACKUP_DIR/mail/var-mail.tar.gz" -C /var mail 2>/dev/null || true
fi

# Backup Maildir from home directories (already in home backup, but separate for clarity)
if ls /home/*/Maildir 1>/dev/null 2>&1; then
    log "Mail directories are included in home backup"
fi

# Backup mail configuration
cp /etc/aliases "$BACKUP_DIR/mail/" 2>/dev/null || true
cp /etc/aliases.db "$BACKUP_DIR/mail/" 2>/dev/null || true

MAIL_SIZE=$(du -sh "$BACKUP_DIR/mail" | awk '{print $1}')
log "Mail backup complete: $MAIL_SIZE"

#-------------------------------------------------------------------------------
# Backup Cron Jobs
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[9/10] Backing up cron jobs...${NC}"
mkdir -p "$BACKUP_DIR/cron"

cp /etc/crontab "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.d "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.daily "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.weekly "$BACKUP_DIR/cron/" 2>/dev/null || true
cp -r /etc/cron.monthly "$BACKUP_DIR/cron/" 2>/dev/null || true

# User crontabs
mkdir -p "$BACKUP_DIR/cron/user-crontabs"
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -l -u "$user" > "$BACKUP_DIR/cron/user-crontabs/$user.cron" 2>/dev/null || true
done

log "Cron backup complete"

#-------------------------------------------------------------------------------
# Package List
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}[10/10] Saving package information...${NC}"
mkdir -p "$BACKUP_DIR/packages"

rpm -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > "$BACKUP_DIR/packages/rpm-list.txt"
yum repolist > "$BACKUP_DIR/packages/repos.txt" 2>/dev/null || true
cp -r /etc/yum.repos.d "$BACKUP_DIR/packages/" 2>/dev/null || true

log "Package list saved"

#-------------------------------------------------------------------------------
# Restart services if stopped
#-------------------------------------------------------------------------------
if [ "$SERVICES_STOPPED" = true ]; then
    echo -e "\n${GREEN}Restarting services...${NC}"
    systemctl start httpd 2>/dev/null || true
    systemctl start postfix 2>/dev/null || true
    systemctl start dovecot 2>/dev/null || true
    log "Services restarted"
fi

#-------------------------------------------------------------------------------
# Create manifest
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}Creating backup manifest...${NC}"

cat << EOF > "$BACKUP_DIR/MANIFEST.txt"
╔══════════════════════════════════════════════════════════════════════════════╗
║                         BACKUP MANIFEST                                      ║
╚══════════════════════════════════════════════════════════════════════════════╝

Backup Created: $(date)
Hostname: $(hostname)
Source OS: $(cat /etc/redhat-release)

BACKUP CONTENTS:
================

mysql/
  - all-databases.sql.gz    : Full MySQL/MariaDB dump
  - users.sql               : MySQL users
  - grants.sql              : MySQL grants/permissions
  - my.cnf                  : MySQL configuration

home/
  - home.tar.gz             : All home directories (/home/*)

www/
  - var-www.tar.gz          : Web content (/var/www)

config/
  - etc.tar.gz              : Full /etc backup
  - individual/             : Individual service configs

ssl/
  - letsencrypt.tar.gz      : Let's Encrypt certificates
  - ssl.tar.gz              : /etc/ssl certificates
  - tls.tar.gz              : /etc/pki/tls certificates

mail/
  - var-mail.tar.gz         : Mail spool
  - aliases                 : Mail aliases

cron/
  - crontab                 : System crontab
  - cron.d/                 : Cron.d directory
  - user-crontabs/          : Per-user crontabs

packages/
  - rpm-list.txt            : Installed packages
  - repos.txt               : Enabled repositories
  - yum.repos.d/            : Repository configurations

BACKUP SIZES:
=============
$(du -sh "$BACKUP_DIR"/* | sort -rh)

TOTAL SIZE: $(du -sh "$BACKUP_DIR" | awk '{print $1}')

RESTORE NOTES:
==============
1. MySQL: gunzip < all-databases.sql.gz | mysql
2. Home: tar -xzf home.tar.gz -C /
3. Configs: Extract etc.tar.gz or use individual configs
4. SSL: Restore to same paths on new server

EOF

#-------------------------------------------------------------------------------
# Calculate checksums
#-------------------------------------------------------------------------------
echo -e "\n${GREEN}Calculating checksums...${NC}"
cd "$BACKUP_DIR"
find . -type f -name "*.tar.gz" -o -name "*.sql.gz" | while read file; do
    sha256sum "$file" >> checksums.sha256
done
log "Checksums saved to checksums.sha256"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    BACKUP COMPLETE                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Backup location: ${BLUE}$BACKUP_DIR${NC}"
echo -e "Total size: ${BLUE}$TOTAL_SIZE${NC}"
echo ""
echo "Backup contents:"
du -sh "$BACKUP_DIR"/* | sort -rh
echo ""
echo -e "${YELLOW}IMPORTANT:${NC}"
echo "  1. Copy this backup to external storage immediately"
echo "  2. Verify backup integrity: cd $BACKUP_DIR && sha256sum -c checksums.sha256"
echo "  3. Test database restore on non-production system"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "  1. Run 03-virtualmin-backup.sh for Virtualmin-specific backups"
echo "  2. Transfer backups to new server or external storage"
echo ""

log "Backup completed successfully. Total size: $TOTAL_SIZE"
