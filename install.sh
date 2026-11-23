#!/bin/bash
# Installer for sshid-sync
#
#   sudo ./install.sh                       interactive
#   sudo ./install.sh --users a,b -y        non-interactive
#   sudo ./install.sh --uninstall           remove
#
# Or straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/okaluk/sshid-sync/main/install.sh | sudo bash

set -euo pipefail

REPO="${SSHID_SYNC_REPO:-okaluk/sshid-sync}"
BRANCH="${SSHID_SYNC_BRANCH:-main}"
RAW_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"

BIN="/usr/local/sbin/sshid-sync"
CONF="/etc/sshid-sync.conf"
AK="/root/.ssh/authorized_keys"
CRON_FILE="/etc/cron.d/sshid-sync"
SVC="/etc/systemd/system/sshid-sync.service"
TIMER="/etc/systemd/system/sshid-sync.timer"
BASE_URL="${SSHID_BASE_URL:-https://sshid.io}"

USERS_ARG=""
INTERVAL=""
ASSUME_YES=0
MODE="install"

c_bold=$'\033[1m'; c_green=$'\033[32m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'; c_reset=$'\033[0m'
info() { echo "${c_bold}==>${c_reset} $*"; }
ok()   { echo "  ${c_green}✓${c_reset} $*"; }
warn() { echo "  ${c_yellow}!${c_reset} $*"; }
die()  { echo "${c_red}Error:${c_reset} $*" >&2; exit 1; }

usage() {
  cat <<EOF
sshid-sync installer

  --users a,b,c   sshid.io usernames (comma-separated)
  --interval N    Sync every N hours (default: 4)
  -y, --yes       Do not ask for confirmation
  --uninstall     Remove sshid-sync (authorized_keys is left unchanged)
  -h, --help      Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --users)     USERS_ARG="${2:-}"; shift 2 ;;
    --interval)  INTERVAL="${2:-}"; shift 2 ;;
    -y|--yes)    ASSUME_YES=1; shift ;;
    --uninstall) MODE="uninstall"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage; die "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Please run as root (sudo)."

# Read input from /dev/tty so that "curl ... | sudo bash" works too
HAVE_TTY=0
if [ "$ASSUME_YES" -eq 0 ] && { : < /dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

ask() { # ask "question" "default" -> answer on stdout
  local answer=""
  if [ "$HAVE_TTY" -eq 1 ]; then
    read -r -p "$1 " answer < /dev/tty || true
  fi
  printf '%s' "${answer:-$2}"
}

confirm() { # confirm "question" (default: yes)
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ "$HAVE_TTY" -eq 0 ] && return 0
  local a; a="$(ask "$1 [Y/n]" "y")"
  [[ "$a" =~ ^[Yy]$ ]]
}

has_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

# ---------------------------------------------------------------- Uninstall
if [ "$MODE" = "uninstall" ]; then
  info "Removing sshid-sync"
  if has_systemd && [ -f "$TIMER" ]; then
    systemctl disable --now sshid-sync.timer >/dev/null 2>&1 || true
    rm -f "$TIMER" "$SVC"; systemctl daemon-reload
    ok "systemd timer removed"
  fi
  [ -f "$CRON_FILE" ] && rm -f "$CRON_FILE" && ok "Cron entry removed"
  [ -f "$BIN" ] && rm -f "$BIN" && ok "$BIN removed"
  if [ -f "$CONF" ] && confirm "Delete the configuration $CONF as well?"; then
    rm -f "$CONF"; ok "$CONF removed"
  fi
  warn "$AK was not modified – keys that were already added remain in place."
  exit 0
fi

# ---------------------------------------------------------------- Installation
echo
echo "${c_bold}sshid-sync${c_reset} – automatically add SSH keys from sshid.io to $AK"
echo

info "Checking requirements"
for cmd in curl ssh-keygen awk grep logger; do
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is missing. Please install it and run again."
done
ok "curl, ssh-keygen, awk, grep, logger available"

SCHEDULER=""
if has_systemd; then
  SCHEDULER="systemd"
elif [ -d /etc/cron.d ]; then
  SCHEDULER="cron"
else
  die "Neither systemd nor cron (/etc/cron.d) found."
fi
ok "Scheduling via $SCHEDULER"

# Show the user how many keys sshid.io returns
check_user() {
  local user="$1" tmp count=0 line fp
  tmp="$(mktemp)"
  if ! curl -fsSL --max-time 15 "$BASE_URL/$user" -o "$tmp"; then
    rm -f "$tmp"; warn "$user: sshid.io unreachable or user unknown"; return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    fp="$(ssh-keygen -lf - <<<"$line" 2>/dev/null)" || continue
    count=$((count + 1))
    echo "      $fp"
  done < "$tmp"
  rm -f "$tmp"
  if [ "$count" -eq 0 ]; then warn "$user: no valid keys found"; return 1; fi
  ok "$user: $count key(s)"
}

# Carry over the existing configuration
USERS=()
if [ -f "$CONF" ]; then
  while IFS= read -r u || [ -n "$u" ]; do
    u="${u%%#*}"; u="$(printf '%s' "$u" | tr -d '[:space:]')"
    [ -n "$u" ] && USERS+=("$u")
  done < "$CONF"
fi

add_user() {
  local u="$1" existing
  [[ "$u" =~ ^[A-Za-z0-9._-]+$ ]] || { warn "Invalid name: $u"; return 1; }
  for existing in "${USERS[@]+"${USERS[@]}"}"; do
    [ "$existing" = "$u" ] && { warn "$u is already configured"; return 0; }
  done
  if check_user "$u" || confirm "  Add anyway?"; then
    USERS+=("$u")
  fi
}

info "sshid.io users"
if [ "${#USERS[@]}" -gt 0 ]; then
  echo "  Already configured: ${USERS[*]}"
  if ! confirm "  Keep these users?"; then USERS=(); fi
fi

if [ -n "$USERS_ARG" ]; then
  IFS=',' read -r -a arg_users <<<"$USERS_ARG"
  for u in "${arg_users[@]}"; do
    u="$(printf '%s' "$u" | tr -d '[:space:]')"
    [ -n "$u" ] && add_user "$u"
  done
fi

if [ "$HAVE_TTY" -eq 1 ]; then
  echo "  Enter usernames (e.g. 'okaluk' for https://sshid.io/okaluk)."
  echo "  An empty input ends the list."
  while :; do
    u="$(ask "  sshid.io user:" "")"
    u="$(printf '%s' "$u" | tr -d '[:space:]')"
    [ -z "$u" ] && break
    add_user "$u" || true
  done
fi

[ "${#USERS[@]}" -gt 0 ] || die "No users specified (interactively or with --users)."

# Interval
if [ -z "$INTERVAL" ]; then
  INTERVAL="$(ask "$(printf '%s==>%s Sync every how many hours? [4]' "$c_bold" "$c_reset")" "4")"
fi
[[ "$INTERVAL" =~ ^[0-9]+$ ]] && [ "$INTERVAL" -ge 1 ] && [ "$INTERVAL" -le 24 ] \
  || die "Interval must be a number from 1 to 24."

echo
info "Summary"
echo "  Users:      ${USERS[*]}"
echo "  Interval:   every $INTERVAL hour(s) and shortly after boot"
echo "  Target:     $AK"
echo
echo "  ${c_yellow}Note:${c_reset} Each of these sshid.io users gets root access to this server."
echo
confirm "Install?" || die "Aborted."

# Obtain the sync script
info "Installing"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/sshid-sync.sh" ]; then
  install -m 700 "$SRC_DIR/sshid-sync.sh" "$BIN"
else
  tmp="$(mktemp)"
  curl -fsSL "$RAW_URL/sshid-sync.sh" -o "$tmp" || die "Download of $RAW_URL/sshid-sync.sh failed."
  install -m 700 "$tmp" "$BIN"; rm -f "$tmp"
fi
ok "$BIN"

# Configuration
{
  echo "# sshid-sync – one sshid.io username per line. Comments start with #"
  printf '%s\n' "${USERS[@]}"
} > "$CONF"
chmod 600 "$CONF"
ok "$CONF"

# Backup
if [ -s "$AK" ]; then
  BACKUP="$AK.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$AK" "$BACKUP" && chmod 600 "$BACKUP"
  ok "Backup: $BACKUP"
fi

# Schedule
if [ "$SCHEDULER" = "systemd" ]; then
  cat > "$SVC" <<EOF
[Unit]
Description=Sync SSH keys from sshid.io
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$BIN
EOF
  cat > "$TIMER" <<EOF
[Unit]
Description=Sync SSH keys from sshid.io every $INTERVAL hour(s)

[Timer]
OnBootSec=2min
OnUnitActiveSec=${INTERVAL}h
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
EOF
  rm -f "$CRON_FILE"
  systemctl daemon-reload
  systemctl enable --now sshid-sync.timer >/dev/null
  ok "systemd timer active (systemctl list-timers sshid-sync.timer)"
else
  cat > "$CRON_FILE" <<EOF
# sshid-sync – sync SSH keys from sshid.io
0 */$INTERVAL * * * root $BIN
@reboot root sleep 120 && $BIN
EOF
  chmod 644 "$CRON_FILE"
  ok "Cron entry $CRON_FILE"
fi

# First run
info "First sync"
"$BIN" --verbose

echo
echo "${c_green}Done.${c_reset}"
echo "  Change users: edit $CONF or run install.sh again"
echo "  Sync now:     $BIN"
echo "  Log:          journalctl -t sshid-sync"
echo "  Uninstall:    install.sh --uninstall"
