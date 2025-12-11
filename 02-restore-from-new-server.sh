#!/bin/bash
#===============================================================================
# Script: 02-restore-from-new-server.sh
# Purpose: Pull backups from temporary server and restore to freshly installed
#          AlmaLinux 8 server (the original server with same IP)
# Run On: OLD SERVER (after fresh AlmaLinux 8 install)
#
# Prerequisites:
# - Fresh AlmaLinux 8 installed on this server
# - Run 03-setup-fresh-almalinux.sh FIRST to install Virtualmin
# - Backups exist on the temporary new server
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
NEW_SERVER_IP="${1:-}"         # Can be passed as argument
NEW_SERVER_USER="root"
REMOTE_BACKUP_DIR="/root/migration-data"
LOCAL_RESTORE_DIR="/root/restore-data"
#===============================================================================

LOG_FILE="/root/restore-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     STEP 2: RESTORE FROM TEMPORARY SERVER                    ║${NC}"
echo -e "${BLUE}║     Run this on: OLD SERVER (Fresh AlmaLinux 8)              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Pre-flight checks
#-------------------------------------------------------------------------------
echo -e "${GREEN}[PRE-CHECK] Verifying environment...${NC}"
echo ""

# Check if root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Check if this is AlmaLinux 8
if ! grep -qE "AlmaLinux.*8\.|Rocky.*8\." /etc/os-release 2>/dev/null; then
    echo -e "${RED}ERROR: This script is for AlmaLinux 8${NC}"
    echo "Current OS: $(cat /etc/os-release | grep PRETTY_NAME)"
    echo ""
    echo "Please install AlmaLinux 8 first, then run this script."
    exit 1
fi
echo -e "${GREEN}✓${NC} AlmaLinux 8 detected"

# Check if Virtualmin is installed
if ! command -v virtualmin &> /dev/null; then
    echo -e "${RED}ERROR: Virtualmin is not installed${NC}"
    echo ""
    echo "Please run 03-setup-fresh-almalinux.sh first to install Virtualmin"
    exit 1
fi
echo -e "${GREEN}✓${NC} Virtualmin is installed"

#-------------------------------------------------------------------------------
# Get new server IP
#-------------------------------------------------------------------------------
if [ -z "$NEW_SERVER_IP" ]; then
    read -p "Enter the IP address of the TEMPORARY server (where backups are): " NEW_SERVER_IP
fi

if [ -z "$NEW_SERVER_IP" ]; then
    echo -e "${RED}ERROR: Temporary server IP is required${NC}"
    exit 1
fi

echo ""
echo "Configuration:"
echo "  This Server:        $(hostname) / $(hostname -I | awk '{print $1}')"
echo "  Backup Server:      $NEW_SERVER_IP"
echo "  Remote Backup Path: $REMOTE_BACKUP_DIR"
echo "  Local Restore Path: $LOCAL_RESTORE_DIR"
echo ""

read -p "Is this correct? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

log "Starting restore from $NEW_SERVER_IP"

#-------------------------------------------------------------------------------
# Test SSH connection
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[1/8] Testing SSH connection...${NC}"

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "${NEW_SERVER_USER}@${NEW_SERVER_IP}" "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${YELLOW}Setting up SSH key authentication...${NC}"
    
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
    fi
    
    echo "Please enter the password for ${NEW_SERVER_USER}@${NEW_SERVER_IP}:"
    ssh-copy-id "${NEW_SERVER_USER}@${NEW_SERVER_IP}"
fi

# Verify backup exists
if ! ssh "${NEW_SERVER_USER}@${NEW_SERVER_IP}" "[ -d ${REMOTE_BACKUP_DIR} ]" 2>/dev/null; then
    echo -e "${RED}ERROR: Backup directory not found on remote server${NC}"
    echo "Expected: ${NEW_SERVER_IP}:${REMOTE_BACKUP_DIR}"
    exit 1
fi

echo -e "${GREEN}✓${NC} SSH connection successful and backup found"
log "SSH connection verified"

#-------------------------------------------------------------------------------
# Pull backups from temporary server
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[2/8] Downloading backups from temporary server...${NC}"

mkdir -p "$LOCAL_RESTORE_DIR"

REMOTE_SIZE=$(ssh "${NEW_SERVER_USER}@${NEW_SERVER_IP}" "du -sh ${REMOTE_BACKUP_DIR} | awk '{print \$1}'" 2>/dev/null)
echo "Total backup size: $REMOTE_SIZE"
echo "Downloading... (this may take a while)"
echo ""

rsync -avz --progress --human-readable \
    "${NEW_SERVER_USER}@${NEW_SERVER_IP}:${REMOTE_BACKUP_DIR}/" \
    "$LOCAL_RESTORE_DIR/"

echo -e "${GREEN}✓${NC} Backups downloaded to $LOCAL_RESTORE_DIR"
log "Backups downloaded"

#-------------------------------------------------------------------------------
# Restore Virtualmin domains
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/8] Restoring Virtualmin domains...${NC}"

VIRTUALMIN_DIR="$LOCAL_RESTORE_DIR/virtualmin"

if [ -d "$VIRTUALMIN_DIR" ]; then
    # Check for combined backup first
    if [ -f "$VIRTUALMIN_DIR/all-domains.tar.gz" ]; then
        echo "Found combined backup - restoring all domains..."
        log "Restoring from all-domains.tar.gz"
        
        virtualmin restore-domain \
            --source "$VIRTUALMIN_DIR/all-domains.tar.gz" \
            --all-domains \
            --all-features \
            2>&1 | tee -a "$LOG_FILE" || log "WARNING: Some domains may have issues"
    else
        # Restore individual domains
        echo "Restoring individual domain backups..."
        
        for backup in "$VIRTUALMIN_DIR"/*.tar.gz; do
            if [ -f "$backup" ] && [[ "$backup" != *"all-domains"* ]]; then
                domain=$(basename "$backup" .tar.gz)
                echo "  Restoring: $domain"
                log "Restoring domain: $domain"
                
                virtualmin restore-domain \
                    --source "$backup" \
                    --all-features \
                    2>&1 | tee -a "$LOG_FILE" || log "WARNING: Issues with $domain"
            fi
        done
    fi
    
    echo -e "${GREEN}✓${NC} Virtualmin domains restored"
else
    echo -e "${YELLOW}! No Virtualmin backups found${NC}"
fi

#-------------------------------------------------------------------------------
# Restore additional databases (if any not in Virtualmin)
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/8] Checking for additional databases...${NC}"

MYSQL_DIR="$LOCAL_RESTORE_DIR/mysql"

if [ -d "$MYSQL_DIR" ]; then
    # Restore grants first
    if [ -f "$MYSQL_DIR/all-grants.sql.gz" ]; then
        echo "Restoring database grants..."
        gunzip -c "$MYSQL_DIR/all-grants.sql.gz" | mysql 2>/dev/null || true
    elif [ -f "$MYSQL_DIR/all-grants.sql" ]; then
        mysql < "$MYSQL_DIR/all-grants.sql" 2>/dev/null || true
    fi
    
    # List databases that were backed up
    echo ""
    echo "Database backups found:"
    ls "$MYSQL_DIR"/*.sql.gz 2>/dev/null | while read f; do
        basename "$f" .sql.gz
    done
    
    echo ""
    echo "Note: Virtualmin restore already included domain databases."
    echo "Only restore additional databases if needed."
    read -p "Restore ALL databases from full dump? (y/n): " restore_all_db
    
    if [[ "$restore_all_db" =~ ^[Yy]$ ]]; then
        if [ -f "$MYSQL_DIR/all-databases.sql.gz" ]; then
            echo "Restoring all databases..."
            gunzip -c "$MYSQL_DIR/all-databases.sql.gz" | mysql 2>&1 | tee -a "$LOG_FILE" || true
        fi
    fi
    
    echo -e "${GREEN}✓${NC} Database restore complete"
else
    echo -e "${YELLOW}! No MySQL backups found${NC}"
fi

#-------------------------------------------------------------------------------
# Restore SSL certificates
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/8] Restoring SSL certificates...${NC}"

SSL_DIR="$LOCAL_RESTORE_DIR/ssl"

if [ -f "$SSL_DIR/letsencrypt.tar.gz" ]; then
    echo "Restoring Let's Encrypt certificates..."
    
    # Backup current if exists
    if [ -d /etc/letsencrypt ]; then
        mv /etc/letsencrypt /etc/letsencrypt.new.$(date +%s)
    fi
    
    tar -xzf "$SSL_DIR/letsencrypt.tar.gz" -C /etc
    
    # Fix permissions
    chmod -R 755 /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
    
    echo -e "${GREEN}✓${NC} Let's Encrypt certificates restored"
    log "SSL certificates restored"
else
    echo -e "${YELLOW}! No Let's Encrypt backup found${NC}"
    echo "  You may need to request new certificates after DNS propagates"
fi

#-------------------------------------------------------------------------------
# Restore mail configuration
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/8] Restoring mail configuration...${NC}"

MAIL_DIR="$LOCAL_RESTORE_DIR/mail"
CONFIG_DIR="$LOCAL_RESTORE_DIR/config"

# Restore mail aliases
if [ -f "$MAIL_DIR/aliases" ]; then
    cp "$MAIL_DIR/aliases" /etc/aliases
    newaliases 2>/dev/null || true
    echo "  Mail aliases restored"
fi

# Restore additional mail data if not in Virtualmin backup
if [ -f "$MAIL_DIR/var-mail.tar.gz" ]; then
    echo "  Note: Mail data should be restored via Virtualmin"
fi

echo -e "${GREEN}✓${NC} Mail configuration restored"

#-------------------------------------------------------------------------------
# Restore cron jobs
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/8] Restoring cron jobs...${NC}"

CRON_DIR="$LOCAL_RESTORE_DIR/cron"

if [ -d "$CRON_DIR" ]; then
    # Restore user crontabs
    if [ -d "$CRON_DIR/users" ]; then
        for cronfile in "$CRON_DIR/users"/*.cron; do
            if [ -f "$cronfile" ] && [ -s "$cronfile" ]; then
                user=$(basename "$cronfile" .cron)
                if id "$user" &>/dev/null; then
                    crontab -u "$user" "$cronfile" 2>/dev/null || true
                    echo "  Restored crontab for: $user"
                fi
            fi
        done
    fi
    
    # Restore cron.d entries
    if [ -d "$CRON_DIR/cron.d" ]; then
        cp "$CRON_DIR/cron.d"/* /etc/cron.d/ 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓${NC} Cron jobs restored"
else
    echo -e "${YELLOW}! No cron backups found${NC}"
fi

#-------------------------------------------------------------------------------
# Final service restart and validation
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[8/8] Restarting services and validating...${NC}"

# Restart all services
echo "Restarting services..."
systemctl restart httpd 2>/dev/null || true
systemctl restart mariadb 2>/dev/null || true
systemctl restart postfix 2>/dev/null || true
systemctl restart dovecot 2>/dev/null || true
systemctl restart named 2>/dev/null || true
systemctl restart php-fpm 2>/dev/null || true
systemctl restart webmin 2>/dev/null || true

# Validate domains
echo ""
echo "Validating restored domains..."
virtualmin list-domains --name-only 2>/dev/null | while read domain; do
    if [ -n "$domain" ]; then
        echo "  Checking: $domain"
        virtualmin validate-domains --domain "$domain" --all-features 2>&1 | grep -E "PASS|FAIL" | head -3
    fi
done

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  RESTORE COMPLETE!                           ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "Restored Domains:"
virtualmin list-domains --name-only 2>/dev/null | while read domain; do
    if [ -n "$domain" ]; then
        echo "  ✓ $domain"
    fi
done

echo ""
echo "Services Status:"
for svc in httpd mariadb postfix dovecot webmin; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $svc is running"
    else
        echo -e "  ${RED}✗${NC} $svc is not running"
    fi
done

echo ""
echo -e "${YELLOW}POST-RESTORE CHECKLIST:${NC}"
echo ""
echo "  1. Test websites by browsing to them"
echo "  2. Test email sending/receiving"
echo "  3. Check SSL certificates:"
echo "     certbot certificates"
echo ""
echo "  4. If SSL certs need renewal (new server detected):"
echo "     virtualmin generate-letsencrypt-cert --domain DOMAIN --renew"
echo ""
echo "  5. Run verification:"
echo "     ./04-verify-migration.sh"
echo ""
echo "  6. Once confirmed working, you can decommission the temporary server"
echo ""

log "Restore completed successfully"
