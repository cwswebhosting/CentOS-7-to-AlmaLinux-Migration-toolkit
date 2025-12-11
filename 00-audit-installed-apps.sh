#!/bin/bash
#===============================================================================
# Script: 00-audit-installed-apps.sh
# Purpose: Audit all installed applications and versions on CentOS 7
#          Generate a report to share for creating custom install scripts
# Run On: OLD SERVER (CentOS 7) - BEFORE any migration steps
#
# The output report should be shared so we can create custom scripts
# for installing equivalent packages on AlmaLinux 8
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REPORT_DIR="/root/migration-audit"
REPORT_FILE="$REPORT_DIR/installed-apps-report.txt"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$REPORT_DIR"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     CENTOS 7 APPLICATION AUDIT                               ║${NC}"
echo -e "${BLUE}║     Generating report for AlmaLinux 8 migration              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#-------------------------------------------------------------------------------
# Initialize report
#-------------------------------------------------------------------------------
cat << EOF > "$REPORT_FILE"
================================================================================
           CENTOS 7 INSTALLED APPLICATIONS AUDIT REPORT
================================================================================

Generated: $(date)
Hostname: $(hostname)
IP Address: $(hostname -I | awk '{print $1}')
OS: $(cat /etc/redhat-release)
Kernel: $(uname -r)
Architecture: $(uname -m)

================================================================================
EOF

#-------------------------------------------------------------------------------
# System Information
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/12] Gathering system information...${NC}"

cat << EOF >> "$REPORT_FILE"

=== SYSTEM RESOURCES ===

CPU: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU Cores: $(nproc)
Total RAM: $(free -h | awk '/^Mem:/ {print $2}')
Disk Space:
$(df -h | grep -E "^/dev|Filesystem")

EOF

#-------------------------------------------------------------------------------
# Web Server
#-------------------------------------------------------------------------------
echo -e "${GREEN}[2/12] Checking web server...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                           WEB SERVER
================================================================================
EOF

# Apache
if command -v httpd &> /dev/null; then
    APACHE_VERSION=$(httpd -v 2>/dev/null | head -1)
    echo -e "  ${CYAN}Apache:${NC} $APACHE_VERSION"
    cat << EOF >> "$REPORT_FILE"

=== APACHE ===
Version: $APACHE_VERSION
Status: $(systemctl is-active httpd 2>/dev/null || echo "unknown")
Enabled: $(systemctl is-enabled httpd 2>/dev/null || echo "unknown")

Installed Apache Packages:
$(rpm -qa | grep -iE "^httpd|^mod_" | sort)

Loaded Modules:
$(httpd -M 2>/dev/null | grep -v "Loaded Modules" | sort)

EOF
else
    echo "Apache: Not installed" >> "$REPORT_FILE"
fi

# Nginx (if installed)
if command -v nginx &> /dev/null; then
    NGINX_VERSION=$(nginx -v 2>&1)
    echo -e "  ${CYAN}Nginx:${NC} $NGINX_VERSION"
    cat << EOF >> "$REPORT_FILE"

=== NGINX ===
Version: $NGINX_VERSION
Status: $(systemctl is-active nginx 2>/dev/null || echo "unknown")

EOF
fi

#-------------------------------------------------------------------------------
# PHP
#-------------------------------------------------------------------------------
echo -e "${GREEN}[3/12] Checking PHP...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                              PHP
================================================================================
EOF

if command -v php &> /dev/null; then
    PHP_VERSION=$(php -v 2>/dev/null | head -1)
    echo -e "  ${CYAN}PHP:${NC} $PHP_VERSION"
    
    cat << EOF >> "$REPORT_FILE"

=== PHP VERSION ===
$PHP_VERSION

=== PHP PACKAGES INSTALLED ===
$(rpm -qa | grep -i "^php" | sort)

=== PHP MODULES LOADED ===
$(php -m 2>/dev/null | sort)

=== PHP-FPM STATUS ===
Status: $(systemctl is-active php-fpm 2>/dev/null || echo "not installed/running")

=== KEY PHP SETTINGS ===
$(php -i 2>/dev/null | grep -E "^(memory_limit|upload_max|post_max|max_execution|max_input)" | head -10)

EOF
else
    echo "PHP: Not installed" >> "$REPORT_FILE"
fi

#-------------------------------------------------------------------------------
# Database
#-------------------------------------------------------------------------------
echo -e "${GREEN}[4/12] Checking database server...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                           DATABASE
================================================================================
EOF

# MariaDB/MySQL
if command -v mysql &> /dev/null; then
    DB_VERSION=$(mysql --version 2>/dev/null)
    echo -e "  ${CYAN}Database:${NC} $DB_VERSION"
    
    cat << EOF >> "$REPORT_FILE"

=== MARIADB/MYSQL ===
Version: $DB_VERSION
Status: $(systemctl is-active mariadb 2>/dev/null || systemctl is-active mysql 2>/dev/null || echo "unknown")

Installed Packages:
$(rpm -qa | grep -iE "^mariadb|^mysql|^MySQL" | sort)

Databases:
$(mysql -N -e "SHOW DATABASES;" 2>/dev/null || echo "Cannot connect - need credentials")

Database Sizes:
$(mysql -e "SELECT table_schema AS 'Database', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.TABLES GROUP BY table_schema ORDER BY SUM(data_length + index_length) DESC;" 2>/dev/null || echo "Cannot get sizes")

EOF
else
    echo "MariaDB/MySQL: Not installed" >> "$REPORT_FILE"
fi

# PostgreSQL
if command -v psql &> /dev/null; then
    PG_VERSION=$(psql --version 2>/dev/null)
    echo -e "  ${CYAN}PostgreSQL:${NC} $PG_VERSION"
    cat << EOF >> "$REPORT_FILE"

=== POSTGRESQL ===
Version: $PG_VERSION
Status: $(systemctl is-active postgresql 2>/dev/null || echo "unknown")

EOF
fi

#-------------------------------------------------------------------------------
# Mail Server
#-------------------------------------------------------------------------------
echo -e "${GREEN}[5/12] Checking mail server...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                           MAIL SERVER
================================================================================
EOF

# Postfix
if command -v postfix &> /dev/null; then
    POSTFIX_VERSION=$(postconf -d mail_version 2>/dev/null | awk '{print $3}')
    echo -e "  ${CYAN}Postfix:${NC} $POSTFIX_VERSION"
    
    cat << EOF >> "$REPORT_FILE"

=== POSTFIX ===
Version: $POSTFIX_VERSION
Status: $(systemctl is-active postfix 2>/dev/null || echo "unknown")

Installed Packages:
$(rpm -qa | grep -i postfix | sort)

Key Configuration:
$(postconf -n 2>/dev/null | grep -E "^(myhostname|mydomain|myorigin|mydestination|relay)" | head -10)

EOF
fi

# Dovecot
if command -v dovecot &> /dev/null; then
    DOVECOT_VERSION=$(dovecot --version 2>/dev/null)
    echo -e "  ${CYAN}Dovecot:${NC} $DOVECOT_VERSION"
    
    cat << EOF >> "$REPORT_FILE"

=== DOVECOT ===
Version: $DOVECOT_VERSION
Status: $(systemctl is-active dovecot 2>/dev/null || echo "unknown")

Installed Packages:
$(rpm -qa | grep -i dovecot | sort)

EOF
fi

# Other mail components
cat << EOF >> "$REPORT_FILE"

=== OTHER MAIL COMPONENTS ===
SpamAssassin: $(rpm -q spamassassin 2>/dev/null || echo "not installed")
ClamAV: $(rpm -q clamav 2>/dev/null || echo "not installed")
OpenDKIM: $(rpm -q opendkim 2>/dev/null || echo "not installed")
Amavis: $(rpm -q amavisd-new 2>/dev/null || echo "not installed")

EOF

#-------------------------------------------------------------------------------
# Webmin/Virtualmin
#-------------------------------------------------------------------------------
echo -e "${GREEN}[6/12] Checking Webmin/Virtualmin...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                        WEBMIN / VIRTUALMIN
================================================================================
EOF

if [ -f /etc/webmin/version ]; then
    WEBMIN_VERSION=$(cat /etc/webmin/version)
    echo -e "  ${CYAN}Webmin:${NC} $WEBMIN_VERSION"
    
    cat << EOF >> "$REPORT_FILE"

=== WEBMIN ===
Version: $WEBMIN_VERSION
Status: $(systemctl is-active webmin 2>/dev/null || echo "unknown")
Port: $(grep "^port=" /etc/webmin/miniserv.conf 2>/dev/null | cut -d= -f2)

EOF
fi

if command -v virtualmin &> /dev/null; then
    echo -e "  ${CYAN}Virtualmin:${NC} Installed"
    
    cat << EOF >> "$REPORT_FILE"

=== VIRTUALMIN ===
Package: $(rpm -q virtualmin-base 2>/dev/null || echo "GPL version")
Domains: $(virtualmin list-domains --name-only 2>/dev/null | wc -l)

Domain List:
$(virtualmin list-domains --name-only 2>/dev/null)

Virtualmin Packages:
$(rpm -qa | grep -i virtualmin | sort)

EOF
fi

if [ -f /etc/usermin/version ]; then
    USERMIN_VERSION=$(cat /etc/usermin/version)
    cat << EOF >> "$REPORT_FILE"

=== USERMIN ===
Version: $USERMIN_VERSION
Status: $(systemctl is-active usermin 2>/dev/null || echo "unknown")

EOF
fi

#-------------------------------------------------------------------------------
# DNS
#-------------------------------------------------------------------------------
echo -e "${GREEN}[7/12] Checking DNS server...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                           DNS SERVER
================================================================================
EOF

if command -v named &> /dev/null; then
    BIND_VERSION=$(named -v 2>/dev/null)
    echo -e "  ${CYAN}BIND:${NC} $BIND_VERSION"
    
    cat << EOF >> "$REPORT_FILE"

=== BIND DNS ===
Version: $BIND_VERSION
Status: $(systemctl is-active named 2>/dev/null || echo "unknown")

Installed Packages:
$(rpm -qa | grep -i bind | sort)

EOF
fi

#-------------------------------------------------------------------------------
# FTP
#-------------------------------------------------------------------------------
echo -e "${GREEN}[8/12] Checking FTP server...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                           FTP SERVER
================================================================================
EOF

# ProFTPd
if command -v proftpd &> /dev/null; then
    PROFTPD_VERSION=$(proftpd -v 2>/dev/null | head -1)
    echo -e "  ${CYAN}ProFTPd:${NC} $PROFTPD_VERSION"
    cat << EOF >> "$REPORT_FILE"

=== PROFTPD ===
Version: $PROFTPD_VERSION
Status: $(systemctl is-active proftpd 2>/dev/null || echo "unknown")

EOF
fi

# vsftpd
if command -v vsftpd &> /dev/null; then
    VSFTPD_VERSION=$(rpm -q vsftpd 2>/dev/null)
    echo -e "  ${CYAN}vsftpd:${NC} $VSFTPD_VERSION"
    cat << EOF >> "$REPORT_FILE"

=== VSFTPD ===
Version: $VSFTPD_VERSION
Status: $(systemctl is-active vsftpd 2>/dev/null || echo "unknown")

EOF
fi

#-------------------------------------------------------------------------------
# Security Tools
#-------------------------------------------------------------------------------
echo -e "${GREEN}[9/12] Checking security tools...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                        SECURITY TOOLS
================================================================================

=== FIREWALL ===
Firewalld: $(systemctl is-active firewalld 2>/dev/null || echo "not active")
IPTables: $(systemctl is-active iptables 2>/dev/null || echo "not active")

=== FAIL2BAN ===
$(rpm -q fail2ban 2>/dev/null || echo "not installed")
Status: $(systemctl is-active fail2ban 2>/dev/null || echo "not active")

=== SSL/CERTBOT ===
Certbot: $(rpm -q certbot 2>/dev/null || echo "not installed")
Let's Encrypt certs: $(ls /etc/letsencrypt/live 2>/dev/null | wc -l) domains

=== SELINUX ===
Status: $(getenforce 2>/dev/null || echo "unknown")

EOF

#-------------------------------------------------------------------------------
# Programming Languages & Runtimes
#-------------------------------------------------------------------------------
echo -e "${GREEN}[10/12] Checking programming languages...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                    PROGRAMMING LANGUAGES & RUNTIMES
================================================================================

=== PYTHON ===
Python 2: $(python --version 2>&1 || echo "not installed")
Python 3: $(python3 --version 2>&1 || echo "not installed")
Pip: $(pip --version 2>&1 || echo "not installed")
Pip3: $(pip3 --version 2>&1 || echo "not installed")

=== NODE.JS ===
Node: $(node --version 2>/dev/null || echo "not installed")
NPM: $(npm --version 2>/dev/null || echo "not installed")

=== RUBY ===
Ruby: $(ruby --version 2>/dev/null || echo "not installed")
Gem: $(gem --version 2>/dev/null || echo "not installed")

=== PERL ===
Perl: $(perl --version 2>/dev/null | grep version | head -1 || echo "not installed")

=== JAVA ===
Java: $(java -version 2>&1 | head -1 || echo "not installed")

=== GO ===
Go: $(go version 2>/dev/null || echo "not installed")

=== COMPOSER (PHP) ===
Composer: $(composer --version 2>/dev/null | head -1 || echo "not installed")

EOF

#-------------------------------------------------------------------------------
# Other Services
#-------------------------------------------------------------------------------
echo -e "${GREEN}[11/12] Checking other services...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                         OTHER SERVICES
================================================================================

=== CACHING ===
Redis: $(redis-server --version 2>/dev/null || echo "not installed")
Memcached: $(memcached -h 2>&1 | head -1 || echo "not installed")

=== SEARCH ===
Elasticsearch: $(curl -s localhost:9200 2>/dev/null | grep "version" | head -1 || echo "not installed/running")

=== MONITORING ===
Nagios: $(rpm -q nagios 2>/dev/null || echo "not installed")
Zabbix: $(rpm -q zabbix-server 2>/dev/null || echo "not installed")
Munin: $(rpm -q munin 2>/dev/null || echo "not installed")

=== BACKUP ===
Bacula: $(rpm -q bacula-director 2>/dev/null || echo "not installed")

=== VERSION CONTROL ===
Git: $(git --version 2>/dev/null || echo "not installed")

=== CONTAINERS ===
Docker: $(docker --version 2>/dev/null || echo "not installed")

EOF

#-------------------------------------------------------------------------------
# All Enabled Services
#-------------------------------------------------------------------------------
echo -e "${GREEN}[12/12] Listing all enabled services...${NC}"

cat << EOF >> "$REPORT_FILE"
================================================================================
                      ALL ENABLED SERVICES
================================================================================

$(systemctl list-unit-files --type=service --state=enabled 2>/dev/null | grep enabled)

================================================================================
                      ALL RUNNING SERVICES
================================================================================

$(systemctl list-units --type=service --state=running 2>/dev/null | grep running)

================================================================================
                    THIRD-PARTY REPOSITORIES
================================================================================

$(yum repolist 2>/dev/null)

================================================================================
                    NON-STANDARD PACKAGES
================================================================================

Packages not from base/updates/extras:
$(yum list installed 2>/dev/null | grep -vE "@base|@updates|@extras|@anaconda" | tail -50)

================================================================================
                         END OF REPORT
================================================================================
EOF

#-------------------------------------------------------------------------------
# Create summary for easy reading
#-------------------------------------------------------------------------------
SUMMARY_FILE="$REPORT_DIR/SUMMARY.txt"

cat << EOF > "$SUMMARY_FILE"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    QUICK SUMMARY - SHARE THIS                                ║
╚══════════════════════════════════════════════════════════════════════════════╝

Server: $(hostname) ($(hostname -I | awk '{print $1}'))
OS: $(cat /etc/redhat-release)

=== KEY SOFTWARE VERSIONS ===

Web Server:
  • Apache: $(httpd -v 2>/dev/null | head -1 | awk '{print $3}' || echo "N/A")
  • Nginx: $(nginx -v 2>&1 | awk -F/ '{print $2}' || echo "N/A")

PHP:
  • Version: $(php -v 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A")
  • Modules: $(php -m 2>/dev/null | wc -l) loaded

Database:
  • MariaDB/MySQL: $(mysql --version 2>/dev/null | awk '{print $5}' | tr -d ',' || echo "N/A")

Mail:
  • Postfix: $(postconf -d mail_version 2>/dev/null | awk '{print $3}' || echo "N/A")
  • Dovecot: $(dovecot --version 2>/dev/null | awk '{print $1}' || echo "N/A")

Control Panel:
  • Webmin: $(cat /etc/webmin/version 2>/dev/null || echo "N/A")
  • Virtualmin: $(rpm -q virtualmin-base 2>/dev/null || echo "GPL")
  • Domains: $(virtualmin list-domains --name-only 2>/dev/null | wc -l)

Other:
  • BIND DNS: $(named -v 2>/dev/null | awk '{print $2}' || echo "N/A")
  • ProFTPd: $(proftpd -v 2>/dev/null | awk '{print $3}' || echo "N/A")
  • Fail2ban: $(rpm -q fail2ban 2>/dev/null | sed 's/fail2ban-//' || echo "N/A")
  • Certbot: $(rpm -q certbot 2>/dev/null | sed 's/certbot-//' || echo "N/A")
  • Node.js: $(node --version 2>/dev/null || echo "N/A")
  • Python3: $(python3 --version 2>&1 | awk '{print $2}' || echo "N/A")
  • Git: $(git --version 2>/dev/null | awk '{print $3}' || echo "N/A")
  • Redis: $(redis-server --version 2>/dev/null | awk '{print $3}' | tr -d 'v=' || echo "N/A")
  • Composer: $(composer --version 2>/dev/null | awk '{print $3}' || echo "N/A")

=== DOMAINS ===
$(virtualmin list-domains --name-only 2>/dev/null || echo "No domains found")

=== NON-STANDARD/CUSTOM PACKAGES TO NOTE ===
(Review full report for complete list)

EOF

# Add any custom repos
echo "" >> "$SUMMARY_FILE"
echo "=== CUSTOM REPOSITORIES ===" >> "$SUMMARY_FILE"
ls /etc/yum.repos.d/*.repo 2>/dev/null | xargs -I {} basename {} | grep -v "CentOS" >> "$SUMMARY_FILE" || true

#-------------------------------------------------------------------------------
# Final output
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 AUDIT COMPLETE!                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Reports generated:"
echo -e "  ${BLUE}$SUMMARY_FILE${NC} (share this)"
echo -e "  ${BLUE}$REPORT_FILE${NC} (detailed)"
echo ""
echo "To view the summary:"
echo "  cat $SUMMARY_FILE"
echo ""
echo "To copy and share:"
echo "  cat $SUMMARY_FILE | less"
echo ""
echo -e "${YELLOW}Please share the SUMMARY.txt content so I can help create${NC}"
echo -e "${YELLOW}custom installation scripts for your specific setup.${NC}"
echo ""

# Display summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
cat "$SUMMARY_FILE"
echo "═══════════════════════════════════════════════════════════════"
