# cron_unidump - 自动化备份管理工具

一个为 Linux 系统管理员设计的 Bash 备份工具，提供统一的接口来自动化备份、管理和恢复 MySQL 数据库和文件系统。

## 📋 目录

- [功能特性](#功能特性)
- [安装](#安装)
- [快速开始](#快速开始)
- [配置指南](#配置指南)
- [常用命令](#常用命令)
- [高级功能](#高级功能)
- [排除路径详解](#排除路径详解)
- [故障排除](#故障排除)
- [已知限制](#已知限制)
- [配置文件参考](#配置文件参考)

## 🎯 功能特性

### 核心功能
- **MySQL 数据库备份** - 支持 MyISAM、InnoDB 等多种引擎
- **文件系统备份** - 支持增量备份和完整备份
- **灵活配置** - 基于配置文件的备份配置管理
- **自动调度** - 与 cron 集成的自动备份任务
- **邮件通知** - 备份完成后的邮件通知（可选）

### 新增功能 ✨
- **多个排除路径支持** - 在文件备份时排除多个目录和文件模式
- **相对路径处理** - 支持相对于备份源的相对路径
- **通配符支持** - 支持 glob 模式进行灵活排除
- **路径验证** - 对不存在的排除路径显示警告

## 📦 安装

### 前置要求

```bash
# 必需工具
- Bash 4.0+
- mysql / mysqldump / mysqlhotcopy / mydumper
- tar（支持快照功能）
- find, md5sum, date, hostname, sudo

# 可选工具
- mutt（邮件通知）
```

### 安装步骤

```bash
# 1. 下载或克隆项目
git clone <repository-url>
cd cron_unidump

# 2. 运行安装脚本
./cron_unidump.sh install

# 3. 初始化默认配置
# 安装后会在 ~/.cron_unidump.d/ 创建配置目录
```

## 🚀 快速开始

### 创建第一个备份配置

```bash
# 创建新的备份配置
./cron_unidump.sh add myapp

# 编辑配置文件
vi ~/.cron_unidump.d/myapp.conf
```

### 配置示例

```bash
# 文件备份配置
SOURCE='/var/www/myapp'

# 排除路径（新增功能）
EXCLUDE=("cache" "tmp" "logs/*.log" "/var/cache/myapp")

EXTRA_SOURCE=""

# 数据库备份配置
DBHOST='localhost'
DBUSER='backup_user'
DBPASS='password'
DBNAME='myapp_db'
DBENGINE='innodb'
```

### 执行备份

```bash
# 备份数据库
./cron_unidump.sh backup db myapp

# 备份文件
./cron_unidump.sh backup file myapp

# 备份所有（数据库+文件）
./cron_unidump.sh backup all myapp
```

## 📖 配置指南

### 全局配置

全局配置文件位于 `$HOME/.cron_unidump.conf`，包含默认设置：

```bash
# 备份存储目录
fileDir="$HOME/.cron_unidump/files"
dbDir="$HOME/.cron_unidump/dbs"
logDir="$HOME/.cron_unidump/logs"

# 默认数据库凭证
BACKUP_HOST='localhost'
BACKUP_USER='root'
BACKUP_PASS=''

# 文件所有权
BACKUP_FILEOWN='root:root'

# 邮件通知
BACKUP_MAIL='y'
BACKUP_EMAILS='admin@example.com'
BACKUP_SUBJECT='Backup Report'

# 保留策略
BACKUP_DELETE='y'
BACKUP_INTERVAL_DAYS=30
```

### 单个备份配置

每个备份配置存储在 `~/.cron_unidump.d/{name}.conf`：

```bash
#------Files------#
SOURCE='/var/www/myapp'

# 排除路径（支持多个）
EXCLUDE=("cache" "tmp" "logs")

EXTRA_SOURCE=""

#------Database------#
DBHOST='localhost'
DBUSER='myapp_user'
DBPASS='password'
DBNAME='myapp_db'
DBENGINE='innodb'
DBOPTIONS=''
```

## 🔧 常用命令

### 配置管理

```bash
# 列出所有备份配置
cron_unidump list

# 查看配置内容
cron_unidump show myapp

# 编辑配置
cron_unidump edit myapp

# 创建新配置
cron_unidump add myapp
```

### 清理旧备份

```bash
# 删除 60 天前的备份文件
cron_unidump clear_db myapp 60
```

### 备份操作

```bash
# 备份数据库
cron_unidump backup db myapp

# 备份文件
cron_unidump backup file myapp

# 备份所有
cron_unidump backup all myapp

# 恢复备份（⚠️ 开发中）
# cron_unidump restore myapp 2024-12-30
```

⚠️ **当前限制**：
- ✅ 支持列出备份文件并选择
- 🚧 数据库恢复功能开发中
- ❌ 文件恢复暂不支持

### 系统管理

```bash
# 安装 cron_unidump
./cron_unidump.sh install

# 卸载 cron_unidump
./cron_unidump.sh uninstall

# 显示帮助（⏳ 即将支持）
./cron_unidump.sh help

# 检查配置（⏳ 即将支持）
./cron_unidump.sh check
```

## 🎁 高级功能

### 自动调度

在 crontab 中添加计划任务。使用 `crontab -e` 编辑：

**基础示例**：
```bash
# 每天凌晨2点完整备份
0 2 * * * cron_unidump backup all myapp

# 每周一凌晨2点备份数据库
0 2 * * 1 cron_unidump backup db myapp

# 每月1号凌晨2点备份所有
0 2 1 * * cron_unidump backup all myapp
```

**生产环境最佳实践**：

```bash
# 1. 日志记录（推荐）
0 2 * * * /usr/bin/cron_unidump backup all myapp >> /var/log/cron_backup.log 2>&1

# 2. 失败时发送邮件告警
0 2 * * * /usr/bin/cron_unidump backup all myapp || mail -s "⚠️ 备份失败" admin@example.com

# 3. 定期清理旧备份（每月1号凌晨4点）
0 4 1 * * /usr/bin/cron_unidump clear_db myapp 60

# 4. 多站点错开时间（避免 I/O 竞争）
0 2 * * * /usr/bin/cron_unidump backup all site1 >> /var/log/backup_site1.log 2>&1
30 2 * * * /usr/bin/cron_unidump backup all site2 >> /var/log/backup_site2.log 2>&1
0 3 * * * /usr/bin/cron_unidump backup all site3 >> /var/log/backup_site3.log 2>&1
```

**日志轮转配置** (`/etc/logrotate.d/cron_unidump`）：

```bash
/var/log/cron_backup.log
/var/log/backup_site*.log
{
    weekly          # 每周轮转一次
    rotate 4        # 保留 4 个历史文件
    compress        # 压缩旧日志
    delaycompress   # 延迟压缩
    missingok       # 文件不存在不报错
    notifempty      # 空文件不轮转
    create 0640 root root
}
```

**日志位置**：
- 备份日志：`~/.cron_unidump/logs/{name}/`
- Cron 日志：`/var/log/cron_backup.log`（自定义）

### 邮件通知（需手动启用）

⚠️ **当前状态**：功能已实现但默认禁用（代码被注释）

**启用步骤**：

1. 安装邮件工具：
   ```bash
   sudo apt-get install mutt
   ```

2. 配置 mutt SMTP 设置（自行参考 mutt 文档）

3. 取消 `cron_unidump.sh` 中第 229-234 行的注释：
   ```bash
   # 找到这段代码并取消注释
   # echo -e "$BODY" | mutt -s "$SUBJECT" $ATTACH -- $DBMAILTO
   ```

4. 在配置文件中启用邮件通知：
   ```bash
   BACKUP_MAIL=y
   BACKUP_EMAILS="admin@example.com"
   BACKUP_SUBJECT="MySQL 备份 - $SERVER ($DATE)"
   ```

**功能说明**：
- ✅ **数据库备份邮件** - 包含备份文件 MD5 校验和
- ❌ **文件备份邮件** - 暂不支持（仅数据库备份支持）

**配置示例**：
```bash
# 全局配置：~/.cron_unidump.conf
BACKUP_MAIL=y
BACKUP_EMAILS="admin@example.com backup@example.com"

# 单个备份配置：~/.cron_unidump.d/myapp.conf
DBMAIL=y                          # 覆盖全局设置
DBMAILTO="ops@example.com"        # 覆盖收件人
```

### 多数据库引擎支持

```bash
# MyISAM 表
DBENGINE='myisam'

# InnoDB 表（推荐）
DBENGINE='innodb'

# 通用备份
DBENGINE='mysqldump'
```

**数据库引擎选择指南**：

| 引擎 | 备份工具 | 适用场景 | 速度 | 特点 |
|------|---------|---------|------|------|
| `myisam` | mysqlhotcopy | 纯 MyISAM 表 | ⚡⚡⚡ 最快 | 物理复制，需锁表 |
| `innodb` | mydumper | InnoDB 表（推荐） | ⚡⚡ 快 | 并行备份，保证一致性 |
| `mysqldump` | mysqldump | 混合引擎 | ⚡ 较慢 | 兼容性最好 |

**选择建议**：
- **现代 Web 应用** → `innodb`（Laravel、WordPress 5.5+、Drupal 9+）
- **大型数据库** → `innodb`（支持并行备份）
- **混合引擎** → `mysqldump`
- **遗留系统** → `myisam`

### 增量备份

文件备份自动支持增量备份机制。

**工作原理**：

- 使用 GNU tar 的 `-g` 快照功能追踪文件系统状态
- 记录文件的 inode、修改时间等元数据
- 仅备份变化的文件，大幅减少备份大小和时间

**两级快照策略**：

```
Day 1:  完整备份 → 创建基准快照
Day 2-29: 增量备份 → 基于基准快照
Day 30: 完整备份 → 更新基准快照
```

快照文件位置（自动管理）：
- `snapshot-{name}-incremental` - 当前增量快照
- `snapshot-{name}-intervalBase` - 周期基准快照

**配置完整备份间隔**：

```bash
INTERVAL_DAYS=30  # 每30天进行一次完整备份
```

⚠️ **恢复说明**：

恢复增量备份需要：
1. 对应的完整备份文件
2. 所有后续增量备份（按时间顺序）
3. 在目标目录执行逐一恢复

```bash
# 恢复完整备份
tar -xjf FILE-myapp-2024-12-01.tar.bz2 -C /restore/path

# 恢复增量备份（按时间顺序）
tar -xjf FILE-myapp-2024-12-10.tar.bz2 -C /restore/path
tar -xjf FILE-myapp-2024-12-20.tar.bz2 -C /restore/path
```

## 🚫 排除路径详解

### 什么是排除路径？

排除路径用于在文件备份时跳过指定的文件或目录，不将其包含在备份存档中。这有助于：
- 减少备份文件大小
- 加快备份速度
- 避免备份临时文件或缓存
- 保护敏感文件

### 配置格式

排除路径使用 Bash 数组语法配置：

```bash
EXCLUDE=("path1" "path2" "path3")
```

### 支持的路径类型

#### 1. 绝对路径

从文件系统根开始的完整路径：

```bash
EXCLUDE=("/var/www/cache" "/tmp/uploads" "/var/log/old")
```

#### 2. 相对路径

相对于 `SOURCE` 目录的路径（自动转换为绝对路径）：

```bash
SOURCE="/var/www/myapp"
EXCLUDE=("cache" "tmp" "logs")

# 等同于：
# EXCLUDE=("/var/www/myapp/cache" "/var/www/myapp/tmp" "/var/www/myapp/logs")
```

#### 3. 通配符模式

使用 glob 模式进行灵活匹配：

```bash
EXCLUDE=("*.log" "*.tmp" "*.bak" "node_modules")
```

#### 4. 混合使用

在同一配置中混合使用多种类型：

```bash
SOURCE="/var/www/myapp"
EXCLUDE=(
  "cache"                           # 相对路径
  "/var/cache/myapp"               # 绝对路径
  "*.log"                           # 通配符
  "/tmp/uploads"                    # 绝对路径
  "vendor/*/tests"                  # 相对路径 + 通配符
)
```

### 实际示例

#### 示例1：Web 应用备份

```bash
SOURCE="/var/www/laravel-app"
EXCLUDE=(
  "storage/logs"
  "storage/cache"
  "bootstrap/cache"
  "node_modules"
  ".git"
  "*.log"
  ".env.local"
)
```

#### 示例2：Drupal 站点备份

```bash
SOURCE="/var/www/drupal"
EXCLUDE=(
  "sites/default/files/cache"
  "sites/default/files/tmp"
  "sites/default/files/js"
  "sites/default/files/css"
  ".git"
  "*.tar.gz"
)
```

#### 示例3：通用服务器备份

```bash
SOURCE="/var/www"
EXCLUDE=(
  "*/cache"
  "*/logs"
  "*/tmp"
  "*/.git"
  "*/node_modules"
  "*/vendor"
  "*.log"
)
```

### 排除路径验证

- ✅ 存在的路径 - 正常排除，显示 "Excluding: ..." 消息
- ⚠️ 不存在的路径 - 显示警告 "Warning: Exclude path not found: ..."，但继续备份
- ✅ 通配符模式 - 跳过验证，由 tar 处理匹配

### 常见问题

**Q: 路径中有空格怎么办？**
```bash
# 在配置文件中使用引号
EXCLUDE=("path with spaces" "another path")
```

**Q: 如何排除所有日志文件？**
```bash
EXCLUDE=("logs" "*.log" "**/*.log")
```

**Q: 排除路径支持递归吗？**
```bash
EXCLUDE=(
  "**/cache"        # 排除所有名为 cache 的目录
  "**/logs"         # 排除所有名为 logs 的目录
)
```

**Q: 如何验证排除是否生效？**
```bash
# 备份后检查归档内容
tar -tjf ~/.cron_unidump/files/FILE-myapp-*.tar.bz2 | grep cache
# 如果没有输出，说明排除成功
```

## 📊 备份结构

```
~/.cron_unidump/
├── files/                    # 文件备份
│   ├── myapp/
│   │   ├── FILE-myapp-20241230.tar.bz2
│   │   ├── .snapshot-myapp-incremental
│   │   └── .snapshot-myapp-intervalBase
│   └── otherapp/
├── dbs/                      # 数据库备份
│   ├── myapp/
│   │   ├── myapp_db-20241230.sql
│   │   └── myapp_db-20241230.sql.bz2
│   └── otherapp/
└── logs/                     # 备份日志
    ├── myapp/
    │   ├── myapp-20241230.log
    │   └── snapshot-myapp-incremental
    └── otherapp/
```

## 🆘 故障排除

### 备份失败

检查日志文件：
```bash
cat ~/.cron_unidump/logs/myapp/myapp-$(date +%Y%m%d).log
```

### 排除路径不生效

验证配置格式：
```bash
# 查看配置
cron_unidump show myapp

# 手动测试排除
bash -x cron_unidump.sh backup file myapp
```

### 数据库连接失败

验证凭证和权限：
```bash
mysql -h $DBHOST -u $DBUSER -p$DBPASS -e "SELECT VERSION();"
```

### 磁盘空间不足

检查备份目录大小：
```bash
du -sh ~/.cron_unidump/*
```

清理旧备份：
```bash
find ~/.cron_unidump/files -name "*.tar.bz2" -mtime +30 -delete
```

## ⚠️ 已知限制

### 功能限制

- ❌ **文件恢复** - 暂未实现，仅支持数据库恢复
- 🚧 **数据库恢复** - 选择备份文件功能完整，但实际恢复逻辑开发中
- 🚧 **邮件通知** - 代码已实现但默认禁用，需手动启用（见高级功能章节）
- ❌ **文件备份邮件** - 仅数据库备份支持邮件通知
- ❌ **远程备份存储** - 不支持 S3、FTP、阿里云 OSS 等远程存储

### 即将支持的命令

- `check` - 配置文件检查和验证
- `help` - 命令帮助信息
- `remove` - 删除备份配置（当前未实现）

### 开发计划

- [ ] 完善数据库恢复功能（自动化还原 SQL）
- [ ] 实现文件系统恢复功能
- [ ] 启用邮件通知功能（取消代码注释）
- [ ] 添加备份验证机制（MD5/SHA256 校验）
- [ ] 支持备份加密（AES-256）
- [ ] 实现配置检查命令（validate 配置）
- [ ] 添加远程备份支持（S3、FTP、SFTP）
- [ ] 创建 Web 管理界面

## 📝 配置文件参考

### 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `fileDir` | 文件备份目录 | `$HOME/.cron_unidump/files` |
| `dbDir` | 数据库备份目录 | `$HOME/.cron_unidump/dbs` |
| `logDir` | 日志目录 | `$HOME/.cron_unidump/logs` |
| `BACKUP_INTERVAL_DAYS` | 保留天数 | `30` |

### 文件备份配置

| 变量 | 说明 | 示例 |
|------|------|------|
| `SOURCE` | 备份源目录 | `/var/www` |
| `EXCLUDE` | 排除路径（数组） | `("cache" "logs")` |
| `EXTRA_SOURCE` | 额外备份目录 | `/var/html` |
| `INTERVAL_DAYS` | 完整备份间隔 | `30` |

### 数据库备份配置

| 变量 | 说明 | 示例 |
|------|------|------|
| `DBHOST` | 数据库主机 | `localhost` |
| `DBUSER` | 数据库用户 | `root` |
| `DBPASS` | 数据库密码 | `password` |
| `DBNAME` | 数据库名 | `myapp_db` |
| `DBENGINE` | 备份引擎 | `innodb` |
| `DBOPTIONS` | 额外选项 | `--lock-tables=false` |

**多数据库备份**：

支持备份多个数据库，使用逗号或空格分隔：

```bash
# 方式1：逗号分隔（推荐）
DBNAME='db1,db2,db3'

# 方式2：空格分隔
DBNAME='db1 db2 db3'

# 实际例子
DBNAME='wordpress,nextcloud,mediawiki'
```

⚠️ **注意事项**：
- `mysqldump` 引擎完全支持多库备份
- `mydumper` 和 `mysqlhotcopy` 可能不支持多库，建议使用 `mysqldump`
- 多库备份会生成单个备份文件，包含所有数据库

## 📄 许可证

此项目遵循相关许可证。详见 LICENSE 文件。

## 👤 作者

**Ryanlau** (showq@qq.com)

**版本历史**：
- **v1.0** (2014/10/23) - 初始版本，基础备份功能
- **v2.0** (2014/11/10) - 增强配置管理，支持多引擎
- **v2.1** (2024年更新) - 添加多排除路径支持，完善文档

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

如有任何建议或发现 Bug，请提交到项目仓库。

## 📞 支持

- **架构文档** - 详见 `CLAUDE.md` 文件了解项目架构和实现细节
- **配置示例** - 查看 `conf/` 目录获取更多配置模板
- **问题反馈** - 提交 GitHub Issue（如果有仓库）或联系作者

---

**最后更新**: 2024年12月31日
**版本**: 2.1（支持多个排除路径、邮件通知、完善文档）
