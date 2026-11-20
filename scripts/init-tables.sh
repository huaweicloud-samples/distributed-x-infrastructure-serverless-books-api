#!/usr/bin/env bash
# ============================================================================
# 初始化数据库（GeminiDB Cassandra）
#   · 创建 keyspace / books / users 表
#   · 插入默认用户（admin，密码由环境变量 ADMIN_PASSWORD 指定）
# 前置：terraform apply 已完成（获得 GeminiDB 内网地址）
# 用法：
#   export CASSANDRA_HOSTS="<gemini_db_lb_ip>"
#   export CASSANDRA_PORT="9042"
#   export CASSANDRA_PASSWORD="<实例密码>"
#   export ADMIN_PASSWORD="<初始管理员密码>"
#   bash scripts/init-tables.sh
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${CASSANDRA_HOSTS:?请设置 CASSANDRA_HOSTS（GeminiDB Cassandra 内网地址）}"
: "${CASSANDRA_PASSWORD:?请设置 CASSANDRA_PASSWORD（GeminiDB 实例密码）}"
: "${ADMIN_PASSWORD:?请设置 ADMIN_PASSWORD（初始管理员密码）}"

cd "$ROOT/scripts/init"
npm install --production --no-audit --no-fund >/dev/null 2>&1

CASSANDRA_HOSTS="$CASSANDRA_HOSTS" \
CASSANDRA_PORT="${CASSANDRA_PORT:-9042}" \
CASSANDRA_PASSWORD="$CASSANDRA_PASSWORD" \
ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  node init-tables.js

echo "[+] 表初始化完成。默认用户：admin（请尽快修改密码）"
