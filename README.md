# cron_unidump

Linux Web 服务器的定时备份工具（Bash）。每天备份网站文件和 MySQL/MariaDB 数据库，然后通过 SSH 把备份包推送到 NAS，推送成功后删除本地副本。

- 文件备份基于 GNU tar 快照：每 N 天一次全量，期间只打包变化的文件。
- 数据库备份用 `mysqldump`（也支持 `mydumper` / `mysqlhotcopy`）。
- 每台服务器只需一条 cron：依次备份所有任务，全部完成后推送一次。
- 推送不会发送正在写入的备份包。

```
cron 03:50 ─► cron_unidump run db:site file:site
                 ├─ backup db site   ─► /var/www/html/backup/site/DB-<库名>-<时间>.tar.gz
                 ├─ backup file site ─► /var/www/html/backup/site/FILE-site-<时间>-full|inc.tar.bz2
                 └─ push             ─► rsync ─► NAS:<PUSH_PATH>/<PUSH_SERVER>/backup/site/
                                                 （确认传输成功后才删除本地文件）
```

## 目录

1. [环境要求](#环境要求)
2. [安装](#安装)
3. [配置](#配置)
4. [命令](#命令)
5. [定时任务](#定时任务)
6. [文件备份原理](#文件备份原理)
7. [推送到 NAS](#推送到-nas)
8. [恢复](#恢复)
9. [文件与日志位置](#文件与日志位置)
10. [配置项参考](#配置项参考)
11. [故障排查](#故障排查)
12. [已知限制](#已知限制)

## 环境要求

| 用途 | 需要的工具 |
|---|---|
| 基本功能 | bash 4+、GNU tar、bzip2、gzip、coreutils、`sudo` |
| 数据库备份 | `mysql` 客户端和 `mysqldump`（或 `mydumper` / `mysqlhotcopy`） |
| 推送 | 两端都有 `rsync` 和 `ssh`；本机有 `flock`、`pgrep` |

- Debian/Ubuntu：`apt install git bzip2 rsync mariadb-client`
- RHEL/Rocky/Alma：`dnf install git bzip2 rsync mysql`

用 root 运行（需要读取网站文件，写入 `/var/www/html/backup` 和 `/var/log/backup`）。

## 安装

```bash
git clone https://github.com/esojourn/cron_unidump.git /root/cron_unidump
/root/cron_unidump/cron_unidump.sh install
```

`install` 会创建：

| 路径 | 说明 |
|---|---|
| `~/.cron_unidump.conf` | 全局配置（权限 600），从仓库里的 `cron_unidump.conf` 复制 |
| `~/.cron_unidump.d/` | 任务配置目录（权限 700），含模板 `example.eg` |
| `/usr/bin/cron_unidump` | 指向脚本的软链接 |

以后升级：`cd /root/cron_unidump && git pull`。配置在 `~` 下，升级不会改动。

## 配置

### 1. 全局配置 `~/.cron_unidump.conf`

至少设置输出目录、数据库账号；如果要推送，再设置 NAS：

```bash
fileDir=/var/www/html/backup
dbDir=/var/www/html/backup
BACKUP_INTERVAL_DAYS=14          # 每 14 天一次全量文件备份
BACKUP_FILE_MODE=incremental

BACKUP_USER="backup"             # 任务没有设置 DBUSER 时使用的 MySQL 账号
BACKUP_PASS="..."

PUSH_HOST='nas.example.com'
PUSH_USER='backup'
PUSH_PORT='22'
PUSH_PATH='/volume1/backup'
PUSH_SERVER='001-web1'           # 每台服务器在 NAS 上一个目录
```

### 2. 每个站点一个任务 `~/.cron_unidump.d/<name>.conf`

```bash
cron_unidump add site            # 从 example.eg 复制出 site.conf 并用 $EDITOR 打开
```

```bash
SOURCE='/var/www/site'
EXCLUDE=("cache" "tmp" "*.log")  # 相对 SOURCE 的路径；也可以写绝对路径、通配符

DBHOST='localhost'
DBNAME='site_db'
DBENGINE='mysqldump'
DBOPTIONS='--single-transaction --routines --triggers'
```

`<name>` 只用字母、数字、`_`、`-`。它会作为该任务备份包和日志的子目录名。

### 3. 手动跑一次验证

```bash
cron_unidump backup db site && cron_unidump backup file site
ls -la /var/www/html/backup/site/
cron_unidump push && tail /var/log/backup/rsyncPush.log
```

## 命令

| 命令 | 作用 |
|---|---|
| `cron_unidump install` | 复制配置模板，创建 `/usr/bin/cron_unidump` |
| `cron_unidump add <name>` | 从模板新建任务配置并打开编辑 |
| `cron_unidump edit <name>` | 用 `$EDITOR` 编辑任务配置 |
| `cron_unidump show <name>` | 显示任务配置（密码会被隐藏） |
| `cron_unidump list` | 列出所有任务 |
| `cron_unidump backup file\|db\|all <name>` | 立即执行一个任务 |
| `cron_unidump push` | 把已完成的备份包推送到 NAS |
| `cron_unidump run <类型:名称> [...]` | 按顺序备份每个任务，最后推送一次 |
| `cron_unidump help` | 简要用法 |

退出码：成功为 `0`；任一备份或推送失败为非 0。`run` 中某个任务失败后会继续执行后面的任务，并推送已经完成的备份包。

## 定时任务

每台服务器写一条 `run`。这一条里的所有备份都结束后才开始推送。

```cron
# 分 时 日 月 周  命令
50 3 * * *  /usr/bin/cron_unidump run db:site file:site file:uploads >> /var/log/backup/cron_unidump.log 2>&1
```

- `run` 的参数格式为 `类型:名称`，类型是 `file`、`db`、`all` 之一。
- 不要把 `backup` 和 `push` 写成两条、靠固定时间差衔接。全量备份变慢时，推送会在备份还没写完时开始。
- cron 按服务器本地时区执行（`timedatectl` 查看）。

## 文件备份原理

使用 GNU tar 的快照增量模式（`tar -g <快照文件>`）。

| 模式（`FILE_MODE` / `BACKUP_FILE_MODE`） | 每次打包的内容 | 恢复时需要 |
|---|---|---|
| `incremental`（默认，增量） | 自上一次备份以来的变化 | 最近的 `-full` 加之后所有 `-inc` |
| `differential`（差异） | 自上一次全量以来的全部变化 | 最近的 `-full` 加最新的一个 `-diff` |

以下情况做全量：基准快照超过 `INTERVAL_DAYS`（任务级）/ `BACKUP_INTERVAL_DAYS`（全局）天；或增量链需要的快照文件不存在。

```
第 1 天      FILE-site-...-full.tar.bz2    全部文件
第 2–14 天   FILE-site-...-inc.tar.bz2     只有前一天以来变化的文件
第 15 天     FILE-site-...-full.tar.bz2    开始新的一条链
```

注意：

- **tar 按 ctime 判断变化，不只看 mtime。** 对源目录执行 `chown -R`、`chmod -R` 后，下一次会把所有文件重新打包。增量模式下只多一次大包；差异模式下直到下次全量前每次都是大包。
- tar 返回 `1`（读取时有文件被修改）视为成功，备份包可用。
- tar 失败时快照会回滚，下次不会漏掉这些变化。
- 备份包先写成 `*.part`，完成后才改名。
- tar 以 `nice` / `ionice` 低优先级运行，减少对线上网站的影响。

## 推送到 NAS

`cron_unidump push` 调用 `scripts/rsyncPush.sh`，读取 `~/.cron_unidump.conf` 中的 `PUSH_*` 配置。

执行顺序：

1. 加锁（`flock`）。已有推送在运行时直接退出。
2. 如果有 `cron_unidump backup` 正在运行，等待它结束（最长 `PUSH_WAIT_MAX` 秒）。
3. 用严格主机密钥校验（`PUSH_KNOWN_HOSTS`）连接 NAS，创建 `<PUSH_PATH>/<PUSH_SERVER>`。
4. 执行 `rsync --remove-source-files`，跳过 `*.part`。rsync 确认某个文件传输成功后才删除本地这个文件。
5. 任何一步失败，本地文件都保留，下次推送重试。

NAS 上的结果：`<PUSH_PATH>/<PUSH_SERVER>/backup/<任务名>/<备份包>`。

### 首次配置推送

```bash
# 1. 生成推送用的密钥（已有可跳过）
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub        # 把这一行加到 NAS 上 PUSH_USER 的 ~/.ssh/authorized_keys

# 2. 保存 NAS 主机密钥，并与 NAS 本机的指纹核对
ssh-keyscan -p 22 nas.example.com > ~/.ssh/known_hosts_nas
ssh-keygen -lf ~/.ssh/known_hosts_nas
#   在 NAS 上执行：ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

# 3. 在 ~/.cron_unidump.conf 中设置 PUSH_HOST、PUSH_USER、PUSH_PATH、PUSH_SERVER，
#    以及 PUSH_SSH_KEY=~/.ssh/id_ed25519，然后测试：
cron_unidump push && tail /var/log/backup/rsyncPush.log
```

推送到 NAS 的文件全部保留，本工具不会删除 NAS 上的任何文件，需要自己定期清理。清理时不要删掉后续 `-inc` 仍然依赖的 `-full`。

## 恢复

### 文件

按时间顺序从旧到新解压：先最近的 `-full`，再依次解压它之后的每个 `-inc`（差异模式：`-full` 之后只解压最新的一个 `-diff`）。`-g /dev/null` 让 tar 同时删除两次备份之间被删掉的文件。

```bash
mkdir /restore && cd /restore
tar -xjf FILE-site-2026-01-01-19-50-01-full.tar.bz2 -g /dev/null
tar -xjf FILE-site-2026-01-02-19-50-01-inc.tar.bz2  -g /dev/null
tar -xjf FILE-site-2026-01-03-19-50-01-inc.tar.bz2  -g /dev/null
# 结果在 /restore/var/www/site/
```

备份包内保存的是绝对路径（`/var/www/site/...`）。上面的写法会去掉开头的 `/`，解压到当前目录，比较安全。加 `-P` 或 `-C /` 会直接覆盖线上目录，确认需要时再用。

不解压检查备份包：`bzip2 -t FILE.tar.bz2 && tar -tjf FILE.tar.bz2 | head`

### 数据库

```bash
mkdir /restore-db && cd /restore-db
tar -xzf DB-site_db-2026-01-03-19-50-01.tar.gz
find . -name backup.sql                                  # mysqldump 导出的 SQL
mysql -u root -p site_db < ./var/www/html/backup/site/<时间>/backup.sql
# mydumper 备份：myloader -u root -p -B site_db -d <解压出的目录> -o
```

`cron_unidump restore` 尚未实现，按上面的步骤手动恢复。

## 文件与日志位置

| 路径 | 内容 |
|---|---|
| `/var/www/html/backup/<任务>/` | 已完成、等待推送的备份包（`fileDir` / `dbDir`） |
| `/var/log/backup/<任务>/<任务>-<时间>.log` | 每次备份的日志 |
| `/var/log/backup/<任务>/snapshot-<任务>-incremental` | 当前增量链的 tar 快照 |
| `/var/log/backup/<任务>/snapshot-<任务>-incremental-intervalBase` | 最近一次全量的快照 |
| `/var/log/backup/<任务>/snapshot-<任务>-incremental-YYMMDD.log` | 每次备份前的快照（历史记录与回滚用） |
| `/var/log/backup/rsyncPush.log` | 推送日志 |
| `/var/log/backup/cron_unidump.log` | cron 输出（按上面的写法重定向时） |

备份包命名（时间为 UTC）：`FILE-<任务>-<时间>-<full|inc|diff>.tar.bz2`、`DB-<库名>-<时间>.tar.gz`。

磁盘空间：备份目录所在分区至少要能放下两份最大的全量包（一份已完成，一份正在写的 `*.part`）。如果推送连续多天失败，需要更多空间。

## 配置项参考

全局配置写在 `~/.cron_unidump.conf`，任务配置写在 `~/.cron_unidump.d/<name>.conf`，任务配置优先。两个文件都按 bash 语法加载，含空格的值要加引号。

### 全局

| 变量 | 默认值 | 说明 |
|---|---|---|
| `fileDir` | `/var/www/html/backup` | 文件备份包输出目录（`<fileDir>/<任务>/`） |
| `dbDir` | `/var/www/html/backup` | 数据库备份包输出目录 |
| `logDir` | `/var/log/backup` | 快照与日志目录 |
| `BACKUP_FILEOWN` | — | 备份包的属主，`用户:组` |
| `BACKUP_INTERVAL_DAYS` | — | 全量文件备份间隔天数（请设置，例如 14） |
| `BACKUP_FILE_MODE` | `incremental` | `incremental` 或 `differential` |
| `BACKUP_HOST` / `BACKUP_USER` / `BACKUP_PASS` | — | 默认 MySQL 连接信息 |
| `BACKUP_MAIL` | — | 保持 `n`，邮件功能未实现 |
| `PUSH_HOST` | 无（必填） | NAS 主机名或 IP |
| `PUSH_USER` | 无（必填） | NAS 上的 SSH 用户 |
| `PUSH_PATH` | 无（必填） | NAS 上的基础目录 |
| `PUSH_SERVER` | 无（必填） | 本服务器在 NAS 上的子目录 |
| `PUSH_PORT` | `22` | NAS 的 SSH 端口 |
| `PUSH_SRC` | `/var/www/html/backup` | 要推送的本地目录（应与 `fileDir`/`dbDir` 一致） |
| `PUSH_SSH_KEY` | `~/.ssh/id_rsa` | 登录 NAS 的私钥 |
| `PUSH_KNOWN_HOSTS` | `~/.ssh/known_hosts_nas` | 保存 NAS 主机密钥的 known_hosts |
| `PUSH_LOG` | `/var/log/backup/rsyncPush.log` | 推送日志 |
| `PUSH_LOCK` | `/var/lock/rsyncPush.lock` | 锁文件 |
| `PUSH_WAIT_MAX` | `21600` | 等待正在运行的备份的最长秒数 |
| `PUSH_BWLIMIT` | 空 | rsync 限速（KiB/s），空表示不限 |

### 任务：文件

| 变量 | 说明 |
|---|---|
| `SOURCE` | 要备份的目录（`backup file` 必填） |
| `EXCLUDE` | 要跳过的路径（bash 数组）：相对 `SOURCE` 的路径、绝对路径、通配符，或现成的 `--exclude=...` 参数 |
| `EXTRA_SOURCE` | 一起打包的额外目录（bash 数组） |
| `INTERVAL_DAYS` | 覆盖 `BACKUP_INTERVAL_DAYS` |
| `FILE_MODE` | 覆盖 `BACKUP_FILE_MODE` |

### 任务：数据库

| 变量 | 说明 |
|---|---|
| `DBNAME` | 数据库名；多个用 `db1,db2`（仅 mysqldump） |
| `DBHOST` / `DBUSER` / `DBPASS` | 覆盖全局的连接信息 |
| `DBENGINE` | `mysqldump`（任意引擎）、`innodb`（用 `mydumper`）、`myisam`（用 `mysqlhotcopy`）；未设置时为 `myisam` |
| `DBOPTIONS` | 传给导出工具的额外参数，例如 `--single-transaction` |
| `DBSQLDUMP_TABLES` | 仅 mysqldump：只导出这些表 |

`DBENGINE` 为 `innodb` / `myisam` 时，导出前会检查所有表是否都是该引擎。引擎混用时请设为 `mysqldump`。

## 故障排查

| 现象 | 检查方法 |
|---|---|
| 每个"增量"包都和全量一样大 | 有操作改了所有文件的 ctime（`chown -R`、`chmod -R`、恢复文件等）。统计被打包的文件数：`tr '\0' '\n' < /var/log/backup/<任务>/snapshot-<任务>-incremental \| grep -c '^Y'` |
| NAS 上的包比源小 / `bzip2 -t` 报错 | 推送时包还没写完（旧版固定时间推送导致）。改用 `cron_unidump run`，再推送一次 |
| 推送日志：`not configured: PUSH_...` | 在 `~/.cron_unidump.conf` 中设置列出的 `PUSH_*` 变量 |
| 推送日志：`NAS preflight failed` | 执行 `ssh -i $PUSH_SSH_KEY -p $PUSH_PORT -o UserKnownHostsFile=$PUSH_KNOWN_HOSTS $PUSH_USER@$PUSH_HOST true` 查看具体错误（公钥未授权、主机密钥变化、端口不通） |
| 推送日志：`backup still running after ...` | 备份超过了 `PUSH_WAIT_MAX`，或有卡住的进程：`pgrep -fa cron_unidump` |
| `Config file ... is no exists` | 任务名在 `~/.cron_unidump.d/` 中没有对应的配置文件 |
| 数据库任务报 "table engine have differences" | 表引擎与 `DBENGINE` 不一致，改为 `DBENGINE='mysqldump'` |
| 备份目录越来越满 | 推送一直失败，查看 `/var/log/backup/rsyncPush.log` |

## 已知限制

- `restore`、`check`、`clear_db` 未实现（恢复请按上文手动操作）。
- 邮件通知未实现。
- 数据库每次都是完整导出，没有增量。
- NAS 端不自动清理，需要手动。
- 配置文件里的密码是明文，两处配置目录都应只允许属主访问（`install` 已设为 600/700）。

## 给 AI Agent

代码结构、不可破坏的约定和测试方法见 [AGENTS.md](AGENTS.md)。

## 许可证

Apache License 2.0，见 [LICENSE](LICENSE)。原作者：Ryanlau（showq）。
