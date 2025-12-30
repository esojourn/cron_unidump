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

# 删除配置
cron_unidump remove myapp
```

### 备份操作

```bash
# 备份数据库
cron_unidump backup db myapp

# 备份文件
cron_unidump backup file myapp

# 备份所有
cron_unidump backup all myapp

# 恢复备份
cron_unidump restore myapp 2024-12-30
```

### 系统管理

```bash
# 安装 cron_unidump
./cron_unidump.sh install

# 卸载 cron_unidump
./cron_unidump.sh uninstall

# 显示帮助
./cron_unidump.sh -h
```

## 🎁 高级功能

### 自动调度

在 crontab 中添加计划任务：

```bash
# 每天凌晨2点备份
0 2 * * * cron_unidump backup all myapp

# 每周一备份
0 2 * * 1 cron_unidump backup db myapp

# 每月1号备份
0 2 1 * * cron_unidump backup all myapp
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

### 增量备份

文件备份自动支持增量备份：

```bash
# 配置完整备份间隔（天）
INTERVAL_DAYS=30

# 默认行为
# - 每30天进行一次完整备份
# - 其他时间进行增量备份
# - 使用 tar 快照文件追踪变更
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

## 📄 许可证

此项目遵循相关许可证。

## 🤝 贡献

欢迎提交问题和拉取请求！

## 📞 支持

如有问题，请查看 CLAUDE.md 文件了解项目架构和实现细节。

---

**最后更新**: 2024年12月30日
**版本**: 2.0.0（支持多个排除路径）
