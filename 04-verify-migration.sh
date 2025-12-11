#!/bin/bash
#===============================================================================
# Script: 04-verify-migration.sh
# Purpose: Verify migration was successful
# Run On: OLD SERVER (after restore on AlmaLinux 8)
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT="/root/migration-verification-$(date +%Y%m%d-%H%M%S).txt"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          POST-MIGRATION VERIFICATION                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Counters
PASS=0
WARN=0
FAIL=0

pass() { echo -e "  ${GREEN}✓ PASS${NC}: $1"; ((PASS++)); echo "PASS: $1" >> "$REPORT"; }
warn() { echo -e "  ${YELLOW}! WARN${NC}: $1"; ((WARN++)); echo "WARN: $1" >> "$REPORT"; }
fail() { echo -e "  ${RED}✗ FAIL${NC}: $1"; ((FAIL++)); echo "FAIL: $1" >> "$REPORT"; }

echo "Verification Report - $(date)" > "$REPORT"
echo "Server: $(hostname) - $(hostname -I | awk '{print $1}')" >> "$REPORT"
echo "" >> "$REPORT"

#-------------------------------------------------------------------------------
# OS Check
#-------------------------------------------------------------------------------
echo -e "${GREEN}[1/7] Operating System${NC}"

if grep -qE "AlmaLinux.*8\." /etc/os-release 2>/dev/null; then
    pass "AlmaLinux 8 is installed"
else
    fail "Expected AlmaLinux 8"
fi

#-------------------------------------------------------------------------------
# Services Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[2/7] Core Services${NC}"

for svc in httpd mariadb postfix dovecot webmin; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        pass "$svc is running"
    else
        fail "$svc is NOT running"
    fi
done

#-------------------------------------------------------------------------------
# Apache Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[3/7] Apache Configuration${NC}"

if httpd -t 2>&1 | grep -q "Syntax OK"; then
    pass "Apache config syntax OK"
else
    fail "Apache config has errors"
fi

VHOSTS=$(httpd -S 2>&1 | grep -c "namevhost" || echo 0)
if [ "$VHOSTS" -gt 0 ]; then
    pass "Apache has $VHOSTS virtual hosts"
else
    warn "No Apache virtual hosts found"
fi

#-------------------------------------------------------------------------------
# Database Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[4/7] Database${NC}"

if mysql -e "SELECT 1" &>/dev/null; then
    pass "MySQL connection OK"
    DB_COUNT=$(mysql -N -e "SHOW DATABASES" | grep -vcE "^(information_schema|performance_schema|mysql|sys)$")
    if [ "$DB_COUNT" -gt 0 ]; then
        pass "Found $DB_COUNT user databases"
    else
        warn "No user databases found"
    fi
else
    fail "Cannot connect to MySQL"
fi

#-------------------------------------------------------------------------------
# Virtualmin Domains
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[5/7] Virtualmin Domains${NC}"

if command -v virtualmin &> /dev/null; then
    DOMAINS=$(virtualmin list-domains --name-only 2>/dev/null | grep -v "^$" | wc -l)
    if [ "$DOMAINS" -gt 0 ]; then
        pass "Found $DOMAINS domains in Virtualmin"
        echo ""
        echo "  Domains:"
        virtualmin list-domains --name-only 2>/dev/null | while read d; do
            [ -n "$d" ] && echo "    - $d"
        done
    else
        warn "No domains found"
    fi
else
    fail "Virtualmin not installed"
fi

#-------------------------------------------------------------------------------
# Mail Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[6/7] Mail Server${NC}"

# SMTP
if nc -z localhost 25 2>/dev/null; then
    pass "SMTP port 25 listening"
else
    fail "SMTP port 25 not listening"
fi

# IMAP
if nc -z localhost 143 2>/dev/null; then
    pass "IMAP port 143 listening"
else
    warn "IMAP port 143 not listening"
fi

#-------------------------------------------------------------------------------
# SSL Check
#-------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}[7/7] SSL Certificates${NC}"

if [ -d /etc/letsencrypt/live ]; then
    CERTS=$(ls /etc/letsencrypt/live 2>/dev/null | grep -v README | wc -l)
    if [ "$CERTS" -gt 0 ]; then
        pass "Found $CERTS SSL certificate(s)"
        
        # Check expiry
        for dir in /etc/letsencrypt/live/*/; do
            if [ -f "${dir}cert.pem" ]; then
                domain=$(basename "$dir")
                expiry=$(openssl x509 -enddate -noout -in "${dir}cert.pem" 2>/dev/null | cut -d= -f2)
                days_left=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))
                if [ "$days_left" -lt 0 ]; then
                    warn "Certificate for $domain EXPIRED"
                elif [ "$days_left" -lt 30 ]; then
                    warn "Certificate for $domain expires in $days_left days"
                fi
            fi
        done
    else
        warn "No SSL certificates found"
    fi
else
    warn "Let's Encrypt not configured"
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Results: ${GREEN}$PASS PASS${NC} | ${YELLOW}$WARN WARN${NC} | ${RED}$FAIL FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}✓ Migration appears successful!${NC}"
else
    echo -e "${RED}✗ There are $FAIL issues to address${NC}"
fi

echo ""
echo "Full report: $REPORT"
echo ""
echo -e "${YELLOW}Recommended next steps:${NC}"
echo "  1. Test each website in browser"
echo "  2. Send/receive test emails"
echo "  3. If SSL issues: virtualmin generate-letsencrypt-cert --domain DOMAIN"
echo "  4. Once stable, decommission temporary server"
echo ""
