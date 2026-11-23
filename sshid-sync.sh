#!/bin/bash
# sshid-sync – fetches SSH public keys from sshid.io and appends them to
# authorized_keys without adding keys that are already present a second time.
#
# Configuration: /etc/sshid-sync.conf (one sshid.io username per line)
# Log:           journalctl -t sshid-sync

set -uo pipefail

CONF="${SSHID_SYNC_CONF:-/etc/sshid-sync.conf}"
AK="${SSHID_SYNC_AUTHORIZED_KEYS:-/root/.ssh/authorized_keys}"
BASE_URL="${SSHID_BASE_URL:-https://sshid.io}"

VERBOSE=0
[ -t 1 ] && VERBOSE=1
case "${1:-}" in
  -v|--verbose) VERBOSE=1 ;;
  -q|--quiet)   VERBOSE=0 ;;
  -h|--help)    echo "Usage: sshid-sync [-v|--verbose] [-q|--quiet]"; exit 0 ;;
esac

log() {
  logger -t sshid-sync -- "$*" 2>/dev/null || true
  [ "$VERBOSE" -eq 1 ] && echo "sshid-sync: $*"
  return 0
}

if [ ! -r "$CONF" ]; then
  log "Configuration $CONF is missing or not readable"
  exit 1
fi

AK_DIR="$(dirname "$AK")"
mkdir -p "$AK_DIR" && chmod 700 "$AK_DIR"
touch "$AK" && chmod 600 "$AK"
# Make sure the file ends with a newline
if [ -s "$AK" ] && [ -n "$(tail -c1 "$AK")" ]; then
  echo >> "$AK"
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

total=0
while IFS= read -r user || [ -n "$user" ]; do
  user="${user%%#*}"
  user="$(printf '%s' "$user" | tr -d '[:space:]')"
  [ -z "$user" ] && continue

  if [[ ! "$user" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log "Skipped invalid username: $user"
    continue
  fi

  if ! curl -fsSL --max-time 15 "$BASE_URL/$user" -o "$TMP"; then
    log "[$user] Fetch failed – skipped"
    continue
  fi

  found=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    # Only accept valid public keys (filters out e.g. HTML error pages)
    fp="$(ssh-keygen -lf - <<<"$line" 2>/dev/null)" || continue
    found=$((found + 1))
    blob="$(awk '{print $2}' <<<"$line")"
    if ! grep -qF -- "$blob" "$AK"; then
      printf '%s\n' "$line" >> "$AK"
      total=$((total + 1))
      log "[$user] Key added: $fp"
    fi
  done < "$TMP"

  [ "$found" -eq 0 ] && log "[$user] No valid keys found"
done < "$CONF"

if [ "$total" -gt 0 ]; then
  log "$total new key(s) added"
else
  [ "$VERBOSE" -eq 1 ] && echo "sshid-sync: No new keys."
fi
exit 0
