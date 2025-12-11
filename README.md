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
- **Need VPS?**: https://ciscowebservers.com/linux-vps-ssd-hosting-packages/
- **Need Dedicated servers?**: https://ciscowebservers.com/linux-dedicated-servers-hosting-packages/
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


# CentOS 7 to AlmaLinux 8 Migration (Keep Same IP)

## Your Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MIGRATION WORKFLOW                                 │
└─────────────────────────────────────────────────────────────────────────────┘

  PHASE 1: AUDIT & BACKUP (on CentOS 7)
  ┌─────────────────────┐
  │    OLD SERVER       │
  │    CentOS 7         │─────────┐
  │    IP: 1.2.3.4      │         │
  └─────────────────────┘         │
           │                      │ Backup
           │ Run audit            │ Transfer
           ▼                      ▼
  ┌─────────────────────┐   ┌─────────────────────┐
  │ 00-audit-installed  │   │    NEW SERVER       │
  │ 01-backup-to-new    │──►│    (Temporary)      │
  └─────────────────────┘   │    Holds backups    │
                            └─────────────────────┘
                                      │
  PHASE 2: FRESH INSTALL              │
  ┌─────────────────────┐             │
  │    OLD SERVER       │             │
  │    Fresh AlmaLinux 8│             │
  │    IP: 1.2.3.4      │◄────────────┘
  │    (Same IP!)       │    Pull backups back
  └─────────────────────┘
           │
           │ Run setup & restore
           ▼
  ┌─────────────────────┐
  │ 03-setup-fresh      │
  │ 02-restore-from-new │
  │ 04-verify           │
  └─────────────────────┘
           │
           ▼
  ┌─────────────────────┐
  │    OLD SERVER       │
  │    AlmaLinux 8      │
  │    All sites back!  │
  │    Same IP: 1.2.3.4 │
  └─────────────────────┘
```

## Scripts Included

| Script | Run On | Purpose |
|--------|--------|---------|
| `00-audit-installed-apps.sh` | CentOS 7 | Audit all installed apps (share output with me) |
| `01-backup-to-new-server.sh` | CentOS 7 | Backup everything & transfer to temp server |
| `02-restore-from-new-server.sh` | AlmaLinux 8 | Pull backups from temp server & restore |
| `03-setup-fresh-almalinux.sh` | AlmaLinux 8 | Setup Virtualmin on fresh install |
| `04-verify-migration.sh` | AlmaLinux 8 | Verify migration success |

---

## Step-by-Step Instructions

### PHASE 1: On OLD Server (CentOS 7)

#### Step 1: Run Audit
```bash
chmod +x *.sh
./00-audit-installed-apps.sh
```
**→ Share the SUMMARY.txt output with me** so I can create custom scripts for any special packages.

#### Step 2: Backup & Transfer
```bash
./01-backup-to-new-server.sh
```
- Enter the IP of your temporary new server when prompted
- This will backup EVERYTHING and transfer to the new server
- Takes time depending on data size

---

### PHASE 2: Fresh Install AlmaLinux 8

#### Step 3: Install AlmaLinux 8 on OLD Server
- Use your hosting provider's control panel
- Reinstall OS → Select AlmaLinux 8
- **This keeps the same IP address**
- Server will reboot with fresh AlmaLinux 8

---

### PHASE 3: On OLD Server (Fresh AlmaLinux 8)

#### Step 4: Copy Scripts to Fresh Server
From your local machine or the temp server:
```bash
scp *.sh root@YOUR_OLD_SERVER_IP:/root/
```

#### Step 5: Setup Virtualmin
```bash
ssh root@YOUR_OLD_SERVER_IP
chmod +x *.sh
./03-setup-fresh-almalinux.sh
```
- Installs Webmin, Virtualmin, Apache, MariaDB, etc.
- Takes 10-20 minutes

#### Step 6: Restore from Temp Server
```bash
./02-restore-from-new-server.sh TEMP_SERVER_IP
```
- Pulls all backups from temporary server
- Restores Virtualmin domains
- Restores databases, SSL, mail, etc.

#### Step 7: Verify
```bash
./04-verify-migration.sh
```

---

## Timeline Estimate

| Phase | Duration |
|-------|----------|
| Audit | 5 minutes |
| Backup & Transfer | 30-120 minutes (depends on data) |
| Fresh Install | 10-30 minutes |
| Virtualmin Setup | 15-20 minutes |
| Restore | 30-60 minutes |
| Verification | 10 minutes |

**Total Downtime**: ~1-2 hours (during fresh install + restore)

---

## Important Notes

### Before Starting
- [ ] Notify users of maintenance window
- [ ] Verify you have root access to both servers
- [ ] Check temp server has enough disk space
- [ ] Document any custom configurations

### DNS
- **No DNS changes needed!** Same IP = same DNS
- Websites will be available as soon as restore completes

### SSL Certificates
- Let's Encrypt certs are restored from backup
- They may need renewal if expired or if LE detects server change
- Run: `virtualmin generate-letsencrypt-cert --domain DOMAIN --renew`

### Email
- Email service restored automatically
- Mail queue on old server will be lost (send pending before migration)
- New mail will work immediately after restore

---

## Troubleshooting

### Can't SSH to fresh AlmaLinux
- Use hosting provider's console/VNC
- Check firewall: `firewall-cmd --list-all`

### Virtualmin restore fails
- Check disk space: `df -h`
- Review log: `/root/restore-*.log`
- Try individual domain: `virtualmin restore-domain --source /path/to/domain.tar.gz --all-features`

### Website not working
```bash
httpd -t                    # Check Apache config
systemctl status httpd      # Check Apache status
tail -f /var/log/httpd/error_log
```

### Database connection failed
```bash
systemctl status mariadb
mysql -u root -p            # Test connection
```

### Email not working
```bash
systemctl status postfix dovecot
tail -f /var/log/maillog
postqueue -p                # Check mail queue
```

---

## After Migration

1. **Test everything** - websites, email, databases
2. **Monitor logs** for 24-48 hours
3. **Keep temp server** for 1-2 weeks as backup
4. **Decommission temp server** once confirmed stable
5. **Update Webmin/Virtualmin** to latest versions

---


