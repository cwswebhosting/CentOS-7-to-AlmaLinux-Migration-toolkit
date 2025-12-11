# 🚀 QUICK START GUIDE: CentOS 7 to AlmaLinux 8 Migration

## Your Current Situation

- **OS**: CentOS 7.9.2009 (EOL - End of Life)
- **Status**: ⚠️ No longer receiving security updates
- **Services**: Webmin, Virtualmin, Apache, MariaDB, Mail Server

## 📋 Migration Options Summary

| Method | Risk | Best For |
|--------|------|----------|
| **Fresh Install + Virtualmin Restore** | ✅ Lowest | Production servers (RECOMMENDED) |
| **ELevate In-Place Upgrade** | ⚠️ Medium | Dev/test servers |

---

## ✅ RECOMMENDED: Fresh Install Method

This is the safest approach for production servers.

### Step 1: On CentOS 7 Server - Create Backups

```bash
# Make scripts executable
chmod +x *.sh

# 1. Audit current system
./01-pre-migration-audit.sh

# 2. Create full backup
./02-full-backup.sh

# 3. Create Virtualmin backup (most important!)
./03-virtualmin-backup.sh

# Backups are in /root/migration-backup/
```

### Step 2: Provision New AlmaLinux 8 Server

- Get a new VPS/server with AlmaLinux 8
- Ensure adequate disk space (check audit report)
- Same or larger RAM than current server

### Step 3: On New Server - Setup & Restore

```bash
# 1. Copy scripts to new server
scp *.sh root@NEW_SERVER_IP:/root/

# 2. Copy backups to new server (from old server)
scp -r /root/migration-backup/* root@NEW_SERVER_IP:/root/migration-restore/

# 3. On new server: Setup Virtualmin
./05-new-server-setup.sh

# 4. Restore domains
./06-restore-migration.sh

# 5. Verify everything
./07-post-migration-verify.sh
```

### Step 4: Testing (Before DNS Change)

```bash
# Add to your LOCAL computer's /etc/hosts:
NEW_SERVER_IP  yourdomain.com www.yourdomain.com

# Test in browser, test email, etc.
```

### Step 5: Go Live

1. Update DNS A records to new server IP
2. Wait for propagation (15 min - 48 hours)
3. Monitor for issues
4. Keep old server for 1-2 weeks as fallback

---

## ⚠️ ALTERNATIVE: ELevate In-Place Upgrade

Only use this if you can't provision a new server.

```bash
# Make sure you have full backups first!
./02-full-backup.sh
./03-virtualmin-backup.sh

# Then run ELevate upgrade
./04-elevate-upgrade.sh
```

**Risks:**
- May break Virtualmin configuration
- Longer downtime
- Harder to rollback

---

## 📞 Troubleshooting

### Website Not Working After Migration

```bash
# Check Apache configuration
httpd -t

# Check virtual host
httpd -S | grep yourdomain.com

# Check permissions
virtualmin validate-domains --domain yourdomain.com --all-features
```

### Email Not Working

```bash
# Check mail services
systemctl status postfix dovecot

# Check mail logs
tail -f /var/log/maillog

# Test sending
echo "Test" | mail -s "Test" you@example.com
```

### SSL Certificate Issues

```bash
# Renew/Request new certificate
virtualmin generate-letsencrypt-cert --domain yourdomain.com

# Check certificate
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
```

### Database Connection Issues

```bash
# Check MariaDB
systemctl status mariadb

# Test connection
mysql -u root -p

# Check user permissions
mysql -e "SELECT User, Host FROM mysql.user;"
```

---

## 📁 Files Included

| Script | Purpose | Run On |
|--------|---------|--------|
| `01-pre-migration-audit.sh` | System audit | CentOS 7 |
| `02-full-backup.sh` | Full system backup | CentOS 7 |
| `03-virtualmin-backup.sh` | Virtualmin domains backup | CentOS 7 |
| `04-elevate-upgrade.sh` | In-place upgrade (risky) | CentOS 7 |
| `05-new-server-setup.sh` | Fresh server setup | AlmaLinux 8 |
| `06-restore-migration.sh` | Restore from backup | AlmaLinux 8 |
| `07-post-migration-verify.sh` | Verify migration | AlmaLinux 8 |
| `transfer-backups.sh` | Transfer helper | CentOS 7 |

---

## ⏱️ Estimated Timeline

| Phase | Duration |
|-------|----------|
| Audit & Backup | 30-60 minutes |
| New Server Setup | 20-30 minutes |
| Backup Transfer | Depends on data size |
| Restore | 30-60 minutes |
| Testing | 1-4 hours |
| DNS Propagation | 15 min - 48 hours |

**Total minimum downtime**: 30 minutes (if using fresh install method with DNS switch)

---

## 🆘 Need Help?

- **AlmaLinux Forums**: https://forums.almalinux.org/
- **Virtualmin Forums**: https://forum.virtualmin.com/
- **ELevate Docs**: https://wiki.almalinux.org/elevate/

---

## ✅ Pre-Migration Checklist

- [ ] Run audit script and review output
- [ ] Create full backup
- [ ] Create Virtualmin backup
- [ ] Verify backup integrity
- [ ] Copy backups to external storage
- [ ] Document current server IP and DNS settings
- [ ] Note any custom configurations
- [ ] Plan maintenance window
- [ ] Notify users of potential downtime

## ✅ Post-Migration Checklist

- [ ] All websites loading correctly
- [ ] SSL certificates valid
- [ ] Email sending works
- [ ] Email receiving works
- [ ] Databases accessible
- [ ] Cron jobs running
- [ ] Backups configured on new server
- [ ] Monitoring set up
- [ ] Old server kept as fallback
