# Script remediation — 8 November 2026

Continues existing PR #1; nothing merged or deployed. All prior backup/configuration/health fixes are retained.

New changes:
- cpu_memory_monitor: bounded vmstat/free collection, numeric validation, accurate nonzero threshold/UNKNOWN exits, stdout/stderr only. Removes mandatory /var/log writes and duplicated memory reads. Requires procps free with available-memory column.
- server-stats.sh: bounded collectors, propagated failures, no empty-value arithmetic/division or tput dependency. Outputs raw snapshots rather than the former colored layout.
- security-audit.sh: validated arguments, successful help, explicit optional filesystem paths, bounded last-day journal query, errors distinct from no matches. Informational output is not security clearance.
- LinuxAudit.sh: explicit category arguments replace interactive menus; all external collectors bounded; failure returns UNKNOWN. No online package-update probes, implicit file writes or unrestricted home/key scanning. Redirect output only into a protected approved destination. Expensive walks use the dedicated explicitly scoped security-audit interface.

Validation: 30 local isolated tests passed, including 28 retained tests and two new CPU/argument test methods. No real infrastructure calls or notifications. Preserve prior backup/CA/application restore and Nginx apply/rollback lab gates. Collector timeouts are per command, not total storage/output quotas. Migration: use explicit category arguments; monitor all nonzero exit codes. No performance benchmarks; fewer duplicate reads and bounded collectors reduce avoidable work.
