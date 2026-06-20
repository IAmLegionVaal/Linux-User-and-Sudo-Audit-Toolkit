#!/usr/bin/env bash
set -u

OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--output DIRECTORY]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./linux-user-audit-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/user-audit.txt"
CSV="$OUTPUT_DIR/local-accounts.csv"
JSON="$OUTPUT_DIR/user-summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"

section() { local title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
[[ $EUID -ne 0 ]] && echo "WARNING: Root privileges improve audit completeness." | tee -a "$REPORT"

section "Collection metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; id'
section "Privileged groups" bash -c 'getent group sudo 2>/dev/null || true; getent group wheel 2>/dev/null || true; getent group adm 2>/dev/null || true'
section "Sudoers validation" bash -c 'visudo -c 2>/dev/null || true; ls -la /etc/sudoers /etc/sudoers.d 2>/dev/null || true'
section "Recent successful logins" last -a -n 100
section "Recent failed logins" bash -c 'lastb -a -n 100 2>/dev/null || true'
section "Last login by account" bash -c 'lastlog 2>/dev/null || true'
section "Accounts with authorised_keys" bash -c 'while IFS=: read -r u _ uid _ _ home shell; do f="$home/.ssh/authorized_keys"; if [[ -r "$f" ]]; then printf "%s uid=%s shell=%s key_lines=%s file=%s\n" "$u" "$uid" "$shell" "$(grep -cv "^[[:space:]]*$" "$f" 2>/dev/null || echo 0)" "$f"; fi; done < /etc/passwd'
section "Orphaned ownership in selected paths" bash -c 'find /home /srv /opt -xdev \( -nouser -o -nogroup \) -print 2>/dev/null | head -n 300'

{
  echo 'username,uid,gid,home,shell,account_class,password_state,last_password_change,min_days,max_days,warn_days'
  while IFS=: read -r user _ uid gid _ home shell; do
    class="service"; [[ "$uid" -eq 0 ]] && class="root"; [[ "$uid" -ge 1000 ]] && class="interactive"
    shadow="$(passwd -S "$user" 2>/dev/null || true)"
    state="$(awk '{print $2}' <<< "$shadow")"
    changed="$(awk '{print $3}' <<< "$shadow")"
    min="$(awk '{print $4}' <<< "$shadow")"
    max="$(awk '{print $5}' <<< "$shadow")"
    warn="$(awk '{print $6}' <<< "$shadow")"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$user" "$uid" "$gid" "$home" "$shell" "$class" "${state:-unknown}" "${changed:-unknown}" "${min:-unknown}" "${max:-unknown}" "${warn:-unknown}"
  done < /etc/passwd
} > "$CSV"

TOTAL="$(wc -l < /etc/passwd | tr -d ' ')"
INTERACTIVE="$(awk -F: '$3 >= 1000 && $7 !~ /(nologin|false)$/ {c++} END {print c+0}' /etc/passwd)"
SUDO_MEMBERS="$( { getent group sudo 2>/dev/null; getent group wheel 2>/dev/null; } | awk -F: '{if ($4 != "") print $4}' | tr ',' '\n' | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
LOCKED="$(awk -F, 'NR>1 && $7 ~ /^(L|LK)$/ {c++} END {print c+0}' "$CSV")"

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "total_local_accounts": ${TOTAL:-0},
  "interactive_accounts": ${INTERACTIVE:-0},
  "privileged_group_members": ${SUDO_MEMBERS:-0},
  "locked_accounts": ${LOCKED:-0}
}
EOF

printf '\nUser and sudo audit completed. Output: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
