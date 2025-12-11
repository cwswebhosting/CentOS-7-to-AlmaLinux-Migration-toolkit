#!/bin/bash
#===============================================================================
# Script: 05-new-server-setup.sh
# Purpose: Set up fresh AlmaLinux 8 server with Virtualmin for migration
# Author: Migration Toolkit
# Usage: sudo ./05-new-server-setup.sh
#
# RUN THIS ON THE NEW ALMALINUX 8 SERVER (not the old CentOS 7 server)
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/server-setup-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     ALMALINUX 8 SERVER SETUP FOR VIRTUALMIN MIGRATION       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Pre-flight checks
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/8] Pre-flight Checks${NC}"
echo "========================"

# Check if root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Check OS version
if ! grep -qE "AlmaLinux.*8\.|Rocky.*8\.|Red Hat.*8\." /etc/os-release 2>/dev/null; then
    echo -e "${YELLOW}WARNING: This script is intended for AlmaLinux/Rocky/RHEL 8${NC}"
    cat /etc/os-release | grep PRETTY_NAME
    read -p "Continue anyway? (y/n): " cont
    if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo -e "${GREEN}✓${NC} AlmaLinux 8 compatible OS detected"

# Get hostname
echo ""
read -p "Enter the FQDN hostname for this server (e.g., server.example.com): " NEW_HOSTNAME
if [ -z "$NEW_HOSTNAME" ]; then
    echo -e "${RED}Hostname is required${NC}"
    exit 1
fi

log "Starting server setup for $NEW_HOSTNAME"

#-------------------------------------------------------------------------------
# Phase 1: System Update
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[2/8] System Update${NC}"
echo "===================="

log "Updating system packages"

dnf update -y 2>&1 | tee -a "$LOG_FILE"
dnf install -y epel-release 2>&1 | tee -a "$LOG_FILE"
dnf install -y wget curl tar gzip nano vim htop 2>&1 | tee -a "$LOG_FILE"

echo -e "${GREEN}✓${NC} System updated"

#-------------------------------------------------------------------------------
# Phase 2: Set Hostname
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/8] Configure Hostname${NC}"
echo "========================="

hostnamectl set-hostname "$NEW_HOSTNAME"
echo "$NEW_HOSTNAME" > /etc/hostname

# Add to hosts file if not present
if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1   $NEW_HOSTNAME $(echo $NEW_HOSTNAME | cut -d. -f1)" >> /etc/hosts
fi

log "Hostname set to $NEW_HOSTNAME"
echo -e "${GREEN}✓${NC} Hostname configured: $NEW_HOSTNAME"

#-------------------------------------------------------------------------------
# Phase 3: Configure Firewall
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/8] Configure Firewall${NC}"
echo "========================="

# Enable firewalld
systemctl enable firewalld
systemctl start firewalld

# Add necessary ports
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=smtp
firewall-cmd --permanent --add-service=smtps
firewall-cmd --permanent --add-service=imap
firewall-cmd --permanent --add-service=imaps
firewall-cmd --permanent --add-service=pop3
firewall-cmd --permanent --add-service=pop3s
firewall-cmd --permanent --add-port=10000/tcp  # Webmin
firewall-cmd --permanent --add-port=20000/tcp  # Usermin
firewall-cmd --permanent --add-port=53/tcp     # DNS
firewall-cmd --permanent --add-port=53/udp     # DNS
firewall-cmd --permanent --add-service=ftp
firewall-cmd --reload

log "Firewall configured"
echo -e "${GREEN}✓${NC} Firewall configured"

#-------------------------------------------------------------------------------
# Phase 4: Install Virtualmin
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/8] Install Virtualmin${NC}"
echo "========================="

log "Downloading Virtualmin installer"

cd /root
wget -q https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh -O virtualmin-install.sh

echo ""
echo "Virtualmin installation options:"
echo "  1. Full LAMP stack (Apache, MariaDB, PHP, etc.) - Recommended"
echo "  2. Minimal installation"
echo ""
read -p "Choose option (1 or 2): " install_option

chmod +x virtualmin-install.sh

log "Running Virtualmin installer"

if [ "$install_option" == "2" ]; then
    echo "Installing Virtualmin (minimal)..."
    ./virtualmin-install.sh --minimal 2>&1 | tee -a "$LOG_FILE"
else
    echo "Installing Virtualmin (full LAMP stack)..."
    echo "This will take 10-20 minutes..."
    ./virtualmin-install.sh --bundle LAMP 2>&1 | tee -a "$LOG_FILE"
fi

log "Virtualmin installation complete"
echo -e "${GREEN}✓${NC} Virtualmin installed"

#-------------------------------------------------------------------------------
# Phase 5: Configure MariaDB
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/8] Configure MariaDB${NC}"
echo "========================"

# Start MariaDB
systemctl enable mariadb
systemctl start mariadb

# Secure MariaDB
echo ""
echo "Securing MariaDB installation..."
echo "Please set a strong root password when prompted."
echo ""

mysql_secure_installation 2>&1 || true

log "MariaDB configured"
echo -e "${GREEN}✓${NC} MariaDB configured"

#-------------------------------------------------------------------------------
# Phase 6: Configure PHP
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/8] Configure PHP${NC}"
echo "===================="

# Install additional PHP modules commonly needed
dnf install -y php-gd php-mbstring php-xml php-json php-curl php-zip php-intl 2>&1 | tee -a "$LOG_FILE" || true

# Optimize PHP settings
PHP_INI=$(php -i | grep "Loaded Configuration File" | awk '{print $5}')
if [ -f "$PHP_INI" ]; then
    # Increase limits
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/max_input_time = .*/max_input_time = 300/' "$PHP_INI"
fi

systemctl restart httpd php-fpm 2>/dev/null || systemctl restart httpd

log "PHP configured"
echo -e "${GREEN}✓${NC} PHP configured"

#-------------------------------------------------------------------------------
# Phase 7: Additional Setup
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[8/8] Additional Configuration${NC}"
echo "================================"

# Enable all services
systemctl enable httpd postfix dovecot 2>/dev/null || true
systemctl start httpd postfix dovecot 2>/dev/null || true

# Create backup directory for incoming migrations
mkdir -p /root/migration-restore
chmod 700 /root/migration-restore

# Install useful tools
dnf install -y certbot python3-certbot-apache fail2ban 2>&1 | tee -a "$LOG_FILE" || true

# Enable fail2ban
systemctl enable fail2ban 2>/dev/null || true
systemctl start fail2ban 2>/dev/null || true

log "Additional configuration complete"
echo -e "${GREEN}✓${NC} Additional configuration complete"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           SERVER SETUP COMPLETE                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Server Information:"
echo "  Hostname: $NEW_HOSTNAME"
echo "  IP Address: $SERVER_IP"
echo ""
echo "Access Points:"
echo -e "  Webmin:    ${BLUE}https://$SERVER_IP:10000${NC}"
echo -e "  Virtualmin: ${BLUE}https://$SERVER_IP:10000${NC}"
echo "  Login with: root and your root password"
echo ""
echo "Services Status:"
for svc in httpd mariadb postfix dovecot webmin; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $svc is running"
    else
        echo -e "  ${YELLOW}○${NC} $svc is not running"
    fi
done
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo "1. Copy backups from old server:"
echo "   scp -r root@OLD_SERVER:/root/migration-backup/* /root/migration-restore/"
echo ""
echo "2. Run the restore script:"
echo "   ./06-restore-migration.sh"
echo ""
echo "3. Or restore manually via Virtualmin web interface:"
echo "   - Log into Webmin at https://$SERVER_IP:10000"
echo "   - Go to: Virtualmin → Backup and Restore → Restore Virtual Servers"
echo "   - Select backup file location"
echo "   - Restore domains"
echo ""
echo "4. After restoring, update DNS:"
echo "   - Point domains to new server IP: $SERVER_IP"
echo ""

log "Server setup complete"

# Create marker file
echo "$(date): Server setup complete. Hostname: $NEW_HOSTNAME, IP: $SERVER_IP" > /root/.server-setup-complete
