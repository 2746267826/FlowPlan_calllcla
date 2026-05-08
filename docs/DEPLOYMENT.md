# FlowPlanV2 部署指南 v2.0.0

> 从一台全新的 Ubuntu 服务器开始，到 FlowPlanV2 完全运行。

---

## 0. 环境概览

| 组件 | 版本要求 | 用途 |
|------|---------|------|
| Ubuntu | 22.04+ / 24.04 | 操作系统 |
| Node.js | 18+ (推荐 22 LTS) | 服务端运行时 |
| PostgreSQL | 14+ (推荐 16) | 主数据库 |
| pgvector | 0.7+ | 向量相似度搜索 (可选) |
| Nginx | 任意 | 反向代理 |
| systemd | 内置 | 进程守护 |

---

## 1. 系统初始化

### 1.1 更新系统

```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 安装基础工具

```bash
sudo apt install -y curl git build-essential nginx
```

### 1.3 设置时区

```bash
sudo timedatectl set-timezone Asia/Shanghai
```

---

## 2. Node.js 安装

```bash
# 使用 NodeSource 安装 Node.js 22 LTS
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 验证
node --version  # ≥22.0.0
npm --version
```

---

## 3. PostgreSQL 安装与配置

### 3.1 安装

```bash
# Ubuntu 24.04 使用官方源安装 PostgreSQL 16
sudo apt install -y postgresql postgresql-contrib
```

### 3.2 创建数据库和用户

```bash
sudo -u postgres psql <<SQL
CREATE DATABASE flowplanv2;
CREATE DATABASE flowplantest;              -- 测试数据库
CREATE USER flowplanv2 WITH PASSWORD 'YOUR_SECURE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE flowplanv2 TO flowplanv2;
GRANT ALL PRIVILEGES ON DATABASE flowplantest TO flowplanv2;
\c flowplanv2
GRANT ALL ON SCHEMA public TO flowplanv2;
\c flowplantest
GRANT ALL ON SCHEMA public TO flowplanv2;
SQL
```

### 3.3 配置慢查询日志

```sql
sudo -u postgres psql <<SQL
ALTER SYSTEM SET log_min_duration_statement = 500;   -- 500ms
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
SELECT pg_reload_conf();
SQL
```

### 3.4 (可选) 安装 pgvector

```bash
# Ubuntu 24.04
sudo apt install -y postgresql-16-pgvector

# 启用扩展
sudo -u postgres psql -d flowplanv2 -c "CREATE EXTENSION IF NOT EXISTS vector;"
sudo -u postgres psql -d flowplantest -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

---

## 4. 项目部署

### 4.1 克隆代码

```bash
cd /opt
sudo git clone <YOUR_REPO_URL> flowplanv2
sudo chown -R $USER:$USER /opt/flowplanv2
cd /opt/flowplanv2
```

### 4.2 配置环境变量

创建 `.env` 文件（或设置系统环境变量）：

```bash
# /opt/flowplanv2/server/.env

# ── 数据库 ──
FLOWPLANV2_DATABASE_URL=postgres://flowplanv2:YOUR_SECURE_PASSWORD@localhost:5432/flowplanv2
DATABASE_POOL_MAX=20
DATABASE_POOL_IDLE_TIMEOUT=60000
DATABASE_POOL_CONNECTION_TIMEOUT=15000
SLOW_QUERY_THRESHOLD_MS=1000

# ── 加密密钥（生产必设！建议 64 位随机 hex） ──
FLOWPLANV2_ENCRYPTION_KEY=<生成命令: openssl rand -hex 32>

# ── JWT ──
JWT_ACCESS_SECRET=<生成命令: openssl rand -hex 32>
JWT_REFRESH_SECRET=<生成命令: openssl rand -hex 32>
JWT_ACCESS_EXPIRES=24h
JWT_REFRESH_EXPIRES=7d

# ── 服务 ──
PORT=3202
HOST=0.0.0.0
FLOWPLANV2_BODY_LIMIT=50mb
ADMIN_CORS_ORIGIN=https://your-domain.com

# ── AI (可选) ──
AI_REQUEST_TIMEOUT_MS=30000

# ── 文件存储 ──
FLOWPLANV2_SERVER_STORAGE_DIR=/opt/flowplanv2/server_storage

# ── Kopia (可选，用于文件版本管理) ──
KOPIA_EXE=/opt/flowplanv2/server/kopia  # Linux binary
# KOPIA_TIMEOUT_MS=120000
```

### 4.3 安装依赖并对数据库应用迁移

```bash
cd /opt/flowplanv2/server
npm install
npm run db:schema
```

### 4.4 应用 pgvector 迁移 (可选)

```bash
DATABASE_URL="postgres://flowplanv2:PASS@localhost:5432/flowplanv2" \
  node -e "const{readFileSync}=require('fs');const{Pool}=require('pg');const p=new Pool({connectionString:process.env.DATABASE_URL});p.query(readFileSync('src/database/migrations/003_pgvector_optional.sql','utf8')).then(()=>{console.log('ok');p.end()})"
```

### 4.5 构建并启动

```bash
cd /opt/flowplanv2/server
npm run build
npm start
```

验证启动：
```bash
curl http://localhost:3202/api/health | jq
```
预期输出：
```json
{
  "ok": true,
  "service": "flowplanv2-server",
  "encryptionKeySecure": true,
  "poolStats": { "totalCount": 1, "idleCount": 1, "waitingCount": 0, "max": 20 }
}
```

### 4.6 管理端构建

```bash
cd /opt/flowplanv2/web_admin
npm install
npm run build
# 输出到 /opt/flowplanv2/web_admin/dist/
```

---

## 5. systemd 服务（开机自启）

创建 `/etc/systemd/system/flowplanv2.service`：

```ini
[Unit]
Description=FlowPlanV2 Server
After=network.target postgresql.service

[Service]
Type=simple
User=flowplanv2
WorkingDirectory=/opt/flowplanv2/server
Environment=NODE_ENV=production
EnvironmentFile=/opt/flowplanv2/server/.env
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

启用服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable flowplanv2
sudo systemctl start flowplanv2
sudo systemctl status flowplanv2
```

---

## 6. Nginx 反向代理

创建 `/etc/nginx/sites-available/flowplanv2`：

```nginx
server {
    listen 80;
    server_name your-domain.com;

    # 管理端静态文件
    location / {
        root /opt/flowplanv2/web_admin/dist;
        index index.html;
        try_files $uri /index.html;
    }

    # API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:3202;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50m;
    }

    # Swagger 文档
    location /api/docs {
        proxy_pass http://127.0.0.1:3202;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
```

启用并重载：

```bash
sudo ln -s /etc/nginx/sites-available/flowplanv2 /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 可选：HTTPS (Certbot)

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

---

## 7. 管理端使用

1. 浏览器访问 `https://your-domain.com`
2. 输入显示名称 → 点击登录
3. 配置 API 基础地址（首次使用默认 `http://localhost:3202`，生产环境改为域名）
4. 系统设置 → 远程配置
5. 可配置 Outlook OAuth（需先在 Azure AD 注册应用）
6. 可配置 AI Provider（OpenAI-compatible API）

### Swagger API 文档

访问 `https://your-domain.com/api/docs`

---

## 8. 维护

### 查看日志

```bash
sudo journalctl -u flowplanv2 -f
```

### 重启服务

```bash
sudo systemctl restart flowplanv2
```

### 数据库备份

```bash
pg_dump -U flowplanv2 -h localhost flowplanv2 > backup_$(date +%Y%m%d).sql
```

### 更新部署

```bash
cd /opt/flowplanv2
git pull
cd server
npm install
npm run db:schema
npm run build
sudo systemctl restart flowplanv2
cd ../web_admin
npm install
npm run build
```

---

## 9. 故障排查

| 问题 | 解决方案 |
|------|---------|
| 服务无法启动 | 检查 `.env` 中的 `DATABASE_URL`，确保 PostgreSQL 运行 |
| `encryptionKeySecure: false` | 设置 `FLOWPLANV2_ENCRYPTION_KEY` 环境变量 |
| 管理端 401 错误 | 确认 token 未过期，刷新页面重新登录 |
| 端口被占用 | 修改 `PORT` 环境变量或停止占用进程 |
| PostgreSQL 连接池耗尽 | 增大 `DATABASE_POOL_MAX` 或优化慢查询 |
