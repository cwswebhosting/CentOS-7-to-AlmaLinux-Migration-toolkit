#!/bin/bash
#===============================================================================
# Script: 03-setup-fresh-almalinux.sh
# Purpose: Set up fresh AlmaLinux 8 with Webmin/Virtualmin
# Run On: OLD SERVER (after fresh AlmaLinux 8 install, BEFORE restoring data)
#
# This script will:
# 1. Update the system
# 2. Install Virtualmin with LAMP stack
# 3. Configure firewall
# 4. Prepare for restore
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/setup-almalinux-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     STEP 3: SETUP FRESH ALMALINUX 8 WITH VIRTUALMIN         ║${NC}"
echo -e "${BLUE}║     Run this on: OLD SERVER (Fresh AlmaLinux 8 install)      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Pre-flight checks
#-------------------------------------------------------------------------------
echo -e "${GREEN}[PRE-CHECK] Verifying environment...${NC}"

# Check if root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Check if AlmaLinux 8
if ! grep -qE "AlmaLinux.*8\.|Rocky.*8\." /etc/os-release 2>/dev/null; then
    echo -e "${RED}ERROR: This script requires AlmaLinux 8 or Rocky Linux 8${NC}"
    echo "Current OS: $(cat /etc/os-release | grep PRETTY_NAME)"
    exit 1
fi
echo -e "${GREEN}✓${NC} AlmaLinux/Rocky 8 detected"

# Check if already has Virtualmin
if command -v virtualmin &> /dev/null; then
    echo -e "${YELLOW}WARNING: Virtualmin appears to already be installed${NC}"
    read -p "Continue anyway? (y/n): " cont
    if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

#-------------------------------------------------------------------------------
# Get hostname
#-------------------------------------------------------------------------------
echo ""
CURRENT_HOSTNAME=$(hostname)
echo "Current hostname: $CURRENT_HOSTNAME"
read -p "Enter FQDN hostname (e.g., server.example.com) [$CURRENT_HOSTNAME]: " NEW_HOSTNAME
NEW_HOSTNAME="${NEW_HOSTNAME:-$CURRENT_HOSTNAME}"

echo ""
echo "Server will be configured with:"
echo "  Hostname: $NEW_HOSTNAME"
echo "  IP: $(hostname -I | awk '{print $1}')"
echo ""

read -p "Proceed with setup? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

log "Starting AlmaLinux 8 setup with hostname: $NEW_HOSTNAME"

#-------------------------------------------------------------------------------
# Phase 1: System Update
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[1/7] Updating System...${NC}"

dnf update -y 2>&1 | tee -a "$LOG_FILE"
dnf install -y epel-release 2>&1 | tee -a "$LOG_FILE"
dnf install -y wget curl tar gzip nano vim htop rsync 2>&1 | tee -a "$LOG_FILE"

echo -e "${GREEN}✓${NC} System updated"
log "System updated"

#-------------------------------------------------------------------------------
# Phase 2: Set Hostname
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[2/7] Configuring Hostname...${NC}"

hostnamectl set-hostname "$NEW_HOSTNAME"

# Update /etc/hosts
if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SHORT_HOSTNAME=$(echo "$NEW_HOSTNAME" | cut -d. -f1)
    echo "$SERVER_IP   $NEW_HOSTNAME $SHORT_HOSTNAME" >> /etc/hosts
fi

echo -e "${GREEN}✓${NC} Hostname set to: $NEW_HOSTNAME"
log "Hostname configured: $NEW_HOSTNAME"

#-------------------------------------------------------------------------------
# Phase 3: Configure Firewall
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/7] Configuring Firewall...${NC}"

# Enable and start firewalld
systemctl enable firewalld 2>/dev/null || true
systemctl start firewalld 2>/dev/null || true

# Add necessary ports
firewall-cmd --permanent --add-service=http 2>/dev/null || true
firewall-cmd --permanent --add-service=https 2>/dev/null || true
firewall-cmd --permanent --add-service=smtp 2>/dev/null || true
firewall-cmd --permanent --add-service=smtps 2>/dev/null || true
firewall-cmd --permanent --add-service=imap 2>/dev/null || true
firewall-cmd --permanent --add-service=imaps 2>/dev/null || true
firewall-cmd --permanent --add-service=pop3 2>/dev/null || true
firewall-cmd --permanent --add-service=pop3s 2>/dev/null || true
firewall-cmd --permanent --add-port=10000/tcp 2>/dev/null || true  # Webmin
firewall-cmd --permanent --add-port=20000/tcp 2>/dev/null || true  # Usermin
firewall-cmd --permanent --add-port=53/tcp 2>/dev/null || true     # DNS
firewall-cmd --permanent --add-port=53/udp 2>/dev/null || true     # DNS
firewall-cmd --permanent --add-service=ftp 2>/dev/null || true
firewall-cmd --permanent --add-port=587/tcp 2>/dev/null || true    # Submission
firewall-cmd --reload 2>/dev/null || true

echo -e "${GREEN}✓${NC} Firewall configured"
log "Firewall configured"

#-------------------------------------------------------------------------------
# Phase 4: Disable SELinux (Virtualmin recommendation)
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/7] Configuring SELinux...${NC}"

# Set SELinux to permissive (Virtualmin works better this way)
if [ -f /etc/selinux/config ]; then
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    setenforce 0 2>/dev/null || true
fi

echo -e "${GREEN}✓${NC} SELinux set to permissive"
log "SELinux configured"

#-------------------------------------------------------------------------------
# Phase 5: Install Virtualmin
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/7] Installing Virtualmin...${NC}"
echo ""
echo "This will install:"
echo "  • Webmin (web-based administration)"
echo "  • Virtualmin (virtual hosting management)"
echo "  • Apache web server"
echo "  • MariaDB database server"
echo "  • Postfix mail server"
echo "  • Dovecot IMAP/POP3 server"
echo "  • BIND DNS server"
echo "  • PHP and common modules"
echo ""
echo "This may take 10-20 minutes..."
echo ""

log "Downloading Virtualmin installer"

cd /root
wget -q https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh -O virtualmin-install.sh
chmod +x virtualmin-install.sh

log "Running Virtualmin installer"

# Run installer with LAMP bundle
./virtualmin-install.sh --bundle LAMP 2>&1 | tee -a "$LOG_FILE"

INSTALL_STATUS=$?

if [ $INSTALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Virtualmin installed successfully"
    log "Virtualmin installed successfully"
else
    echo -e "${RED}WARNING: Virtualmin installer returned code $INSTALL_STATUS${NC}"
    echo "Check log file: $LOG_FILE"
    log "Virtualmin installer returned: $INSTALL_STATUS"
fi

#-------------------------------------------------------------------------------
# Phase 6: Configure MariaDB
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/7] Configuring MariaDB...${NC}"

# Ensure MariaDB is running
systemctl enable mariadb 2>/dev/null || true
systemctl start mariadb 2>/dev/null || true

# Run secure installation
echo ""
echo "Securing MariaDB..."
echo "Please set a strong root password when prompted."
echo "(This should match your old server's MySQL root password for easier restore)"
echo ""

mysql_secure_installation 2>&1 || true

echo -e "${GREEN}✓${NC} MariaDB configured"
log "MariaDB configured"

#-------------------------------------------------------------------------------
# Phase 7: Configure PHP
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/7] Configuring PHP...${NC}"

# Install additional PHP modules
dnf install -y php-gd php-mbstring php-xml php-json php-curl php-zip php-intl php-opcache 2>&1 | tee -a "$LOG_FILE" || true

# Optimize PHP settings
PHP_INI=$(php -i 2>/dev/null | grep "Loaded Configuration File" | awk '{print $5}')
if [ -f "$PHP_INI" ]; then
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
    sed -i 's/post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/max_input_time = .*/max_input_time = 300/' "$PHP_INI"
    log "PHP settings optimized"
fi

# Restart services
systemctl restart httpd php-fpm 2>/dev/null || systemctl restart httpd

echo -e "${GREEN}✓${NC} PHP configured"

#-------------------------------------------------------------------------------
# Install additional useful tools
#-------------------------------------------------------------------------------
echo ""
echo "Installing additional tools..."

dnf install -y certbot python3-certbot-apache fail2ban 2>&1 | tee -a "$LOG_FILE" || true

# Enable fail2ban
systemctl enable fail2ban 2>/dev/null || true
systemctl start fail2ban 2>/dev/null || true

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ALMALINUX 8 SETUP COMPLETE!                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Server Information:"
echo "  Hostname:   $NEW_HOSTNAME"
echo "  IP Address: $SERVER_IP"
echo ""
echo "Access Points:"
echo -e "  Webmin/Virtualmin: ${BLUE}https://$SERVER_IP:10000${NC}"
echo "  Login with: root and your root password"
echo ""
echo "Services Status:"
for svc in httpd mariadb postfix dovecot named webmin; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $svc is running"
    else
        echo -e "  ${YELLOW}○${NC} $svc is not running (may start after config)"
    fi
done

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                      NEXT STEPS                              ║${NC}"
echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║  Now run the restore script to pull data from temp server:  ║${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║  ./02-restore-from-new-server.sh TEMP_SERVER_IP              ║${NC}"
echo -e "${YELLOW}║                                                              ║${NC}"
echo -e "${YELLOW}║  This will:                                                  ║${NC}"
echo -e "${YELLOW}║  • Download backups from the temporary server                ║${NC}"
echo -e "${YELLOW}║  • Restore all Virtualmin domains                            ║${NC}"
echo -e "${YELLOW}║  • Restore databases, SSL certs, and configurations         ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "Setup complete"

# Create marker file
echo "Setup completed: $(date)" > /root/.almalinux-setup-complete
echo "Hostname: $NEW_HOSTNAME" >> /root/.almalinux-setup-complete
echo "IP: $SERVER_IP" >> /root/.almalinux-setup-complete
