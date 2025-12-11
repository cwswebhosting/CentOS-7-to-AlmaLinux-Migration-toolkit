#!/bin/bash
#===============================================================================
# Script: 07-post-migration-verify.sh
# Purpose: Verify migration was successful and identify any issues
# Author: Migration Toolkit
# Usage: sudo ./07-post-migration-verify.sh
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_FILE="/root/migration-verification-$(date +%Y%m%d-%H%M%S).txt"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          POST-MIGRATION VERIFICATION                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Initialize counters
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Functions
pass() {
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    echo "PASS: $1" >> "$REPORT_FILE"
    ((PASS_COUNT++))
}

warn() {
    echo -e "  ${YELLOW}! WARN${NC}: $1"
    echo "WARN: $1" >> "$REPORT_FILE"
    ((WARN_COUNT++))
}

fail() {
    echo -e "  ${RED}✗ FAIL${NC}: $1"
    echo "FAIL: $1" >> "$REPORT_FILE"
    ((FAIL_COUNT++))
}

#-------------------------------------------------------------------------------
# System Information
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/8] System Information${NC}"
echo "========================="
echo ""

echo "Hostname: $(hostname)" | tee -a "$REPORT_FILE"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')" | tee -a "$REPORT_FILE"
echo "Kernel: $(uname -r)" | tee -a "$REPORT_FILE"
echo "IP: $(hostname -I | awk '{print $1}')" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

#-------------------------------------------------------------------------------
# Service Status
#-------------------------------------------------------------------------------
echo -e "${GREEN}[2/8] Service Status${NC}"
echo "====================="
echo ""

SERVICES="httpd mariadb postfix dovecot webmin named php-fpm"

for svc in $SERVICES; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        if systemctl is-active --quiet $svc; then
            pass "$svc is running"
        else
            if systemctl is-enabled --quiet $svc 2>/dev/null; then
                fail "$svc is not running (but enabled)"
            else
                warn "$svc is not running (and not enabled)"
            fi
        fi
    fi
done

#-------------------------------------------------------------------------------
# Virtual Hosts / Domains
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/8] Virtual Hosts / Domains${NC}"
echo "==============================="
echo ""

if command -v virtualmin &> /dev/null; then
    DOMAINS=$(virtualmin list-domains --name-only 2>/dev/null)
    DOMAIN_COUNT=$(echo "$DOMAINS" | grep -v "^$" | wc -l)
    
    if [ "$DOMAIN_COUNT" -gt 0 ]; then
        pass "Found $DOMAIN_COUNT domains in Virtualmin"
        echo ""
        echo "Domains:" | tee -a "$REPORT_FILE"
        
        echo "$DOMAINS" | while read domain; do
            if [ -n "$domain" ]; then
                echo "  - $domain" | tee -a "$REPORT_FILE"
                
                # Check if website is accessible
                DOC_ROOT=$(virtualmin list-domains --domain "$domain" --multiline 2>/dev/null | grep "Home directory" | awk '{print $NF}')
                if [ -d "$DOC_ROOT/public_html" ]; then
                    if [ -f "$DOC_ROOT/public_html/index.html" ] || [ -f "$DOC_ROOT/public_html/index.php" ]; then
                        echo "      └─ Web files present" | tee -a "$REPORT_FILE"
                    fi
                fi
            fi
        done
    else
        warn "No domains found in Virtualmin"
    fi
else
    warn "Virtualmin not installed"
fi

#-------------------------------------------------------------------------------
# Apache Configuration
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/8] Apache Configuration${NC}"
echo "============================"
echo ""

if command -v httpd &> /dev/null; then
    # Test configuration
    if httpd -t 2>&1 | grep -q "Syntax OK"; then
        pass "Apache configuration syntax OK"
    else
        fail "Apache configuration has errors"
        httpd -t 2>&1 | head -5
    fi
    
    # Count virtual hosts
    VHOST_COUNT=$(httpd -S 2>&1 | grep -c "namevhost" || echo "0")
    if [ "$VHOST_COUNT" -gt 0 ]; then
        pass "Apache has $VHOST_COUNT virtual hosts configured"
    else
        warn "No Apache virtual hosts found"
    fi
fi

#-------------------------------------------------------------------------------
# Database Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/8] Database Check${NC}"
echo "====================="
echo ""

if command -v mysql &> /dev/null; then
    if mysql -e "SELECT 1" &>/dev/null; then
        pass "MySQL/MariaDB connection successful"
        
        # Count databases
        DB_COUNT=$(mysql -N -e "SHOW DATABASES" | grep -vcE "^(information_schema|performance_schema|mysql|sys)$")
        if [ "$DB_COUNT" -gt 0 ]; then
            pass "Found $DB_COUNT user databases"
            echo ""
            echo "Databases:" | tee -a "$REPORT_FILE"
            mysql -N -e "SHOW DATABASES" | grep -vE "^(information_schema|performance_schema|mysql|sys)$" | while read db; do
                SIZE=$(mysql -N -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.TABLES WHERE table_schema = '$db'")
                echo "  - $db (${SIZE}MB)" | tee -a "$REPORT_FILE"
            done
        else
            warn "No user databases found"
        fi
    else
        fail "Cannot connect to MySQL/MariaDB"
    fi
fi

#-------------------------------------------------------------------------------
# Mail Server Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/8] Mail Server Check${NC}"
echo "========================"
echo ""

# Postfix
if command -v postfix &> /dev/null; then
    if postfix status &>/dev/null; then
        pass "Postfix is running"
    else
        fail "Postfix is not running"
    fi
    
    # Check mail queue
    QUEUE_COUNT=$(postqueue -p 2>/dev/null | tail -1 | grep -oE "[0-9]+ Request" | awk '{print $1}' || echo "0")
    if [ "$QUEUE_COUNT" == "0" ] || [ -z "$QUEUE_COUNT" ]; then
        pass "Mail queue is empty"
    else
        warn "Mail queue has $QUEUE_COUNT messages"
    fi
fi

# Dovecot
if command -v dovecot &> /dev/null; then
    if pidof dovecot &>/dev/null; then
        pass "Dovecot is running"
    else
        fail "Dovecot is not running"
    fi
fi

# Test SMTP
if nc -z localhost 25 2>/dev/null; then
    pass "SMTP port 25 is listening"
else
    fail "SMTP port 25 is not listening"
fi

# Test IMAP
if nc -z localhost 143 2>/dev/null; then
    pass "IMAP port 143 is listening"
else
    warn "IMAP port 143 is not listening"
fi

#-------------------------------------------------------------------------------
# SSL Certificates
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/8] SSL Certificates${NC}"
echo "======================="
echo ""

if [ -d /etc/letsencrypt/live ]; then
    CERT_COUNT=$(ls -1 /etc/letsencrypt/live 2>/dev/null | wc -l)
    if [ "$CERT_COUNT" -gt 0 ]; then
        pass "Found $CERT_COUNT SSL certificate(s)"
        echo ""
        echo "Certificates:" | tee -a "$REPORT_FILE"
        
        for cert_dir in /etc/letsencrypt/live/*/; do
            if [ -d "$cert_dir" ]; then
                domain=$(basename "$cert_dir")
                if [ "$domain" != "README" ]; then
                    if [ -f "${cert_dir}cert.pem" ]; then
                        EXPIRY=$(openssl x509 -enddate -noout -in "${cert_dir}cert.pem" 2>/dev/null | cut -d= -f2)
                        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
                        NOW_EPOCH=$(date +%s)
                        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
                        
                        if [ "$DAYS_LEFT" -lt 0 ]; then
                            echo "  - $domain: ${RED}EXPIRED${NC}" | tee -a "$REPORT_FILE"
                            fail "Certificate for $domain is expired"
                        elif [ "$DAYS_LEFT" -lt 30 ]; then
                            echo "  - $domain: ${YELLOW}Expires in $DAYS_LEFT days${NC}" | tee -a "$REPORT_FILE"
                            warn "Certificate for $domain expires in $DAYS_LEFT days"
                        else
                            echo "  - $domain: ${GREEN}Valid ($DAYS_LEFT days)${NC}" | tee -a "$REPORT_FILE"
                        fi
                    fi
                fi
            fi
        done
    else
        warn "No Let's Encrypt certificates found"
    fi
else
    warn "Let's Encrypt directory not found"
fi

#-------------------------------------------------------------------------------
# Disk Space
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[8/8] Disk Space${NC}"
echo "================="
echo ""

ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$ROOT_USAGE" -lt 80 ]; then
    pass "Root partition usage: ${ROOT_USAGE}%"
elif [ "$ROOT_USAGE" -lt 90 ]; then
    warn "Root partition usage: ${ROOT_USAGE}%"
else
    fail "Root partition usage: ${ROOT_USAGE}% - Low disk space!"
fi

echo ""
df -h | grep -E "^/dev|Filesystem" | tee -a "$REPORT_FILE"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    VERIFICATION SUMMARY                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}PASS${NC}: $PASS_COUNT"
echo -e "  ${YELLOW}WARN${NC}: $WARN_COUNT"
echo -e "  ${RED}FAIL${NC}: $FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}Migration appears successful!${NC}"
else
    echo -e "${RED}There are $FAIL_COUNT issues that need attention.${NC}"
fi

echo ""
echo "Full report saved to: $REPORT_FILE"
echo ""

#-------------------------------------------------------------------------------
# Recommendations
#-------------------------------------------------------------------------------
echo -e "${YELLOW}RECOMMENDATIONS:${NC}"
echo ""

if [ "$WARN_COUNT" -gt 0 ] || [ "$FAIL_COUNT" -gt 0 ]; then
    echo "1. Review and fix any FAIL items above"
    echo ""
fi

echo "2. Test each website manually by browsing to them"
echo ""
echo "3. Send test emails to/from each domain"
echo ""
echo "4. Update DNS records when ready:"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "   Change A records to point to: $SERVER_IP"
echo ""
echo "5. If SSL certificates expired, renew them:"
echo "   virtualmin generate-letsencrypt-cert --domain DOMAIN --renew"
echo ""
echo "6. Monitor logs for errors:"
echo "   tail -f /var/log/httpd/error_log"
echo "   tail -f /var/log/maillog"
echo ""
echo "7. Keep old server running for 1-2 weeks as fallback"
echo ""
