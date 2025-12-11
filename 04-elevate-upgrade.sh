#!/bin/bash
#===============================================================================
# Script: 04-elevate-upgrade.sh
# Purpose: In-place upgrade from CentOS 7 to AlmaLinux 8 using ELevate
# Author: Migration Toolkit
# Usage: sudo ./04-elevate-upgrade.sh
#
# ⚠️  WARNING: IN-PLACE UPGRADE IS RISKY FOR PRODUCTION SERVERS
# ⚠️  ALWAYS HAVE FULL BACKUPS BEFORE PROCEEDING
# ⚠️  TEST IN STAGING ENVIRONMENT FIRST
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/elevate-upgrade-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║     ⚠️  CENTOS 7 TO ALMALINUX 8 IN-PLACE UPGRADE ⚠️           ║${NC}"
echo -e "${RED}║                                                              ║${NC}"
echo -e "${RED}║  THIS IS A RISKY OPERATION FOR PRODUCTION SERVERS           ║${NC}"
echo -e "${RED}║  VIRTUALMIN MAY REQUIRE RECONFIGURATION AFTER UPGRADE       ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Pre-flight checks
#-------------------------------------------------------------------------------
echo -e "${YELLOW}PRE-FLIGHT CHECKS${NC}"
echo "================="
echo ""

# Check if root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Check OS version
if ! grep -q "CentOS Linux release 7" /etc/redhat-release 2>/dev/null; then
    echo -e "${RED}ERROR: This script is only for CentOS 7${NC}"
    cat /etc/redhat-release
    exit 1
fi
echo -e "${GREEN}✓${NC} CentOS 7 detected"

# Check if backup exists
echo ""
echo -e "${YELLOW}BACKUP VERIFICATION${NC}"
read -p "Have you run the backup scripts (02 and 03)? (yes/no): " backup_confirm
if [ "$backup_confirm" != "yes" ]; then
    echo -e "${RED}Please run backup scripts first!${NC}"
    echo "  ./02-full-backup.sh"
    echo "  ./03-virtualmin-backup.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Backups confirmed"

# Check disk space
ROOT_FREE=$(df / | awk 'NR==2 {print $4}')
ROOT_FREE_GB=$((ROOT_FREE / 1024 / 1024))
if [ "$ROOT_FREE" -lt 5242880 ]; then
    echo -e "${RED}ERROR: Need at least 5GB free on root partition${NC}"
    echo "Current free space: ${ROOT_FREE_GB}GB"
    exit 1
fi
echo -e "${GREEN}✓${NC} Disk space OK (${ROOT_FREE_GB}GB free)"

# Final confirmation
echo ""
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}  FINAL WARNING: This will upgrade your system to AlmaLinux 8${NC}"
echo -e "${RED}  The process takes 1-3 hours and requires a reboot${NC}"
echo -e "${RED}  Services may be unavailable during upgrade${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "Type 'UPGRADE' to proceed: " confirm
if [ "$confirm" != "UPGRADE" ]; then
    echo "Aborted."
    exit 1
fi

log "Starting ELevate upgrade process"

#-------------------------------------------------------------------------------
# Phase 1: Pre-upgrade preparation
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[PHASE 1/5] Pre-upgrade Preparation${NC}"
echo "======================================"

log "Phase 1: Pre-upgrade preparation"

# Update current system
echo "Updating current CentOS 7 system..."
yum update -y | tee -a "$LOG_FILE"

# Clean yum cache
yum clean all

# Record current state
rpm -qa --queryformat '%{NAME}\n' | sort > /root/pre-upgrade-packages.txt
systemctl list-unit-files --state=enabled > /root/pre-upgrade-services.txt

# Stop non-essential services for safety
echo "Stopping services that might interfere..."
systemctl stop webmin 2>/dev/null || true
systemctl stop usermin 2>/dev/null || true

log "Pre-upgrade preparation complete"

#-------------------------------------------------------------------------------
# Phase 2: Install ELevate
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[PHASE 2/5] Installing ELevate${NC}"
echo "================================"

log "Phase 2: Installing ELevate"

# Install elevate-release
echo "Installing ELevate repository..."
yum install -y http://repo.almalinux.org/elevate/elevate-release-latest-el7.noarch.rpm 2>&1 | tee -a "$LOG_FILE"

# Install leapp and AlmaLinux upgrade data
echo "Installing leapp upgrade tools..."
yum install -y leapp-upgrade leapp-data-almalinux 2>&1 | tee -a "$LOG_FILE"

log "ELevate installation complete"

#-------------------------------------------------------------------------------
# Phase 3: Pre-upgrade assessment
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[PHASE 3/5] Pre-upgrade Assessment${NC}"
echo "====================================="

log "Phase 3: Running pre-upgrade assessment"

# Run preupgrade check
echo "Running pre-upgrade check (this may take several minutes)..."
leapp preupgrade 2>&1 | tee -a "$LOG_FILE" || true

# Check for inhibitors
echo ""
echo "Checking for upgrade inhibitors..."

INHIBITORS_FILE="/var/log/leapp/leapp-report.txt"
if [ -f "$INHIBITORS_FILE" ]; then
    INHIBITORS=$(grep -c "inhibitor" "$INHIBITORS_FILE" 2>/dev/null || echo "0")
    echo "Found $INHIBITORS potential issues"
    
    if [ "$INHIBITORS" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  UPGRADE INHIBITORS FOUND - MANUAL INTERVENTION REQUIRED${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Review the report at: $INHIBITORS_FILE"
        echo ""
        echo "Common fixes:"
        echo ""
        
        # Common fix: PAM configuration
        if grep -q "pam" "$INHIBITORS_FILE" 2>/dev/null; then
            echo "1. PAM configuration issue - Fix with:"
            echo "   rm -f /etc/pam.d/system-auth-local"
            echo "   rm -f /etc/pam.d/password-auth-local"
        fi
        
        # Common fix: Kernel modules
        if grep -q "kernel" "$INHIBITORS_FILE" 2>/dev/null; then
            echo "2. Kernel driver issue - May need to unload modules"
        fi
        
        # Common fix: GRUB
        if grep -q "GRUB" "$INHIBITORS_FILE" 2>/dev/null; then
            echo "3. GRUB configuration needed"
        fi
        
        echo ""
        echo "After fixing issues, re-run: leapp preupgrade"
        echo "Then re-run this script."
        echo ""
        
        read -p "Would you like to see the full report? (y/n): " show_report
        if [[ "$show_report" =~ ^[Yy]$ ]]; then
            cat "$INHIBITORS_FILE" | less
        fi
        
        read -p "Attempt to auto-fix common issues and continue? (y/n): " autofix
        if [[ ! "$autofix" =~ ^[Yy]$ ]]; then
            log "Upgrade aborted - inhibitors found"
            exit 1
        fi
        
        # Auto-fix attempts
        echo "Attempting auto-fixes..."
        
        # Fix: PAM
        rm -f /etc/pam.d/system-auth-local 2>/dev/null || true
        rm -f /etc/pam.d/password-auth-local 2>/dev/null || true
        
        # Fix: SSH config
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 2>/dev/null || true
        
        # Fix: Disable incompatible repos
        yum-config-manager --disable epel 2>/dev/null || true
        
        # Create answers file for known issues
        mkdir -p /var/log/leapp
        
        # Re-run preupgrade
        echo "Re-running preupgrade check..."
        leapp preupgrade 2>&1 | tee -a "$LOG_FILE" || true
    fi
fi

# Answer some common questions
mkdir -p /var/log/leapp
leapp answer --section remove_pam_pkcs11_module_check.confirm=True 2>/dev/null || true

log "Pre-upgrade assessment complete"

#-------------------------------------------------------------------------------
# Phase 4: Perform Upgrade
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[PHASE 4/5] Performing Upgrade${NC}"
echo "================================"

echo -e "${RED}"
echo "═══════════════════════════════════════════════════════════════"
echo "  THE SYSTEM WILL REBOOT DURING THIS PROCESS"
echo "  DO NOT INTERRUPT - THIS CAN TAKE 1-3 HOURS"
echo "  SSH CONNECTION WILL BE LOST"
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

read -p "Ready to proceed with upgrade and reboot? (yes/no): " final_confirm
if [ "$final_confirm" != "yes" ]; then
    echo "Aborted."
    log "Upgrade aborted by user"
    exit 1
fi

log "Phase 4: Starting upgrade process"

# Start the upgrade
echo "Starting upgrade... The system will reboot automatically."
echo "After reboot, the upgrade process will continue."
echo ""
echo "Monitor progress after reboot with: journalctl -u leapp-upgrade -f"
echo ""

leapp upgrade 2>&1 | tee -a "$LOG_FILE"

# If we get here without error, initiate reboot
echo ""
echo "Upgrade preparation complete. Rebooting in 10 seconds..."
echo "DO NOT INTERRUPT THE REBOOT PROCESS"
sleep 10

log "Initiating reboot for upgrade"
reboot

#-------------------------------------------------------------------------------
# Phase 5 runs after reboot - create post-upgrade script
#-------------------------------------------------------------------------------
cat << 'POSTSCRIPT' > /root/05-post-elevate-upgrade.sh
#!/bin/bash
# This script should be run after the system reboots into AlmaLinux 8

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          POST-UPGRADE VERIFICATION                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verify OS
echo "Current OS:"
cat /etc/os-release | grep PRETTY_NAME

echo ""
echo "Kernel:"
uname -r

# Clean up old packages
echo ""
echo "Cleaning up old CentOS 7 packages..."
dnf remove -y leapp-deps-el8 leapp-repository-deps-el8 2>/dev/null || true
dnf remove -y kernel-3.10* 2>/dev/null || true

# Update system
echo ""
echo "Updating AlmaLinux 8..."
dnf update -y

# Fix Virtualmin if installed
if [ -f /etc/webmin/virtual-server/config ]; then
    echo ""
    echo "Virtualmin detected - Reinstalling/Updating..."
    echo "This may take several minutes..."
    
    # Download and run Virtualmin install script in update mode
    wget -q https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh -O /tmp/virtualmin-install.sh
    chmod +x /tmp/virtualmin-install.sh
    /tmp/virtualmin-install.sh --minimal --bundle LAMP || true
fi

# Restart services
echo ""
echo "Restarting services..."
systemctl restart httpd 2>/dev/null || true
systemctl restart mariadb 2>/dev/null || true
systemctl restart postfix 2>/dev/null || true
systemctl restart dovecot 2>/dev/null || true
systemctl restart webmin 2>/dev/null || true

# Verify services
echo ""
echo "Service status:"
for svc in httpd mariadb postfix dovecot webmin; do
    if systemctl is-active --quiet $svc; then
        echo -e "  ${GREEN}✓${NC} $svc is running"
    else
        echo -e "  ${RED}✗${NC} $svc is not running"
    fi
done

echo ""
echo -e "${GREEN}Post-upgrade tasks complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Test all websites"
echo "  2. Test email sending/receiving"
echo "  3. Check Virtualmin/Webmin interface"
echo "  4. Review logs for errors"
echo ""
POSTSCRIPT

chmod +x /root/05-post-elevate-upgrade.sh
echo ""
echo "Post-upgrade script created at /root/05-post-elevate-upgrade.sh"
echo "Run it after the system reboots into AlmaLinux 8"
