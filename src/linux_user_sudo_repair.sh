#!/usr/bin/env bash
set -u

ACTION=""
TARGET_USER=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: linux_user_sudo_repair.sh ACTION --user USER [options]

Actions:
  --add-sudo         Add USER to the distribution's sudo or wheel group.
  --remove-sudo      Remove USER from the sudo or wheel group.
  --lock-user        Lock USER's password.
  --unlock-user      Unlock USER's password.
  --fix-home-owner   Set USER as owner of the configured home directory.

Options:
  --dry-run          Show commands without changing the system.
  --yes              Skip confirmation prompts.
  --output DIR       Save logs and before/after verification in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --add-sudo) ACTION="add-sudo"; shift ;;
    --remove-sudo) ACTION="remove-sudo"; shift ;;
    --lock-user) ACTION="lock-user"; shift ;;
    --unlock-user) ACTION="unlock-user"; shift ;;
    --fix-home-owner) ACTION="fix-home-owner"; shift ;;
    --user) TARGET_USER="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$ACTION" ] || { echo "Choose one action." >&2; exit 2; }
[ -n "$TARGET_USER" ] || { echo "--user is required." >&2; exit 2; }
getent passwd "$TARGET_USER" >/dev/null 2>&1 || { echo "User not found: $TARGET_USER" >&2; exit 2; }
USER_UID=$(id -u "$TARGET_USER")
[ "$USER_UID" -ge 1000 ] || { echo "Refusing to modify a system account with UID $USER_UID." >&2; exit 2; }
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
case "$USER_HOME" in /home/*|/Users/*) : ;; *) [ "$ACTION" != "fix-home-owner" ] || { echo "Refusing non-standard home path: $USER_HOME" >&2; exit 2; } ;; esac

PRIV_GROUP=""
getent group sudo >/dev/null 2>&1 && PRIV_GROUP=sudo
[ -n "$PRIV_GROUP" ] || { getent group wheel >/dev/null 2>&1 && PRIV_GROUP=wheel; }
if [ "$ACTION" = "add-sudo" ] || [ "$ACTION" = "remove-sudo" ]; then [ -n "$PRIV_GROUP" ] || { echo "No sudo or wheel group found." >&2; exit 3; }; fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./user-sudo-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
BEFORE="$OUTPUT_DIR/before.txt"
AFTER="$OUTPUT_DIR/after.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
collect_state() {
  local destination="$1"
  {
    echo "Collected: $(date -Is)"
    id "$TARGET_USER" 2>&1 || true
    passwd -S "$TARGET_USER" 2>&1 || true
    chage -l "$TARGET_USER" 2>&1 || true
    echo
    getent group sudo 2>/dev/null || true
    getent group wheel 2>/dev/null || true
    echo
    stat -c '%a %U:%G %n' "$USER_HOME" 2>/dev/null || true
    echo
    visudo -c 2>&1 || true
  } > "$destination"
}

collect_state "$BEFORE"
confirm "Apply '$ACTION' to $TARGET_USER?" || { log "Repair cancelled."; exit 10; }

case "$ACTION" in
  add-sudo)
    run_root "Adding $TARGET_USER to $PRIV_GROUP" usermod -aG "$PRIV_GROUP" "$TARGET_USER" || true
    ;;
  remove-sudo)
    MEMBER_COUNT=$(getent group "$PRIV_GROUP" | awk -F: '{n=split($4,a,","); if($4=="") n=0; print n}')
    if id -nG root 2>/dev/null | tr ' ' '\n' | grep -Fxq "$PRIV_GROUP"; then MEMBER_COUNT=$((MEMBER_COUNT + 1)); fi
    [ "$MEMBER_COUNT" -gt 1 ] || { log "Refusing to remove the final account in $PRIV_GROUP."; exit 20; }
    if command -v gpasswd >/dev/null 2>&1; then run_root "Removing $TARGET_USER from $PRIV_GROUP" gpasswd -d "$TARGET_USER" "$PRIV_GROUP" || true; else run_root "Removing $TARGET_USER from $PRIV_GROUP" deluser "$TARGET_USER" "$PRIV_GROUP" || true; fi
    ;;
  lock-user)
    run_root "Locking password for $TARGET_USER" passwd -l "$TARGET_USER" || true
    ;;
  unlock-user)
    run_root "Unlocking password for $TARGET_USER" passwd -u "$TARGET_USER" || true
    ;;
  fix-home-owner)
    [ -d "$USER_HOME" ] || { log "Home directory does not exist: $USER_HOME"; exit 20; }
    PRIMARY_GROUP=$(id -gn "$TARGET_USER")
    run_root "Correcting ownership of $USER_HOME" chown -R "$TARGET_USER:$PRIMARY_GROUP" "$USER_HOME" || true
    ;;
esac

command -v visudo >/dev/null 2>&1 && run_root "Validating sudo configuration" visudo -c || true
collect_state "$AFTER"
if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
