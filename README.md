# Linux Admin Scripts

Bash scripts for Linux system administration, auditing, monitoring, and server health checks.

## Scripts

### Audit

| Script | Description | Risk Level |
|---|---|---|
| `scripts/audit/LinuxAudit.sh` | Collects Linux system audit information such as users, services, packages, network details, and configuration data. | Read-only / information gathering |

### Monitoring

| Script | Description | Risk Level |
|---|---|---|
| `scripts/monitoring/server-stats.sh` | Displays server statistics such as CPU, memory, disk usage, uptime, and running processes. | Read-only |

## Usage

Clone the repository:

```bash
git clone https://github.com/blow-tech/linux-admin-scripts.git
cd linux-admin-scripts

Make a script executable:

chmod +x scripts/monitoring/server-stats.sh

Run a script:

./scripts/monitoring/server-stats.sh

./scripts/audit/LinuxAudit.sh


Safety

These scripts are intended for learning, lab use, and system administration.

Before running on production systems:

Review the script code.
Test in a lab or non-production system.
Confirm what information is collected.
Avoid publishing generated reports that contain sensitive data.
Requirements
Linux server or workstation
Bash
Standard Linux command-line tools
sudo/root permissions may be required for some audit checks
Disclaimer

Audit outputs may contain sensitive information such as usernames, IP addresses, installed packages, services, and system configuration. Review reports before sharing them.
