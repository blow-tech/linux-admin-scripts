#!/usr/bin/env bash
# LinuxAudit - Targeted Security Audit Tool
# Interactive menu: run only what you need

tput clear

ctrl_c() {
  echo ""
  echo "** Ctrl+C detected. Exiting."
  exit 0
}
trap ctrl_c INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/LinuxAudit_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

# ─────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────
print_banner(){
cat << "EOF"
#                                 #
#       # #    # #    # #    #   # #   #    # #####  # #####
#       # ##   # #    #  #  #   #   #  #    # #    # #   #
#       # # #  # #    #   ##   #     # #    # #    # #   #
#       # #  # # #    #   ##   ####### #    # #    # #   #
#       # #   ## #    #  #  #  #     # #    # #    # #   #
####### # #    #  ####  #    # #     #  ####  #####  #   #
EOF
}

print_banner
echo
echo "  Linux Targeted Audit Tool"
echo "  Host: $HOSTNAME  |  Date: $(date)"
echo

# ─────────────────────────────────────────────
# Root check
# ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "WARNING: Not running as root. Some checks will be incomplete."
  echo "For full results: sudo $0"
  echo ""
  read -p "Continue anyway? (y/n): " continue_nonroot
  [[ "$continue_nonroot" =~ ^[Yy]$ ]] || { echo "Exiting."; exit 1; }
  RUNNING_AS_ROOT=false
else
  RUNNING_AS_ROOT=true
fi

# ─────────────────────────────────────────────
# Output mode selection
# ─────────────────────────────────────────────
echo ""
echo "Output Mode:"
echo "  [1] Save to file  ($OUTPUT_FILE)"
echo "  [2] Terminal only"
echo "  [3] Quit"
echo ""
read -p "Select output mode [1/2/3]: " OUTPUT_MODE
echo ""
case "$OUTPUT_MODE" in
  1|2) ;;
  3) echo "Exiting."; exit 0 ;;
  *) echo "Invalid option. Defaulting to terminal."; OUTPUT_MODE=2 ;;
esac

# ─────────────────────────────────────────────
# Output helper — writes to file or terminal
# ─────────────────────────────────────────────
run_audit_section() {
  if [[ "$OUTPUT_MODE" == "1" ]]; then
    "$1" | tee -a "$OUTPUT_FILE"
  else
    "$1"
  fi
}

sep() { printf "\n\e[0;33m ──────────────────────────────────── \e[0m\n"; }
hdr() { printf "\n\e[0;33m[+] %s\e[0m\n" "$1"; sep; }

# ─────────────────────────────────────────────
# AUDIT MODULES
# ─────────────────────────────────────────────

audit_system_info() {
  hdr "Kernel & OS"
  uname -a; echo
  cat /etc/os-release; echo
  sep

  hdr "Uptime"
  uptime; echo
  sep

  hdr "Last Reboots"
  last reboot | head -10; echo
  sep

  hdr "Kernel Messages (last 30)"
  dmesg | tail -n 30; echo
  sep

  hdr "MOTD / Login Banner"
  cat /etc/motd 2>/dev/null || echo "(no /etc/motd)"
  echo
  sep
}

audit_users_groups() {
  hdr "Current User & ID"
  whoami; id; echo
  sep

  hdr "Logged-In Users"
  w; echo
  sep

  hdr "All Local Users (/etc/passwd)"
  cut -d: -f1,3,4,6,7 /etc/passwd; echo
  sep

  hdr "Shells Assigned to Users"
  awk -F: '{printf "%-20s %s\n", $1, $7}' /etc/passwd; echo
  sep

  hdr "Groups (/etc/group)"
  cat /etc/group; echo
  sep

  hdr "UID 0 Accounts (other than root)"
  awk -F: '($3 == 0 && $1 != "root"){print}' /etc/passwd || echo "None found."
  echo
  sep

  hdr "Sudo Access (/etc/sudoers.d + sudoers)"
  if [[ "$RUNNING_AS_ROOT" == true ]]; then
    cat /etc/sudoers 2>/dev/null
    ls /etc/sudoers.d/ 2>/dev/null && cat /etc/sudoers.d/* 2>/dev/null
  else
    echo "(requires root)"
  fi
  echo
  sep

  hdr "Password Aging Policies"
  if [[ "$RUNNING_AS_ROOT" == true ]]; then
    while IFS=: read -r user _; do
      echo "--- $user ---"
      chage -l "$user" 2>/dev/null || echo "  (unavailable)"
    done < /etc/passwd
  else
    echo "(requires root)"
  fi
  echo
  sep

  hdr "Null Password Accounts"
  while IFS=: read -r user _; do
    passwd -S "$user" 2>/dev/null | grep " NP "
  done < /etc/passwd
  echo
  sep
}

audit_disk_memory() {
  hdr "Disk Usage (df -h)"
  df -h; echo
  sep

  hdr "Block Devices & Filesystems"
  lsblk -f; echo
  sep

  hdr "Mount Points"
  findmnt; echo
  sep

  hdr "Memory Usage"
  free -h; echo
  sep

  hdr "Top Processes by Memory/CPU (snapshot)"
  top -b -n1 | head -20; echo
  sep

  hdr "Largest Directories Under / (top 20, skipping pseudo-fs)"
  du -x --max-depth=3 / 2>/dev/null | sort -rh | head -20; echo
  sep
}

audit_networking() {
  hdr "Network Interfaces"
  ip a; echo
  sep

  hdr "Routing Table"
  ip route; echo
  sep

  hdr "ARP / Neighbor Table"
  ip neigh show; echo
  sep

  hdr "Open Ports & Listening Services (ss)"
  ss -tulnp; echo
  sep

  hdr "Firewall Rules (iptables)"
  if [[ "$RUNNING_AS_ROOT" == true ]]; then
    iptables -L -n -v 2>/dev/null
    echo ""
    echo "-- IPv6 --"
    ip6tables -L -n -v 2>/dev/null
  else
    echo "(requires root)"
  fi
  echo
  sep

  hdr "Network Kernel Parameters (sysctl)"
  sysctl net.ipv4.ip_forward 2>/dev/null
  sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null
  sysctl net.ipv4.conf.all.rp_filter 2>/dev/null
  sysctl net.ipv6.conf.all.forwarding 2>/dev/null
  echo
  sep

  hdr "TCP Wrappers (hosts.allow / hosts.deny)"
  echo "--- /etc/hosts.allow ---"
  cat /etc/hosts.allow 2>/dev/null || echo "(not present)"
  echo "--- /etc/hosts.deny ---"
  cat /etc/hosts.deny 2>/dev/null || echo "(not present)"
  echo
  sep
}

audit_services() {
  hdr "Running systemd Services"
  systemctl list-units --type=service --state=running --no-pager; echo
  sep

  hdr "Failed systemd Units"
  systemctl --failed --no-pager; echo
  sep

  hdr "Enabled at Boot"
  systemctl list-unit-files --type=service --state=enabled --no-pager; echo
  sep

  hdr "All Running Processes"
  ps auxf; echo
  sep

  hdr "Services Running as Root"
  ps -U root -u root u; echo
  sep
}

audit_ssh() {
  hdr "SSH Server Configuration (/etc/ssh/sshd_config)"
  if [[ -f /etc/ssh/sshd_config ]]; then
    grep -v "^#" /etc/ssh/sshd_config | grep -v "^$"
  else
    echo "(sshd_config not found)"
  fi
  echo
  sep

  hdr "Authorized Keys (all users)"
  for homedir in /home/* /root; do
    keyfile="$homedir/.ssh/authorized_keys"
    if [[ -f "$keyfile" ]]; then
      echo "==> $keyfile"
      cat "$keyfile"
    fi
  done
  echo
  sep

  hdr "SSH Host Keys"
  ls -la /etc/ssh/ssh_host_* 2>/dev/null; echo
  sep
}

audit_security() {
  hdr "Password Policy (/etc/pam.d/common-password)"
  cat /etc/pam.d/common-password 2>/dev/null || echo "(not found)"
  echo
  sep

  hdr "Login Definitions (/etc/login.defs)"
  grep -v "^#" /etc/login.defs 2>/dev/null | grep -v "^$"
  echo
  sep

  hdr "Failed Login Attempts"
  grep -i "failure\|failed\|invalid" /var/log/auth.log 2>/dev/null | tail -30 \
    || journalctl _SYSTEMD_UNIT=sshd.service | grep -i "fail\|invalid" | tail -30 2>/dev/null \
    || echo "(no auth.log or journald access)"
  echo
  sep

  hdr "World-Writable Files"
  find / -xdev -type f -perm -0002 2>/dev/null | head -50
  echo
  sep

  hdr "SUID / SGID Binaries"
  find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null
  echo
  sep

  hdr "Dangerous Dotfiles (.rhosts .netrc .forward)"
  find /home /root -maxdepth 2 \( -name .rhosts -o -name .netrc -o -name .forward \) 2>/dev/null \
    || echo "None found."
  echo
  sep

  hdr "Kernel Security Parameters (ASLR, redirects, rp_filter)"
  sysctl kernel.randomize_va_space 2>/dev/null
  sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null
  sysctl net.ipv4.conf.all.rp_filter 2>/dev/null
  echo
  sep

  hdr "SELinux / AppArmor Status"
  if command -v getenforce &>/dev/null; then
    echo "SELinux: $(getenforce)"
  elif command -v apparmor_status &>/dev/null; then
    apparmor_status 2>/dev/null | head -10
  else
    echo "(neither SELinux nor AppArmor tools found)"
  fi
  echo
  sep
}

audit_packages() {
  hdr "Package Manager Detection"
  if command -v rpm &>/dev/null; then
    echo "--- RPM-based (RHEL/CentOS/Rocky) ---"
    rpm -qa --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort
  elif command -v dpkg &>/dev/null; then
    echo "--- DEB-based (Debian/Ubuntu) ---"
    dpkg -l | grep "^ii"
  else
    echo "(unsupported package manager)"
  fi
  echo
  sep

  hdr "Pending Updates"
  if command -v apt-get &>/dev/null; then
    apt list --upgradeable 2>/dev/null
  elif command -v yum &>/dev/null; then
    yum check-update 2>/dev/null
  elif command -v dnf &>/dev/null; then
    dnf check-update 2>/dev/null
  fi
  echo
  sep
}

audit_cron() {
  hdr "Current User Crontab"
  crontab -l 2>/dev/null || echo "(no crontab for current user)"
  echo
  sep

  hdr "System-Wide Cron Directories"
  ls -la /etc/cron* 2>/dev/null; echo
  sep

  hdr "All User Crontabs (root only)"
  if [[ "$RUNNING_AS_ROOT" == true ]]; then
    for user in $(cut -d: -f1 /etc/passwd); do
      entry=$(crontab -u "$user" -l 2>/dev/null)
      if [[ -n "$entry" ]]; then
        echo "==> $user:"
        echo "$entry"
        echo ""
      fi
    done
  else
    echo "(requires root)"
  fi
  sep

  hdr "Systemd Timers"
  systemctl list-timers --no-pager; echo
  sep
}

audit_logs() {
  hdr "Last 50 Auth Log Entries"
  tail -50 /var/log/auth.log 2>/dev/null \
    || journalctl -u ssh --no-pager -n 50 2>/dev/null \
    || echo "(not accessible)"
  echo
  sep

  hdr "Last 30 syslog/messages Entries"
  tail -30 /var/log/syslog 2>/dev/null \
    || tail -30 /var/log/messages 2>/dev/null \
    || journalctl --no-pager -n 30 2>/dev/null
  echo
  sep

  hdr "Recent sudo Usage"
  grep -i "sudo" /var/log/auth.log 2>/dev/null | tail -30 \
    || journalctl | grep sudo | tail -30 2>/dev/null \
    || echo "(not accessible)"
  echo
  sep
}

# ─────────────────────────────────────────────
# MENU LOOP
# ─────────────────────────────────────────────
show_menu() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  SELECT AUDIT CATEGORY"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  [1]  System Information   (kernel, OS, uptime, reboots)"
  echo "  [2]  Users & Groups       (accounts, sudo, UIDs, password aging)"
  echo "  [3]  Disk & Memory        (df, lsblk, free, mounts)"
  echo "  [4]  Networking           (interfaces, ports, firewall, routing)"
  echo "  [5]  Services & Processes (systemd, running procs, root services)"
  echo "  [6]  SSH Configuration    (sshd_config, authorized_keys)"
  echo "  [7]  Security Checks      (world-writable, SUID, PAM, SELinux)"
  echo "  [8]  Installed Packages   (full list, pending updates)"
  echo "  [9]  Cron & Timers        (crontabs, systemd timers)"
  echo "  [10] Log Review           (auth, syslog, sudo)"
  echo "  [A]  Run ALL Categories"
  echo "  [Q]  Quit"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

dispatch() {
  local choice="$1"
  case "$choice" in
    1)  run_audit_section audit_system_info ;;
    2)  run_audit_section audit_users_groups ;;
    3)  run_audit_section audit_disk_memory ;;
    4)  run_audit_section audit_networking ;;
    5)  run_audit_section audit_services ;;
    6)  run_audit_section audit_ssh ;;
    7)  run_audit_section audit_security ;;
    8)  run_audit_section audit_packages ;;
    9)  run_audit_section audit_cron ;;
    10) run_audit_section audit_logs ;;
    [Aa])
      for fn in audit_system_info audit_users_groups audit_disk_memory \
                audit_networking audit_services audit_ssh audit_security \
                audit_packages audit_cron audit_logs; do
        run_audit_section "$fn"
      done
      ;;
    [Qq]) echo "Exiting. Goodbye."; exit 0 ;;
    *)  echo "Invalid option: $choice" ;;
  esac
}

# ─────────────────────────────────────────────
# MULTI-SELECT: user can pick multiple, e.g. "2 3 7"
# ─────────────────────────────────────────────
while true; do
  show_menu
  read -p "Enter option(s) — e.g. 2  or  2 3 7  or  A  or  Q: " selection
  echo ""

  START=$(date +%s)

  if [[ "$selection" =~ ^[Qq]$ ]]; then
    echo "Exiting."; exit 0
  fi

  for choice in $selection; do
    dispatch "$choice"
  done

  END=$(date +%s)
  DIFF=$(( END - START ))
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Completed in ${DIFF}s  |  $(date)"
  [[ "$OUTPUT_MODE" == "1" ]] && echo "  Output saved to: $OUTPUT_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  read -p "Run another audit? (y/n): " again
  [[ "$again" =~ ^[Yy]$ ]] || break
  echo ""
done

exit 0
