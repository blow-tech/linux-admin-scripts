# Linux Admin Scripts

9 September continuation: shared backup publication now refuses existing checksum files, symlinks and directories. Both daily and weekly paths publish checksums with no-clobber hard links; a checksum-generation failure cannot report a verified backup. Interrupted publication may still leave an archive without its final checksum, so require a valid checksum pair and investigate retained partial artifacts. This adds two isolated regression tests (12 total); application-consistent restoration remains a lab gate.

Bash administration utilities. Validate each script in a disposable lab before production deployment. Syntax checks and fixture tests do not certify an environment or an application backup.

## Entry points

Use `bash <script-path>`; several maintained entry points intentionally have no `.sh` extension.

| Path | Behavior and scope |
| --- | --- |
| `scripts/monitoring/server-stats.sh` | Local statistics snapshot; unchanged in the September remediation. |
| `scripts/monitoring/cpu_memory_monitor` | CPU/memory observations; local log and stderr alerts. |
| `scripts/monitoring/disk_alert` | One GNU df collection; warning/critical or unavailable collection returns nonzero. |
| `scripts/monitoring/service_uptime <unit> ...` | Explicit service scope, alert-only; never restarts a service. |
| `scripts/backup/backup_script <source> <existing-destination>` | Verified, versioned file archive; retention inventory only. |
| `scripts/backup/backup_rotation.sh` | Versioned daily/weekly archives; requires SRC_DIR, BACKUP_DIR and EXPECTED_BACKUP_SOURCE. |
| `scripts/Nginx_create.sh <dns-name> <template> <owner>` | Configuration preview. `--apply` installs and validates; `--reload` additionally reloads Nginx. |
| `scripts/appache2_confg.sh --plan` | Apache installation plan. `--install` is explicit and may start Apache; never changes UFW. |
| `scripts/audit/LinuxAudit.sh` | Interactive audit. Expensive filesystem scans are opt-in and bounded. |
| `scripts/audit/FastCheck.sh <host> --scan` | Explicitly authorized TLS/connectivity checks; intrusive NSE/DoS menu removed. |
| `scripts/audit/ScanPort.sh <IPv4> --scan` | Explicitly authorized checks of the 24 listed TCP ports. |

The previously documented `system_resource_check` and `maintenance/log_cleanup` scripts are not supplied. Remove references to those nonexistent paths from deployment plans.

## Alerts, state, and privileges

`scripts/core/alert_engine.sh` supplies locking, log archival, and timestamped **local stderr alerts only**. It does not send Slack, Teams or email. Integrate stdout/stderr and exit status with your approved monitoring system; external delivery is not configured by this repository. The CPU monitor also writes `/var/log/admin-scripts`; provision that protected log directory before deployment. Log archives are retained; configure a separate reviewed retention policy.

Locks use `${XDG_STATE_HOME:-$HOME/.local/state}/admin-scripts`, or `ADMIN_SCRIPTS_STATE_DIR`. The state directory must be owned by the executing account, mode 700, with trusted ancestors. Backup directories and configuration parents must be protected against concurrent untrusted writers. Do not run from or deploy into user-writable directories as root.

Monitoring needs read access to the selected objects. Backup needs read access to the source and write access to the destination. Nginx `--apply` and Apache `--install` require root and an approved change window. Scan commands contact their target; target-owner approval is required.

## Backup configuration and migration

1. Provision an existing, protected destination and verify the intended mounted device. Read-only check: `findmnt -n -o SOURCE -T <BackupDirectory>`.
2. Pin the reviewed value in `EXPECTED_BACKUP_SOURCE`; do not dynamically accept whichever device is mounted at runtime.
3. Set the source/destination explicitly. Archives include a source-path job identifier and unique timestamp/PID; old daily files are never accepted merely because they exist.
4. Creation writes to `.partial.*`, checks gzip/tar integrity, then publishes without overwriting an existing archive and writes a SHA256 sidecar. Failures retain clearly marked partial artifacts and return nonzero.
5. Retention prints job-specific, nonrecursive candidates; it never deletes previous backups. Review retention and capacity separately. Existing legacy archives are retained.
6. Test restoration into an isolated directory and compare representative files, metadata, ACLs and application consistency. These are file archives, not consistent live-database backups; this implementation does not promise ACL/xattr preservation. Use an application-aware backup when required.

Weekly filenames include the ISO week-year. Publication requires same-filesystem hard-link support. Interrupted runs after publication but before the sidecar completes must be investigated; do not infer completion from filename alone. No automatic cleanup of failed artifacts is performed.

## Configuration changes

Nginx defaults to stdout preview. Templates are operator-supplied and must be reviewed, including certificate paths and any includes. Existing web roots/sites are refused. Applying checks the baseline first, creates only the new targets, tests the complete configuration, and rolls back only those new targets on failure. Ownership changes are limited to the newly created directory. If `--reload` fails, the previous file configuration is restored and a rollback reload is attempted; a failure is reported for operator intervention. A successful `--apply` without `--reload` stages the site for the next reload.

Apache installation and firewall activation are separate changes. Before any manual firewall activation, record existing policy, the actual management port/source, console access, rollback commands, and an independent management-session validation. This script does not activate the firewall.

For filesystem audit scans, set `ENABLE_FILESYSTEM_SCAN=1` and an explicit absolute `AUDIT_SCAN_ROOT` only after approving metadata I/O. Results can be incomplete on permission errors or timeout and must be reviewed accordingly.

## Validation

`python3 -m unittest discover -s tests -v` performs Bash syntax validation, local backup creation/restore fixtures, and mocked systemctl/df/configuration-preview checks. It makes no production calls. GitHub Actions runs the same tests. Nginx reload/rollback, full disks, application restore, production mounts and notification delivery still require environment-specific lab validation.

The September 2026 remediation corresponds to review findings H2-H5, H9, M1-M2 and the identified Linux performance items. See the pull request for exact validation evidence. Keep existing deployments pinned until their schedule and parameters have been migrated and approved.
