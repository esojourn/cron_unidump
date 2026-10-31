# AGENTS.md

Guide for coding agents working on this repository. User-facing behaviour is documented in [README.md](README.md); read it first.

## Layout

| Path | Role |
|---|---|
| `cron_unidump.sh` | the whole CLI: config loading, DB backup, file backup, command dispatch (`case $1`) |
| `scripts/rsyncPush.sh` | push to the NAS; called by `cron_unidump push` and `run` |
| `scripts/rsyncMirror.sh` | plain-file mirror of `MIRROR_SOURCES` to the NAS; called by `cron_unidump mirror`. Never deletes on the server; deletions on the NAS go to `<MIRROR_DEST>-deleted/<date>/` via `--backup-dir` |
| `cron_unidump.conf` | template for `~/.cron_unidump.conf` (copied by `install`) |
| `example.eg` | template for `~/.cron_unidump.d/<name>.conf` (copied by `install`, used by `add`) |

Key functions in `cron_unidump.sh`: `unidump_initEnv` (sources the global config), `unidump_readConfig` (evals a job config, sets `fileBaseDir`/`dbBaseDir`/`logBaseDir`), `unidump_backup_db_check`, `unidump_backup_db`, `unidump_backup_file`, `unidump_push`. `run` re-executes the script once per job (`bash "$selfPath" backup ...`) so job variables never leak between jobs.

## Invariants (do not break)

1. **Archives appear atomically.** Write to `<archive>.part`, rename only on success, delete the `.part` on failure. The push excludes `*.part`.
2. **Push never races a backup.** `rsyncPush.sh` waits while `bash .../cron_unidump(.sh) backup ` is running. If you change how backups are launched, keep that `pgrep` pattern matching, and keep it from matching the cron `sh -c` parent.
3. **Snapshot rollback.** Before tar runs, the current snapshot is copied to `snapshot-<job>-incremental-YYMMDD.log`; on tar failure (rc > 1) it is restored. tar rc 1 is success.
4. **Incremental chain.** `inc` continues from the previous run's snapshot; `diff` starts from `-intervalBase`; `full` removes the snapshot. A missing snapshot forces `full`.
5. **Exit codes.** `backup` exits non-zero if tar or the DB archive failed (`unidumpFailed`). `run` exits non-zero if any job or the push failed.
6. **Local files are deleted only by rsync `--remove-source-files`** after a confirmed transfer. Never add other deletes of archives.
7. **No site-specific data in the repo.** No real host names, IPs, ports, user names, e-mail addresses, paths of real sites or passwords, including in examples and tests. `PUSH_HOST`, `PUSH_USER`, `PUSH_PATH`, `PUSH_SERVER` deliberately have no defaults. Use `example.com`, `site`, `001-web1`, `CHANGE_ME`.
8. Config files are sourced/evaluated as bash; they may contain passwords. Anything that prints a config must mask `*PASS*` values (see `show`).

## Testing a change

There is no test suite. Test on a disposable Linux host or container with GNU tar, never against real backup directories:

```bash
T=$(mktemp -d); H=$T/home; mkdir -p $H/.cron_unidump.d $T/src $T/out $T/log
echo a > $T/src/a; echo b > $T/src/b
cat > $H/.cron_unidump.conf <<EOF
BACKUP_FILEOWN=root:root
BACKUP_INTERVAL_DAYS=14
BACKUP_FILE_MODE=incremental
EOF
printf "SOURCE=$T/src\nfileDir=$T/out\nlogDir=$T/log\n" > $H/.cron_unidump.d/t.conf
HOME=$H bash cron_unidump.sh backup file t        # -full
echo c > $T/src/c; sleep 1
HOME=$H bash cron_unidump.sh backup file t        # -inc with only c
mkdir $T/r && cd $T/r && for f in $(ls $T/out/t/ | sort); do tar -xjf $T/out/t/$f -g /dev/null; done
diff -r $T/src $T/r$T/src && echo RESTORE_OK
```

Cases worth covering after a change to backup or push logic:

- full → inc → inc restores identical to the source, including a deleted file and a mode change
- `FILE_MODE=differential` produces cumulative `-diff` archives
- base snapshot older than `INTERVAL_DAYS` (`touch -d '15 days ago' ...-intervalBase`) gives `-full`
- forced failure (e.g. `fileDir=/proc/x`, root ignores chmod) leaves the snapshot unchanged and exits non-zero
- push started while a backup runs waits, then sends only finished archives
- push with a `PUSH_*` variable unset exits 2; a second concurrent push exits 1

Always `bash -n` both scripts. Files must have LF line endings (a Windows checkout with `core.autocrlf=true` produces CRLF, which bash rejects).

## Style

- Bash, two-space indent, functions named `unidump_*`.
- Messages through `commentLine` / `alertMsg` / `successMsg`.
- Keep compatibility with existing job configs (string or array `EXCLUDE`/`EXTRA_SOURCE`, `--exclude=` entries).
- Update README.md when behaviour, commands or variables change.
