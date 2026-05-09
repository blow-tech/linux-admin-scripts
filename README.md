# 🐧 Linux Admin Scripts

A production-ready collection of Bash scripts for Linux system administration — monitoring, alerting, backup, maintenance, and security auditing.

> All scripts include centralized Slack/Teams/Email alerting, lock files, log rotation, and proper error handling.

---

## 📁 Repository Structure

```
linux-admin-scripts/
└── scripts/
    ├── core/               ← Shared alert engine (load this first)
    ├── audit/              ← Security & system auditing
    ├── monitoring/         ← Resource & service monitoring
    ├── backup/             ← Backup & rotation scripts
    └── maintenance/        ← Cleanup & housekeeping
```

---

## 🔔 Core

| Script | Description | Risk Level |
|---|---|---|
| `scripts/core/alert_engine.sh` | Central alerting module — Slack, MS Teams, Email. Sourced by all other scripts. Also provides lock files and log rotation. | Read-only |

**Configure this first** before running any other script. Set your Slack webhook, Teams webhook, or email inside this file.

---

## 🔍 Audit

| Script | Description | Risk Level |
|---|---|---|
| `scripts/audit/LinuxAudit.sh` | Collects Linux system audit information — users, services, packages, network details, and configuration data. | Read-only / information gathering |

---

## 📊 Monitoring

| Script | Description | Risk Level |
|---|---|---|
| `scripts/monitoring/server-stats.sh` | Displays server statistics — CPU, memory, disk usage, uptime, and running processes. | Read-only |
| `scripts/monitoring/cpu_memory_monitor.sh` | Monitors CPU and memory usage. Sends WARNING/CRITICAL alerts when thresholds are exceeded. Uses `vmstat` and `/proc/meminfo` for accuracy. | Read-only |
| `scripts/monitoring/disk_alert.sh` | Monitors all disk mountpoints. Two alert levels: WARNING at 75%, CRITICAL at 90%. Skips tmpfs/devtmpfs. | Read-only |
| `scripts/monitoring/service_uptime_checker.sh` | Checks critical services (nginx, docker, mysql). Auto-restarts if down, retries N times, escalates to CRITICAL alert with journal logs if restart fails. | Read/Write (restarts services) |
| `scripts/monitoring/system_resource_check.sh` | Full hourly system snapshot — CPU, RAM, swap, disk, top processes, network connections, last logins. Saves report to log file. | Read-only |

---

## 💾 Backup

| Script | Description | Risk Level |
|---|---|---|
| `scripts/backup/backup_rotation.sh` | Daily + weekly backup with rotation. Pre-flight checks for source directory and free disk space. Alerts on failure. | Read/Write |
| `scripts/backup/backup_script.sh` | Compressed backup with archive integrity verification (`tar -tzf`). Cleans backups older than N days. | Read/Write |

---

## 🧹 Maintenance

| Script | Description | Risk Level |
|---|---|---|
| `scripts/maintenance/log_cleanup.sh` | Deletes log files older than N days. Optional `--archive` flag compresses logs before deletion. Protects `audit.log` and `secure.log`. | Read/Write (deletes files) |

---

## ⚙️ Setup

### 1. Clone the repository

```bash
git clone https://github.com/blow-tech/linux-admin-scripts.git
cd linux-admin-scripts
```

### 2. Deploy to server

```bash
sudo mkdir -p /opt/admin-scripts
sudo cp -r scripts/* /opt/admin-scripts/
sudo chmod +x /opt/admin-scripts/**/*.sh
sudo mkdir -p /var/log/admin-scripts
```

### 3. Configure alerts

Edit `/opt/admin-scripts/core/alert_engine.sh`:

```bash
SLACK_ENABLED=true
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

TEAMS_ENABLED=true
TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/YOUR-WEBHOOK-URL"

SMTP_CONFIGURED=true
ALERT_EMAIL="admin@yourcompany.com"
```

### 4. Make scripts executable

```bash
chmod +x scripts/monitoring/cpu_memory_monitor.sh
chmod +x scripts/monitoring/disk_alert.sh
chmod +x scripts/monitoring/service_uptime_checker.sh
chmod +x scripts/monitoring/system_resource_check.sh
chmod +x scripts/backup/backup_rotation.sh
chmod +x scripts/backup/backup_script.sh
chmod +x scripts/maintenance/log_cleanup.sh
chmod +x scripts/core/alert_engine.sh
```

### 5. Run a script

```bash
./scripts/monitoring/cpu_memory_monitor.sh
./scripts/monitoring/disk_alert.sh
./scripts/audit/LinuxAudit.sh
./scripts/backup/backup_rotation.sh
./scripts/maintenance/log_cleanup.sh /var/log 14 --archive
```

---

## ⏰ Recommended Crontab

```bash
sudo crontab -e
```

```cron
# CPU & Memory — every 5 minutes
*/5 * * * * /opt/admin-scripts/monitoring/cpu_memory_monitor.sh

# Disk Alert — every 30 minutes
*/30 * * * * /opt/admin-scripts/monitoring/disk_alert.sh

# Service Health — every 5 minutes
*/5 * * * * /opt/admin-scripts/monitoring/service_uptime_checker.sh

# System Resource Snapshot — every hour
0 * * * * /opt/admin-scripts/monitoring/system_resource_check.sh

# Daily Backup — 2AM every day
0 2 * * * /opt/admin-scripts/backup/backup_rotation.sh

# Log Cleanup — 3AM every Sunday
0 3 * * 0 /opt/admin-scripts/maintenance/log_cleanup.sh /var/log 14 --archive
```

---

## 📋 Log Files

All logs are written to `/var/log/admin-scripts/`:

| File | Contents |
|---|---|
| `alerts.log` | All alerts from all scripts |
| `cpu_memory_monitor.log` | CPU/memory check history |
| `disk_alert.log` | Disk usage check history |
| `service_uptime_checker.log` | Service status & restart history |
| `system_resource_check.log` | Hourly resource snapshots |
| `backup_rotation.log` | Daily/weekly backup history |
| `backup_script.log` | Backup job history |
| `log_cleanup.log` | Cleanup activity |

---

## 🛡️ Script Safety Features

Every script in this repo includes:

- `set -euo pipefail` — exits immediately on any error
- Lock files — prevents duplicate cron executions
- Log rotation — log files are capped automatically
- Pre-flight validation — checks directories and disk space before acting
- Alert integration — every failure sends a real-time notification

---

## 👤 Author

**Prashanth Teja Vankala**  
Linux System Administrator  
GitHub: [@blow-tech](https://github.com/blow-tech)
