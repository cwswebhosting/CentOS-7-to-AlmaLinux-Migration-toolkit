#!/bin/bash
#===============================================================================
# Script: 01-pre-migration-audit.sh
# Purpose: Audit CentOS 7 system before migration to AlmaLinux 8
# Author: Migration Toolkit
# Usage: sudo ./01-pre-migration-audit.sh
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output directory
AUDIT_DIR="/root/migration-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$AUDIT_DIR"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       CentOS 7 Pre-Migration Audit Script                    ║${NC}"
echo -e "${BLUE}║       Output Directory: $AUDIT_DIR${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Function: log_section
#-------------------------------------------------------------------------------
log_section() {
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#-------------------------------------------------------------------------------
# System Information
#-------------------------------------------------------------------------------
log_section "1. SYSTEM INFORMATION"

echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo ""

echo "=== OS Release ===" | tee "$AUDIT_DIR/system-info.txt"
cat /etc/os-release | tee -a "$AUDIT_DIR/system-info.txt"
echo ""

echo "=== Kernel ===" | tee -a "$AUDIT_DIR/system-info.txt"
uname -a | tee -a "$AUDIT_DIR/system-info.txt"
echo ""

echo "=== CPU Info ===" | tee -a "$AUDIT_DIR/system-info.txt"
lscpu | head -20 | tee -a "$AUDIT_DIR/system-info.txt"
echo ""

echo "=== Memory ===" | tee -a "$AUDIT_DIR/system-info.txt"
free -h | tee -a "$AUDIT_DIR/system-info.txt"
echo ""

#-------------------------------------------------------------------------------
# Disk Space
#-------------------------------------------------------------------------------
log_section "2. DISK SPACE"

echo "=== Disk Usage ===" | tee "$AUDIT_DIR/disk-info.txt"
df -h | tee -a "$AUDIT_DIR/disk-info.txt"
echo ""

echo "=== Block Devices ===" | tee -a "$AUDIT_DIR/disk-info.txt"
lsblk | tee -a "$AUDIT_DIR/disk-info.txt"
echo ""

echo "=== Large Directories (Top 20) ===" | tee -a "$AUDIT_DIR/disk-info.txt"
du -h --max-depth=2 / 2>/dev/null | sort -rh | head -20 | tee -a "$AUDIT_DIR/disk-info.txt"
echo ""

# Check if enough space for upgrade (need at least 10GB free on /)
ROOT_FREE=$(df / | awk 'NR==2 {print $4}')
if [ "$ROOT_FREE" -lt 10485760 ]; then
    echo -e "${RED}⚠ WARNING: Less than 10GB free on /. Recommend freeing space before upgrade.${NC}"
fi

#-------------------------------------------------------------------------------
# Installed Packages
#-------------------------------------------------------------------------------
log_section "3. INSTALLED PACKAGES"

echo "Total RPM packages: $(rpm -qa | wc -l)" | tee "$AUDIT_DIR/packages.txt"
echo ""

echo "=== All Installed Packages ===" >> "$AUDIT_DIR/packages-full-list.txt"
rpm -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort >> "$AUDIT_DIR/packages-full-list.txt"

echo "=== Third-Party Repositories ===" | tee -a "$AUDIT_DIR/packages.txt"
yum repolist | tee -a "$AUDIT_DIR/packages.txt"
echo ""

echo "=== Packages NOT from CentOS repos ===" | tee -a "$AUDIT_DIR/packages.txt"
yum list installed 2>/dev/null | grep -v "^Installed\|^@base\|^@updates\|^@extras\|^@centos" | head -50 | tee -a "$AUDIT_DIR/packages.txt"
echo ""

#-------------------------------------------------------------------------------
# Webmin/Virtualmin
#-------------------------------------------------------------------------------
log_section "4. WEBMIN/VIRTUALMIN"

echo "=== Virtualmin Status ===" | tee "$AUDIT_DIR/virtualmin-info.txt"

if command -v virtualmin &> /dev/null; then
    echo -e "${GREEN}✓ Virtualmin is installed${NC}" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    
    echo ""
    echo "=== Virtualmin Version ===" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    rpm -q virtualmin-base 2>/dev/null || echo "virtualmin-base not found" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    rpm -q webmin 2>/dev/null || echo "webmin not found" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    
    echo ""
    echo "=== Virtual Servers (Domains) ===" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    virtualmin list-domains --name-only 2>/dev/null | tee -a "$AUDIT_DIR/virtualmin-domains.txt"
    DOMAIN_COUNT=$(virtualmin list-domains --name-only 2>/dev/null | wc -l)
    echo "Total domains: $DOMAIN_COUNT" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    
    echo ""
    echo "=== Virtual Servers Details ===" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    virtualmin list-domains --multiline 2>/dev/null | tee -a "$AUDIT_DIR/virtualmin-domains-detail.txt"
    
else
    echo -e "${YELLOW}! Virtualmin command not found${NC}" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
fi

if [ -f /etc/webmin/miniserv.conf ]; then
    echo ""
    echo "=== Webmin Config ===" | tee -a "$AUDIT_DIR/virtualmin-info.txt"
    grep -E "^port=|^ssl=" /etc/webmin/miniserv.conf | tee -a "$AUDIT_DIR/virtualmin-info.txt"
fi

#-------------------------------------------------------------------------------
# Apache
#-------------------------------------------------------------------------------
log_section "5. APACHE WEB SERVER"

echo "=== Apache Status ===" | tee "$AUDIT_DIR/apache-info.txt"

if systemctl is-active --quiet httpd; then
    echo -e "${GREEN}✓ Apache (httpd) is running${NC}" | tee -a "$AUDIT_DIR/apache-info.txt"
else
    echo -e "${YELLOW}! Apache (httpd) is not running${NC}" | tee -a "$AUDIT_DIR/apache-info.txt"
fi

echo ""
echo "=== Apache Version ===" | tee -a "$AUDIT_DIR/apache-info.txt"
httpd -v 2>/dev/null | tee -a "$AUDIT_DIR/apache-info.txt"

echo ""
echo "=== Apache Modules ===" | tee -a "$AUDIT_DIR/apache-info.txt"
httpd -M 2>/dev/null | tee -a "$AUDIT_DIR/apache-modules.txt"
echo "Modules saved to apache-modules.txt"

echo ""
echo "=== Virtual Hosts ===" | tee -a "$AUDIT_DIR/apache-info.txt"
httpd -S 2>/dev/null | tee -a "$AUDIT_DIR/apache-vhosts.txt"
echo "Virtual hosts saved to apache-vhosts.txt"

echo ""
echo "=== Apache Config Files ===" | tee -a "$AUDIT_DIR/apache-info.txt"
ls -la /etc/httpd/conf.d/ 2>/dev/null | tee -a "$AUDIT_DIR/apache-info.txt"

# Backup Apache configs
cp -r /etc/httpd "$AUDIT_DIR/apache-config-backup" 2>/dev/null || echo "Could not backup /etc/httpd"

#-------------------------------------------------------------------------------
# MariaDB/MySQL
#-------------------------------------------------------------------------------
log_section "6. MARIADB/MYSQL DATABASE"

echo "=== MariaDB Status ===" | tee "$AUDIT_DIR/mariadb-info.txt"

if systemctl is-active --quiet mariadb; then
    echo -e "${GREEN}✓ MariaDB is running${NC}" | tee -a "$AUDIT_DIR/mariadb-info.txt"
elif systemctl is-active --quiet mysql; then
    echo -e "${GREEN}✓ MySQL is running${NC}" | tee -a "$AUDIT_DIR/mariadb-info.txt"
else
    echo -e "${YELLOW}! MariaDB/MySQL is not running${NC}" | tee -a "$AUDIT_DIR/mariadb-info.txt"
fi

echo ""
echo "=== MariaDB Version ===" | tee -a "$AUDIT_DIR/mariadb-info.txt"
mysql --version 2>/dev/null | tee -a "$AUDIT_DIR/mariadb-info.txt"

echo ""
echo "=== Databases ===" | tee -a "$AUDIT_DIR/mariadb-info.txt"
mysql -e "SHOW DATABASES;" 2>/dev/null | tee -a "$AUDIT_DIR/mariadb-databases.txt" || echo "Cannot connect to MySQL (may need credentials)"

echo ""
echo "=== Database Sizes ===" | tee -a "$AUDIT_DIR/mariadb-info.txt"
mysql -e "SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.TABLES GROUP BY table_schema;" 2>/dev/null | tee -a "$AUDIT_DIR/mariadb-info.txt" || echo "Cannot get database sizes"

echo ""
echo "=== MySQL Users ===" | tee -a "$AUDIT_DIR/mariadb-info.txt"
mysql -e "SELECT User, Host FROM mysql.user;" 2>/dev/null | tee -a "$AUDIT_DIR/mariadb-users.txt" || echo "Cannot list users"

# Calculate total database size
DB_SIZE=$(du -sh /var/lib/mysql 2>/dev/null | awk '{print $1}')
echo ""
echo "Total MySQL data directory size: $DB_SIZE" | tee -a "$AUDIT_DIR/mariadb-info.txt"

#-------------------------------------------------------------------------------
# Mail Server
#-------------------------------------------------------------------------------
log_section "7. MAIL SERVER"

echo "=== Mail Services Status ===" | tee "$AUDIT_DIR/mail-info.txt"

# Check Postfix
if systemctl is-active --quiet postfix; then
    echo -e "${GREEN}✓ Postfix is running${NC}" | tee -a "$AUDIT_DIR/mail-info.txt"
    postconf -n 2>/dev/null | tee -a "$AUDIT_DIR/postfix-config.txt"
else
    echo -e "${YELLOW}! Postfix is not running${NC}" | tee -a "$AUDIT_DIR/mail-info.txt"
fi

# Check Dovecot
if systemctl is-active --quiet dovecot; then
    echo -e "${GREEN}✓ Dovecot is running${NC}" | tee -a "$AUDIT_DIR/mail-info.txt"
else
    echo -e "${YELLOW}! Dovecot is not running${NC}" | tee -a "$AUDIT_DIR/mail-info.txt"
fi

# Check for mail queue
echo ""
echo "=== Mail Queue ===" | tee -a "$AUDIT_DIR/mail-info.txt"
postqueue -p 2>/dev/null | tail -5 | tee -a "$AUDIT_DIR/mail-info.txt"

# Mail directories size
echo ""
echo "=== Mail Storage ===" | tee -a "$AUDIT_DIR/mail-info.txt"
if [ -d /var/mail ]; then
    du -sh /var/mail 2>/dev/null | tee -a "$AUDIT_DIR/mail-info.txt"
fi
if [ -d /home/*/Maildir ]; then
    du -sh /home/*/Maildir 2>/dev/null | head -10 | tee -a "$AUDIT_DIR/mail-info.txt"
fi

#-------------------------------------------------------------------------------
# SSL Certificates
#-------------------------------------------------------------------------------
log_section "8. SSL CERTIFICATES"

echo "=== SSL Certificates ===" | tee "$AUDIT_DIR/ssl-info.txt"

# Check Let's Encrypt
if [ -d /etc/letsencrypt/live ]; then
    echo "=== Let's Encrypt Certificates ===" | tee -a "$AUDIT_DIR/ssl-info.txt"
    ls -la /etc/letsencrypt/live/ | tee -a "$AUDIT_DIR/ssl-info.txt"
    
    echo ""
    echo "=== Certificate Expiry Dates ===" | tee -a "$AUDIT_DIR/ssl-info.txt"
    for cert in /etc/letsencrypt/live/*/cert.pem; do
        if [ -f "$cert" ]; then
            domain=$(dirname "$cert" | xargs basename)
            expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
            echo "$domain: $expiry" | tee -a "$AUDIT_DIR/ssl-info.txt"
        fi
    done
fi

# Backup Let's Encrypt
if [ -d /etc/letsencrypt ]; then
    cp -r /etc/letsencrypt "$AUDIT_DIR/letsencrypt-backup" 2>/dev/null && echo "Let's Encrypt backed up"
fi

#-------------------------------------------------------------------------------
# Cron Jobs
#-------------------------------------------------------------------------------
log_section "9. CRON JOBS"

echo "=== System Cron Jobs ===" | tee "$AUDIT_DIR/cron-info.txt"

echo "--- /etc/crontab ---" | tee -a "$AUDIT_DIR/cron-info.txt"
cat /etc/crontab 2>/dev/null | tee -a "$AUDIT_DIR/cron-info.txt"

echo ""
echo "--- /etc/cron.d/ ---" | tee -a "$AUDIT_DIR/cron-info.txt"
ls -la /etc/cron.d/ 2>/dev/null | tee -a "$AUDIT_DIR/cron-info.txt"

echo ""
echo "=== User Cron Jobs ===" | tee -a "$AUDIT_DIR/cron-info.txt"
for user in $(cut -f1 -d: /etc/passwd); do
    crontab_content=$(crontab -l -u "$user" 2>/dev/null)
    if [ -n "$crontab_content" ]; then
        echo "--- User: $user ---" | tee -a "$AUDIT_DIR/cron-info.txt"
        echo "$crontab_content" | tee -a "$AUDIT_DIR/cron-info.txt"
        echo "" | tee -a "$AUDIT_DIR/cron-info.txt"
    fi
done

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
log_section "10. NETWORK CONFIGURATION"

echo "=== IP Addresses ===" | tee "$AUDIT_DIR/network-info.txt"
ip addr show | tee -a "$AUDIT_DIR/network-info.txt"

echo ""
echo "=== Listening Ports ===" | tee -a "$AUDIT_DIR/network-info.txt"
ss -tlnp | tee -a "$AUDIT_DIR/network-info.txt"

echo ""
echo "=== Firewall Rules ===" | tee -a "$AUDIT_DIR/network-info.txt"
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --list-all 2>/dev/null | tee -a "$AUDIT_DIR/network-info.txt"
fi
iptables -L -n 2>/dev/null | tee -a "$AUDIT_DIR/iptables-rules.txt"

echo ""
echo "=== DNS Configuration ===" | tee -a "$AUDIT_DIR/network-info.txt"
cat /etc/resolv.conf | tee -a "$AUDIT_DIR/network-info.txt"

#-------------------------------------------------------------------------------
# Services
#-------------------------------------------------------------------------------
log_section "11. ENABLED SERVICES"

echo "=== Enabled Services ===" | tee "$AUDIT_DIR/services-info.txt"
systemctl list-unit-files --type=service --state=enabled | tee -a "$AUDIT_DIR/services-info.txt"

echo ""
echo "=== Running Services ===" | tee -a "$AUDIT_DIR/services-info.txt"
systemctl list-units --type=service --state=running | tee -a "$AUDIT_DIR/services-info.txt"

#-------------------------------------------------------------------------------
# Users and Groups
#-------------------------------------------------------------------------------
log_section "12. USERS AND GROUPS"

echo "=== System Users (UID >= 1000) ===" | tee "$AUDIT_DIR/users-info.txt"
awk -F: '$3 >= 1000 && $3 < 65534 {print $1":"$3":"$6}' /etc/passwd | tee -a "$AUDIT_DIR/users-info.txt"

echo ""
echo "=== Users with sudo access ===" | tee -a "$AUDIT_DIR/users-info.txt"
grep -E "^%wheel|^%sudo" /etc/sudoers 2>/dev/null | tee -a "$AUDIT_DIR/users-info.txt"
getent group wheel | tee -a "$AUDIT_DIR/users-info.txt"

# Backup passwd and group
cp /etc/passwd "$AUDIT_DIR/passwd.bak"
cp /etc/shadow "$AUDIT_DIR/shadow.bak" 2>/dev/null || echo "Cannot backup shadow (need root)"
cp /etc/group "$AUDIT_DIR/group.bak"

#-------------------------------------------------------------------------------
# Web Content
#-------------------------------------------------------------------------------
log_section "13. WEB CONTENT"

echo "=== Document Root Sizes ===" | tee "$AUDIT_DIR/webcontent-info.txt"

# Standard locations
for dir in /var/www /home/*/public_html /home/*/domains; do
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | tee -a "$AUDIT_DIR/webcontent-info.txt"
    fi
done

echo ""
echo "=== Home Directories ===" | tee -a "$AUDIT_DIR/webcontent-info.txt"
du -sh /home/* 2>/dev/null | sort -rh | head -20 | tee -a "$AUDIT_DIR/webcontent-info.txt"

#-------------------------------------------------------------------------------
# Summary Report
#-------------------------------------------------------------------------------
log_section "14. SUMMARY REPORT"

SUMMARY="$AUDIT_DIR/MIGRATION-SUMMARY.txt"

cat << EOF | tee "$SUMMARY"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    CENTOS 7 MIGRATION AUDIT SUMMARY                          ║
╚══════════════════════════════════════════════════════════════════════════════╝

Generated: $(date)
Hostname: $(hostname)
OS: $(cat /etc/redhat-release)
Kernel: $(uname -r)

STORAGE:
$(df -h / | tail -1 | awk '{print "  Root partition: "$3" used / "$2" total ("$5" full)"}')
$(df -h /home 2>/dev/null | tail -1 | awk '{print "  Home partition: "$3" used / "$2" total ("$5" full)"}')

SERVICES DETECTED:
  ✓ Apache: $(httpd -v 2>/dev/null | head -1 || echo "Not found")
  ✓ MariaDB: $(mysql --version 2>/dev/null || echo "Not found")
  ✓ Postfix: $(postconf -d mail_version 2>/dev/null | awk '{print $3}' || echo "Not found")
  ✓ Dovecot: $(dovecot --version 2>/dev/null || echo "Not found")
  ✓ Webmin: $(rpm -q webmin 2>/dev/null || echo "Not found")

VIRTUALMIN:
  Domains: $(virtualmin list-domains --name-only 2>/dev/null | wc -l || echo "N/A")
  
DATABASE:
  Total size: $(du -sh /var/lib/mysql 2>/dev/null | awk '{print $1}' || echo "N/A")
  Databases: $(mysql -e "SHOW DATABASES;" 2>/dev/null | wc -l || echo "N/A")

ESTIMATED BACKUP SIZE:
  /home: $(du -sh /home 2>/dev/null | awk '{print $1}')
  /var/www: $(du -sh /var/www 2>/dev/null | awk '{print $1}')
  /var/lib/mysql: $(du -sh /var/lib/mysql 2>/dev/null | awk '{print $1}')
  /etc: $(du -sh /etc 2>/dev/null | awk '{print $1}')

RECOMMENDATIONS:
$([ "$ROOT_FREE" -lt 10485760 ] && echo "  ⚠ FREE UP DISK SPACE: Less than 10GB free on root partition")
  • Create full backup before any migration
  • Use Virtualmin backup for easiest domain migration
  • Test email delivery after migration
  • Update DNS only after verifying new server

AUDIT FILES LOCATION: $AUDIT_DIR

EOF

#-------------------------------------------------------------------------------
# Final Output
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    AUDIT COMPLETE                            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "All audit data saved to: ${BLUE}$AUDIT_DIR${NC}"
echo ""
echo "Important files created:"
echo "  • MIGRATION-SUMMARY.txt - Overview of your system"
echo "  • virtualmin-domains.txt - List of all domains"
echo "  • mariadb-databases.txt - List of databases"
echo "  • apache-vhosts.txt - Apache virtual hosts"
echo "  • packages-full-list.txt - All installed packages"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo "  1. Review the summary and audit files"
echo "  2. Run 02-full-backup.sh to create system backup"
echo "  3. Run 03-virtualmin-backup.sh for Virtualmin backups"
echo ""
