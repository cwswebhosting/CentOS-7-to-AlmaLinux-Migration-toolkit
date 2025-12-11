#!/bin/bash
#===============================================================================
# Script: 06-restore-migration.sh
# Purpose: Restore backups from CentOS 7 to new AlmaLinux 8 server
# Author: Migration Toolkit
# Usage: sudo ./06-restore-migration.sh [backup_directory]
#
# RUN THIS ON THE NEW ALMALINUX 8 SERVER
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default backup location
BACKUP_DIR="${1:-/root/migration-restore}"
LOG_FILE="/root/restore-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          MIGRATION RESTORE SCRIPT                            ║${NC}"
echo -e "${BLUE}║          Looking for backups in: $BACKUP_DIR${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Check prerequisites
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/7] Checking Prerequisites${NC}"
echo "=============================="

# Check if root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}ERROR: Backup directory not found: $BACKUP_DIR${NC}"
    echo ""
    echo "Please copy backups from the old server first:"
    echo "  scp -r root@OLD_SERVER:/root/migration-backup/* $BACKUP_DIR/"
    exit 1
fi

# Check if Virtualmin is installed
if ! command -v virtualmin &> /dev/null; then
    echo -e "${RED}ERROR: Virtualmin is not installed${NC}"
    echo "Please run 05-new-server-setup.sh first"
    exit 1
fi

echo -e "${GREEN}✓${NC} Prerequisites met"
log "Starting restore process"

#-------------------------------------------------------------------------------
# Find backup files
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[2/7] Finding Backup Files${NC}"
echo "==========================="

# Find Virtualmin backups
VIRTUALMIN_BACKUP=$(find "$BACKUP_DIR" -name "virtualmin-backup-*" -type d 2>/dev/null | head -1)
FULL_BACKUP=$(find "$BACKUP_DIR" -name "full-backup-*" -type d 2>/dev/null | head -1)

echo "Found backups:"
if [ -n "$VIRTUALMIN_BACKUP" ]; then
    echo -e "  ${GREEN}✓${NC} Virtualmin backup: $VIRTUALMIN_BACKUP"
fi
if [ -n "$FULL_BACKUP" ]; then
    echo -e "  ${GREEN}✓${NC} Full backup: $FULL_BACKUP"
fi

if [ -z "$VIRTUALMIN_BACKUP" ] && [ -z "$FULL_BACKUP" ]; then
    echo -e "${RED}No backup directories found in $BACKUP_DIR${NC}"
    echo "Looking for individual backup files..."
    ls -la "$BACKUP_DIR"
    exit 1
fi

#-------------------------------------------------------------------------------
# Restore Virtualmin Domains
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/7] Restoring Virtualmin Domains${NC}"
echo "===================================="

if [ -n "$VIRTUALMIN_BACKUP" ]; then
    DOMAINS_DIR="$VIRTUALMIN_BACKUP/domains"
    
    if [ -d "$DOMAINS_DIR" ]; then
        echo "Found domain backups in: $DOMAINS_DIR"
        echo ""
        
        # List available domains
        echo "Available domains to restore:"
        ls "$DOMAINS_DIR"/*.tar.gz 2>/dev/null | while read backup; do
            domain=$(basename "$backup" .tar.gz)
            echo "  - $domain"
        done
        
        echo ""
        read -p "Restore all domains? (y/n): " restore_all
        
        if [[ "$restore_all" =~ ^[Yy]$ ]]; then
            # Check for combined backup first
            if [ -f "$VIRTUALMIN_BACKUP/all-domains-backup.tar.gz" ]; then
                echo "Using combined backup file..."
                log "Restoring from all-domains-backup.tar.gz"
                
                virtualmin restore-domain \
                    --source "$VIRTUALMIN_BACKUP/all-domains-backup.tar.gz" \
                    --all-domains \
                    --all-features \
                    2>&1 | tee -a "$LOG_FILE"
            else
                # Restore individual domains
                for backup in "$DOMAINS_DIR"/*.tar.gz; do
                    if [ -f "$backup" ]; then
                        domain=$(basename "$backup" .tar.gz)
                        echo ""
                        echo -e "Restoring: ${BLUE}$domain${NC}"
                        log "Restoring domain: $domain"
                        
                        virtualmin restore-domain \
                            --source "$backup" \
                            --all-features \
                            2>&1 | tee -a "$LOG_FILE" || log "WARNING: Issues restoring $domain"
                    fi
                done
            fi
        else
            # Restore selected domains
            for backup in "$DOMAINS_DIR"/*.tar.gz; do
                if [ -f "$backup" ]; then
                    domain=$(basename "$backup" .tar.gz)
                    read -p "Restore $domain? (y/n): " restore_domain
                    
                    if [[ "$restore_domain" =~ ^[Yy]$ ]]; then
                        echo "Restoring $domain..."
                        log "Restoring domain: $domain"
                        
                        virtualmin restore-domain \
                            --source "$backup" \
                            --all-features \
                            2>&1 | tee -a "$LOG_FILE" || log "WARNING: Issues restoring $domain"
                    fi
                fi
            done
        fi
    fi
fi

echo -e "${GREEN}✓${NC} Domain restoration complete"

#-------------------------------------------------------------------------------
# Restore Additional MySQL Databases
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/7] Checking for Additional Databases${NC}"
echo "========================================="

if [ -n "$FULL_BACKUP" ] && [ -d "$FULL_BACKUP/mysql" ]; then
    echo "Found MySQL backup in: $FULL_BACKUP/mysql"
    
    # Check for databases not handled by Virtualmin
    if [ -f "$FULL_BACKUP/mysql/all-databases.sql.gz" ]; then
        echo ""
        echo "Full database dump found. Virtualmin domains include their databases."
        echo "Only restore this if you have non-Virtualmin databases."
        read -p "Restore full database dump? (y/n): " restore_db
        
        if [[ "$restore_db" =~ ^[Yy]$ ]]; then
            echo "Restoring databases..."
            log "Restoring all-databases.sql.gz"
            gunzip < "$FULL_BACKUP/mysql/all-databases.sql.gz" | mysql 2>&1 | tee -a "$LOG_FILE" || true
        fi
    fi
fi

echo -e "${GREEN}✓${NC} Database check complete"

#-------------------------------------------------------------------------------
# Restore SSL Certificates
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/7] Restoring SSL Certificates${NC}"
echo "=================================="

# Let's Encrypt certificates
if [ -n "$FULL_BACKUP" ] && [ -f "$FULL_BACKUP/ssl/letsencrypt.tar.gz" ]; then
    echo "Found Let's Encrypt backup"
    read -p "Restore Let's Encrypt certificates? (y/n): " restore_ssl
    
    if [[ "$restore_ssl" =~ ^[Yy]$ ]]; then
        log "Restoring Let's Encrypt certificates"
        
        # Backup current (if exists)
        if [ -d /etc/letsencrypt ]; then
            mv /etc/letsencrypt /etc/letsencrypt.bak.$(date +%s) 2>/dev/null || true
        fi
        
        # Restore
        tar -xzf "$FULL_BACKUP/ssl/letsencrypt.tar.gz" -C /etc
        
        # Fix permissions
        chmod -R 755 /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
        
        echo -e "${GREEN}✓${NC} Let's Encrypt certificates restored"
        echo ""
        echo -e "${YELLOW}NOTE: You may need to renew certificates for the new server IP${NC}"
        echo "Run: certbot renew --dry-run"
    fi
else
    echo "No Let's Encrypt backup found"
    echo "You can request new certificates after DNS is updated:"
    echo "  virtualmin generate-letsencrypt-cert --domain DOMAIN"
fi

#-------------------------------------------------------------------------------
# Restore Additional Configurations
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/7] Additional Configuration Restore${NC}"
echo "========================================"

if [ -n "$VIRTUALMIN_BACKUP" ] && [ -d "$VIRTUALMIN_BACKUP/additional" ]; then
    echo "Found additional configuration backups"
    
    # DKIM
    if [ -f "$VIRTUALMIN_BACKUP/additional/opendkim.tar.gz" ]; then
        read -p "Restore DKIM configuration? (y/n): " restore_dkim
        if [[ "$restore_dkim" =~ ^[Yy]$ ]]; then
            tar -xzf "$VIRTUALMIN_BACKUP/additional/opendkim.tar.gz" -C /etc
            systemctl restart opendkim 2>/dev/null || true
            echo -e "${GREEN}✓${NC} DKIM restored"
        fi
    fi
    
    # Fail2ban
    if [ -f "$VIRTUALMIN_BACKUP/additional/fail2ban.tar.gz" ]; then
        read -p "Restore fail2ban configuration? (y/n): " restore_f2b
        if [[ "$restore_f2b" =~ ^[Yy]$ ]]; then
            tar -xzf "$VIRTUALMIN_BACKUP/additional/fail2ban.tar.gz" -C /etc
            systemctl restart fail2ban 2>/dev/null || true
            echo -e "${GREEN}✓${NC} Fail2ban restored"
        fi
    fi
fi

#-------------------------------------------------------------------------------
# Validate and Restart Services
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/7] Validating and Restarting Services${NC}"
echo "==========================================="

# Validate domains
echo "Validating restored domains..."
virtualmin list-domains --name-only 2>/dev/null | while read domain; do
    if [ -n "$domain" ]; then
        echo "  Validating: $domain"
        virtualmin validate-domains --domain "$domain" --all-features 2>&1 | grep -E "^  |PASS|FAIL" | head -5
    fi
done

# Restart services
echo ""
echo "Restarting services..."

systemctl restart httpd
systemctl restart mariadb
systemctl restart postfix
systemctl restart dovecot
systemctl restart webmin 2>/dev/null || true

echo -e "${GREEN}✓${NC} Services restarted"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              RESTORE COMPLETE                                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Restored Domains:"
virtualmin list-domains --name-only 2>/dev/null | while read domain; do
    if [ -n "$domain" ]; then
        echo "  - $domain"
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
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo "1. Test websites by adding to your local /etc/hosts:"
echo "   $SERVER_IP  yourdomain.com www.yourdomain.com"
echo ""
echo "2. Test email delivery (send test emails)"
echo ""
echo "3. When ready, update DNS records to point to: $SERVER_IP"
echo ""
echo "4. Run verification script:"
echo "   ./07-post-migration-verify.sh"
echo ""
echo "5. Request new SSL certificates if needed:"
echo "   virtualmin generate-letsencrypt-cert --domain DOMAIN --renew"
echo ""

log "Restore process complete"
