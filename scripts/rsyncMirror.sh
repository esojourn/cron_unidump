#!/bin/bash
# rsyncMirror.sh - keep a mirror of large, rarely changing directories on the NAS.
#
# For data that is too big to tar every time (media libraries, uploads).
# Files are copied as they are, no archive is made locally, so it needs no
# local disk space. After the first run only new and changed files are sent.
#
# Usage:   cron_unidump mirror        (or run this script directly)
#
# Config:  ~/.cron_unidump.conf
#   MIRROR_SOURCES=("/var/www/site/files/audio" "/var/www/site/files/video")
#   NAS connection: PUSH_HOST, PUSH_USER, PUSH_PORT, PUSH_PATH, PUSH_SERVER,
#                   PUSH_SSH_KEY, PUSH_KNOWN_HOSTS (same as the archive push)
#
# Result on the NAS:
#   <PUSH_PATH>/<PUSH_SERVER>/<MIRROR_DEST>/<full source path>/...      current copy
#   <PUSH_PATH>/<PUSH_SERVER>/<MIRROR_DEST>-deleted/<date>/<path>/...   files that were
#        deleted or replaced on the server since the previous run (never removed by this script)
#
# Safety:
#   - single instance (flock); a long first run is not started twice
#   - strict host key checking against PUSH_KNOWN_HOSTS
#   - nothing on the server is modified or deleted
#   - nothing is lost on the NAS: --delete moves files into <MIRROR_DEST>-deleted/<date>/
#   - interrupted transfers resume (partial files kept in .rsync-partial, not in the mirror)
set -u
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# ---------- defaults ----------
MIRROR_SOURCES=()
MIRROR_DEST='mirror'
MIRROR_LOG='/var/log/backup/rsyncMirror.log'
MIRROR_LOCK='/var/lock/rsyncMirror.lock'
MIRROR_BWLIMIT=''                       # KiB/s, empty = unlimited
PUSH_SERVER=''
PUSH_HOST=''
PUSH_USER=''
PUSH_PORT='22'
PUSH_PATH=''
PUSH_SSH_KEY="$HOME/.ssh/id_rsa"
PUSH_KNOWN_HOSTS="$HOME/.ssh/known_hosts_nas"

# ---------- config ----------
GLOBAL_CONF="${CRON_UNIDUMP_CONF:-$HOME/.cron_unidump.conf}"
if [ -r "$GLOBAL_CONF" ]; then
  # The global config is plain bash (arrays allowed); unset variables in it must not abort us
  set +u
  # shellcheck disable=SC1090
  . "$GLOBAL_CONF" >/dev/null 2>&1
  set -u
fi

mkdir -p "$(dirname "$MIRROR_LOG")" "$(dirname "$MIRROR_LOCK")"
if [ -t 1 ]; then
  exec > >(tee -a "$MIRROR_LOG") 2>&1
else
  exec >>"$MIRROR_LOG" 2>&1
fi
log() { printf '[%s] %s\n' "$(date '+%F %T %z')" "$*"; }

missing=''
for v in PUSH_SERVER PUSH_HOST PUSH_USER PUSH_PATH MIRROR_DEST; do
  [ -z "${!v}" ] && missing="$missing $v"
done
[ ${#MIRROR_SOURCES[@]} -eq 0 ] && missing="$missing MIRROR_SOURCES"
if [ -n "$missing" ]; then
  log "not configured:$missing (set them in $GLOBAL_CONF)"
  exit 2
fi

exec 9>"$MIRROR_LOCK"
if ! flock -n 9; then
  log "another mirror run is still in progress, exit"
  exit 1
fi

if [ ! -r "$PUSH_SSH_KEY" ] || [ ! -r "$PUSH_KNOWN_HOSTS" ]; then
  log "SSH key ($PUSH_SSH_KEY) or known_hosts ($PUSH_KNOWN_HOSTS) is missing"
  exit 1
fi

ssh_cmd="ssh -i $PUSH_SSH_KEY -p $PUSH_PORT -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$PUSH_KNOWN_HOSTS -o ConnectTimeout=30 -o ServerAliveInterval=30"
base="$PUSH_PATH/$PUSH_SERVER"
deletedDir="$base/${MIRROR_DEST}-deleted/$(date +%F)"

if ! $ssh_cmd "$PUSH_USER@$PUSH_HOST" "mkdir -p '$base/$MIRROR_DEST' && test -d '$base/$MIRROR_DEST'"; then
  log "NAS preflight failed (connect or $base/$MIRROR_DEST missing)"
  exit 1
fi

# --chmod: the NAS user must always be able to write into the mirror, even when a
# source directory is read-only (e.g. Drupal sites/default is 550)
rsync_opts=(-rltp --relative --delete --delete-delay --backup --backup-dir="$deletedDir"
            --chmod=Du+rwx,Fu+rw
            --partial-dir=.rsync-partial --stats --human-readable --rsync-path=/usr/bin/rsync)
[ -n "$MIRROR_BWLIMIT" ] && rsync_opts+=(--bwlimit="$MIRROR_BWLIMIT")

log "mirror started: ${MIRROR_SOURCES[*]} -> $PUSH_USER@$PUSH_HOST:$base/$MIRROR_DEST"
failed=0
for src in "${MIRROR_SOURCES[@]}"; do
  src=${src%/}
  if [ ! -d "$src" ]; then
    log "skip, not a directory: $src"
    failed=1
    continue
  fi
  log "sync $src ($(du -sh "$src" 2>/dev/null | cut -f1))"
  rsync "${rsync_opts[@]}" -e "$ssh_cmd" "$src" "$PUSH_USER@$PUSH_HOST:$base/$MIRROR_DEST/"
  rc=$?
  # 24 = some files vanished while being read: the rest was copied, the next run catches up
  if [ $rc -ne 0 ] && [ $rc -ne 24 ]; then
    log "rsync failed for $src rc=$rc (the next run resumes)"
    failed=1
  fi
done

if [ $failed -ne 0 ]; then
  log "mirror finished with errors"
  exit 1
fi
log "mirror completed"
exit 0
