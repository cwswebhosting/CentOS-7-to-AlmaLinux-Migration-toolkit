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

## Need Help?

Run the audit script and share the output - I can help create custom scripts for any special software your server needs!
