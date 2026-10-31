#!/bin/bash
# rsyncPush.sh - push finished cron_unidump archives to the NAS, then remove them locally.
#
# Usage:   cron_unidump push        (or run this script directly)
#
# Config:  PUSH_* variables in ~/.cron_unidump.conf (see cron_unidump.conf).
#
# Safety:
#   - single instance (flock)
#   - waits while a cron_unidump backup is still running
#   - never sends *.part files (cron_unidump writes archives as *.part, then renames)
#   - strict host key checking against PUSH_KNOWN_HOSTS
#   - local files are removed only after rsync confirms each transfer
set -u
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# ---------- defaults ----------
PUSH_SRC='/var/www/html/backup'
PUSH_SERVER=''                          # NAS sub directory, e.g. 001-SK2024 (required)
PUSH_HOST='dingxuan.synology.me'
PUSH_USER='unicom'
PUSH_PORT='11756'
PUSH_PATH='/var/services/homes/unicom/rsync'
PUSH_SSH_KEY="$HOME/.ssh/id_rsa"
PUSH_KNOWN_HOSTS="$HOME/.ssh/known_hosts_nas"
PUSH_LOG='/var/log/backup/rsyncPush.log'
PUSH_LOCK='/var/lock/rsyncPush.lock'
PUSH_WAIT_MAX=21600                     # seconds to wait for running backups (6h)
PUSH_BWLIMIT=''                         # rsync --bwlimit in KiB/s, empty = unlimited

# ---------- config ----------
GLOBAL_CONF="${CRON_UNIDUMP_CONF:-$HOME/.cron_unidump.conf}"
if [ -r "$GLOBAL_CONF" ]; then
  # Only take PUSH_* assignments; the rest of the file is not needed here
  eval "$(grep -E '^[[:space:]]*PUSH_[A-Z_]+=' "$GLOBAL_CONF")"
fi

mkdir -p "$(dirname "$PUSH_LOG")" "$(dirname "$PUSH_LOCK")"
# Log to file; also to the terminal when run interactively
if [ -t 1 ]; then
  exec > >(tee -a "$PUSH_LOG") 2>&1
else
  exec >>"$PUSH_LOG" 2>&1
fi
log() { printf '[%s] %s\n' "$(date '+%F %T %z')" "$*"; }

if [ -z "$PUSH_SERVER" ]; then
  log "PUSH_SERVER is not set in $GLOBAL_CONF"
  exit 2
fi

exec 9>"$PUSH_LOCK"
if ! flock -n 9; then
  log "another push is already running, exit"
  exit 1
fi

log "push started: $PUSH_SRC -> $PUSH_USER@$PUSH_HOST:$PUSH_PATH/$PUSH_SERVER"

# ---------- wait for running backups ----------
# Match only the bash process running cron_unidump, not a cron "sh -c '... && cron_unidump push'" parent
waited=0
while pgrep -f '^[^ ]*bash [^ ]*cron_unidump(\.sh)? backup ' >/dev/null; do
  if [ "$waited" -ge "$PUSH_WAIT_MAX" ]; then
    log "backup still running after ${PUSH_WAIT_MAX}s, give up (local files kept)"
    exit 1
  fi
  [ "$waited" -eq 0 ] && log "backup in progress, waiting..."
  sleep 60
  waited=$((waited + 60))
done
[ "$waited" -gt 0 ] && log "backup finished after waiting ${waited}s"

# ---------- preflight ----------
if [ ! -d "$PUSH_SRC" ]; then
  log "source directory does not exist: $PUSH_SRC"
  exit 1
fi
if [ ! -r "$PUSH_SSH_KEY" ] || [ ! -r "$PUSH_KNOWN_HOSTS" ]; then
  log "SSH key ($PUSH_SSH_KEY) or known_hosts ($PUSH_KNOWN_HOSTS) is missing"
  exit 1
fi

ssh_cmd="ssh -i $PUSH_SSH_KEY -p $PUSH_PORT -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$PUSH_KNOWN_HOSTS -o ConnectTimeout=30 -o ServerAliveInterval=30"

if ! $ssh_cmd "$PUSH_USER@$PUSH_HOST" "mkdir -p '$PUSH_PATH/$PUSH_SERVER' && test -d '$PUSH_PATH/$PUSH_SERVER'"; then
  log "NAS preflight failed (connect or $PUSH_PATH/$PUSH_SERVER missing), local files kept"
  exit 1
fi

# ---------- push ----------
rsync_opts=(-rltp --partial --stats --human-readable --exclude='*.part' --remove-source-files --rsync-path=/usr/bin/rsync)
[ -n "$PUSH_BWLIMIT" ] && rsync_opts+=(--bwlimit="$PUSH_BWLIMIT")

# Keep the historical NAS layout: <PUSH_PATH>/<PUSH_SERVER>/<basename of PUSH_SRC>/<job>/<file>
rsync "${rsync_opts[@]}" -e "$ssh_cmd" "${PUSH_SRC%/}" "$PUSH_USER@$PUSH_HOST:$PUSH_PATH/$PUSH_SERVER/"
rc=$?
if [ $rc -ne 0 ]; then
  log "rsync failed rc=$rc, files not confirmed are kept locally"
  exit $rc
fi

log "push completed"
exit 0
