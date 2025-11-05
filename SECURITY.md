# 安全配置指南

## 🔐 密码安全存储

### 推荐方法：使用 MySQL 配置文件

这是最安全的方法，因为密码不会出现在进程列表中。

#### 步骤 1: 创建 MySQL 配置文件

```bash
# 复制示例文件
cp mysql_backup.cnf.example ~/.mysql_backup.cnf

# 设置严格的文件权限（只有所有者可读写）
chmod 600 ~/.mysql_backup.cnf
```

#### 步骤 2: 编辑配置文件

```bash
vim ~/.mysql_backup.cnf
```

内容：

```ini
[client]
user=root
password=your_secure_password_here
host=localhost

[mysqldump]
single-transaction
quick
lock-tables=false

[mydumper]
# mydumper specific options
```

#### 步骤 3: 配置 cron_unidump

编辑 `~/.cron_unidump.conf`：

```bash
# 使用 MySQL 配置文件（推荐）
BACKUP_MYSQL_DEFAULTS_FILE="$HOME/.mysql_backup.cnf"

# 注释掉密码行
# BACKUP_PASS="YOUR_PASSWORD_HERE"
```

#### 步骤 4: 测试连接

```bash
# 测试 MySQL 连接
mysql --defaults-file=~/.mysql_backup.cnf -e "SELECT 1;"

# 验证 cron_unidump 配置
cron_unidump check
```

### 替代方法：mysql_config_editor

MySQL 5.6.6+ 提供了更安全的密码存储工具：

```bash
# 配置加密的密码存储
mysql_config_editor set --login-path=backup_user \
  --host=localhost \
  --user=root \
  --password

# 测试
mysql --login-path=backup_user -e "SELECT 1;"
```

在 `cron_unidump.sh` 中修改 `mysqlCommand` 函数使用 login-path。

## 🔒 文件权限配置

### 配置文件权限

```bash
# 全局配置
chmod 600 ~/.cron_unidump.conf

# MySQL 凭据文件
chmod 600 ~/.mysql_backup.cnf

# 任务配置目录
chmod 700 ~/.cron_unidump.d
chmod 600 ~/.cron_unidump.d/*.conf
```

### 备份目录权限

```bash
# 创建备份目录
sudo mkdir -p /var/backup/{files,database,logs}

# 设置所有者
sudo chown -R your_user:your_group /var/backup

# 设置权限（只有所有者可访问）
sudo chmod 700 /var/backup
sudo chmod 700 /var/backup/*
```

### 日志目录权限

```bash
# 创建日志目录
sudo mkdir -p /var/log/backup

# 设置所有者
sudo chown your_user:your_group /var/log/backup

# 设置权限
sudo chmod 755 /var/log/backup
```

## 🛡️ Git 安全

### 防止敏感信息泄露

`.gitignore` 已配置排除：

```gitignore
# 配置文件
*.conf
!*.conf.example
*.conf.backup

# 凭据文件
.my.cnf
.mysql_backup.cnf

# 备份文件
backup/
*.tar.gz
*.tar.bz2

# 日志
*.log
```

### 移除已提交的敏感信息

如果之前已经提交了敏感信息：

```bash
# 使用 git-filter-branch（适用于小仓库）
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch cron_unidump.conf" \
  --prune-empty --tag-name-filter cat -- --all

# 或使用 BFG Repo-Cleaner（推荐，更快）
# 1. 下载 BFG
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar

# 2. 删除敏感文件
java -jar bfg-1.14.0.jar --delete-files cron_unidump.conf

# 3. 清理
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 4. 强制推送（⚠️ 慎用）
git push --force --all
```

### 更改已泄露的密码

如果密码已经被提交到 Git：

1. **立即更改 MySQL 密码**
2. 更新所有配置文件
3. 从 Git 历史中移除敏感信息
4. 通知团队成员更新配置

## 🔐 备份文件加密（可选）

### 方法 1: OpenSSL 加密

修改脚本以添加加密：

```bash
# 在备份后添加加密步骤
tar -czf - "$SOURCE" | openssl enc -aes-256-cbc -salt -out "$TARGET.enc"

# 解密
openssl enc -d -aes-256-cbc -in backup.tar.gz.enc -out backup.tar.gz
```

### 方法 2: GPG 加密

```bash
# 创建 GPG 密钥（如果没有）
gpg --gen-key

# 加密备份
tar -czf - "$SOURCE" | gpg --encrypt --recipient your-email@example.com -o "$TARGET.gpg"

# 解密
gpg --decrypt backup.tar.gz.gpg | tar -xzf -
```

## 🚨 安全检查清单

在部署到生产环境前，请确保：

- [ ] 使用 MySQL 配置文件或 mysql_config_editor
- [ ] 所有配置文件权限设置为 600
- [ ] 备份目录权限设置为 700
- [ ] `.gitignore` 正确配置
- [ ] 从 Git 历史中移除了敏感信息
- [ ] 已更改示例中的默认密码
- [ ] 备份文件定期测试恢复
- [ ] 日志文件定期清理
- [ ] cron 作业使用正确的用户运行
- [ ] 已禁用不必要的功能（如邮件发送）

## 🔍 安全审计

### 定期检查

```bash
# 检查文件权限
find ~/.cron_unidump.d -type f -not -perm 600

# 检查备份目录权限
ls -la /var/backup

# 检查 MySQL 用户权限
mysql -e "SELECT user, host FROM mysql.user WHERE user='backup_user';"

# 审计日志
grep -i "failed\|error" /var/log/backup/*.log
```

### 监控可疑活动

```bash
# 检查最近的备份
find /var/backup -type f -mtime -1

# 检查备份大小变化
du -sh /var/backup/* | sort -h

# 监控磁盘空间
df -h /var/backup
```

## 📞 紧急情况响应

### 如果密码泄露

1. **立即更改密码**：
   ```bash
   mysql -u root -p
   ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_secure_password';
   FLUSH PRIVILEGES;
   ```

2. **更新所有配置**
3. **审计访问日志**
4. **通知相关人员**

### 如果备份被删除

1. 检查是否有远程备份副本
2. 检查回收站/快照
3. 联系系统管理员
4. 从最近的备份恢复

## 🔗 相关资源

- [MySQL 安全最佳实践](https://dev.mysql.com/doc/refman/8.0/en/security.html)
- [Linux 文件权限指南](https://www.linux.com/training-tutorials/understanding-linux-file-permissions/)
- [Git 敏感数据移除](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
