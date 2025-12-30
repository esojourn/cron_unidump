# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a bash-based MySQL database and file backup automation tool designed for Linux system administrators. It provides a unified interface for automated backup scheduling, management, and restoration of both MySQL databases and file systems through configuration-based profiles.

## Common Commands

### Installation & Setup
```bash
./cron_unidump.sh install          # Initialize system with default configurations
./cron_unidump.sh uninstall        # Remove installation and configurations
```

### Configuration Management
```bash
cron_unidump add {name}            # Create new backup configuration
cron_unidump edit {name}           # Edit existing configuration
cron_unidump show {name}           # Display configuration content
cron_unidump list                  # List all backup configurations
```

### Backup & Restore Operations
```bash
cron_unidump backup db {name}      # Backup database defined in {name}.conf
cron_unidump backup file {name}    # Backup files defined in {name}.conf
cron_unidump restore {name} {date} # Restore from backup of specific date
```

### Testing
```bash
./test.sh                          # Basic test utility
```

## Architecture & Key Concepts

### Configuration Hierarchy

The system uses a two-tier configuration model:

1. **Global Configuration** (`$HOME/.cron_unidump.conf`)
   - Default database credentials: `BACKUP_HOST`, `BACKUP_USER`, `BACKUP_PASS`
   - File ownership: `BACKUP_FILEOWN`
   - Email settings: `BACKUP_MAIL`, `BACKUP_EMAILS`, `BACKUP_SUBJECT`
   - Retention policy: `BACKUP_DELETE`, `BACKUP_INTERVAL_DAYS`

2. **Per-Backup Configuration** (`$HOME/.cron_unidump.d/{name}.conf`)
   - Can override global defaults
   - Database settings: `DBHOST`, `DBUSER`, `DBPASS`, `DBNAME`, `DBENGINE`, `DBOPTIONS`
   - File backup settings: `SOURCE`, `EXCLUDE`, `EXTRA_SOURCE`, `INTERVAL_DAYS`

Configuration templates are provided in `cron_unidump.conf`, `conf.example`, and the `conf/` directory.

### Backup Flow Architecture

The backup process follows this flow in `cron_unidump.sh`:

1. **Initialization** (line 105: `unidump_initEnv()`)
   - Sets up environment variables and required directories

2. **Configuration Loading** (line 321: `unidump_readConfig()`)
   - Reads and parses the configuration file for the selected backup profile

3. **Database Backup** (lines 115-247)
   - `unidump_backup_db_check()`: Validates database connectivity and table engine compatibility
   - `unidump_backup_db()`: Executes the actual backup using one of three methods

4. **File Backup** (line 248: `unidump_backup_file()`)
   - Uses GNU tar with snapshot files for incremental backup support
   - Manages monthly full backup cycles (default 30 days)

5. **Orchestration** (line 342: `unidump_backup()`)
   - Coordinates the entire backup process

### MySQL Backup Methods

The system supports three backup tools, selected via the `DBENGINE` configuration variable:

- **mysqlhotcopy**: Fast backup for MyISAM tables only
- **mydumper**: Recommended for InnoDB tables; provides parallelized backups
- **mysqldump**: Fallback method; universal but slower

The `unidump_backup_db_check()` function validates that table engines match the configured backup method before proceeding.

### Incremental File Backups

File backups use GNU tar's snapshot feature to track changes between backups:
- Full backup: Created monthly (default 30-day interval)
- Incremental backups: Created more frequently between full backups
- Snapshots stored in `{backup_dir}/.snapshot` directory

### Key Configuration Variables

**Database Backup:**
- `DBHOST`: MySQL server hostname
- `DBUSER`, `DBPASS`: Database credentials
- `DBNAME`: Database name(s) to backup
- `DBENGINE`: `myisam`, `innodb`, or `mysqldump`
- `DBOPTIONS`: Additional tool-specific arguments

**File Backup:**
- `SOURCE`: Primary source directory to backup
- `EXCLUDE`: Array of paths/patterns to exclude from backup (supports absolute paths, relative paths, and wildcards)
  - Array syntax: `EXCLUDE=("/path1" "path2" "*.log")`
  - Absolute paths: `EXCLUDE=("/var/www/cache" "/tmp/uploads")`
  - Relative paths: `EXCLUDE=("cache" "tmp")` (relative to SOURCE)
  - Wildcards: `EXCLUDE=("*.log" "*.tmp")`
  - Empty: `EXCLUDE=()` (no exclusions)
- `EXTRA_SOURCE`: Additional source directory (optional)
- `INTERVAL_DAYS`: Days between full backups (default: 30)

**Global:**
- `BACKUP_FILEOWN`: File/directory ownership (e.g., `nginx:nginx`)
- `BACKUP_DELETE`: Enable deletion of old backups (`y` or `n`)
- `BACKUP_INTERVAL_DAYS`: Retention period in days

## External Dependencies

The script requires these external tools to be installed:

- **MySQL tools**: `mysql`, `mysqldump`, `mysqlhotcopy`, or `mydumper`
- **Archive tools**: `tar` (with snapshot support for incremental backups)
- **System utilities**: `find`, `md5sum`, `date`, `hostname`, `sudo`
- **Optional**: `mutt` (for email notifications)

## Design Patterns

- **Colored output functions** (lines 70-80): Message formatting for user feedback
- **Command dispatch** (lines 466-557): Main command handler matching shell pattern
- **Configuration inheritance**: Global defaults can be overridden per-backup profile
- **Directory structure**: Logged at installation; standard Unix backup directory conventions

## Recent Updates

Recent commits have addressed:
- Dump command compatibility
- Tar exclude error handling
- Bash construct corrections
- Interval comparison logic (handling variable formatting)
- Support for database names with spaces
- Multi-database backup support in mysqldump
- Special character handling in passwords
