#!/usr/bin/env bash
# ============================================================================
# 构建全部 FunctionGraph 函数 zip 包
# 产物：src/functions/<fn>/<fn>.zip（infra/main.tf 的 func_code 引用这些包）
# 用法：bash scripts/build-functions.sh
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for fn in create get-all auth authorizer; do
  DIR="$ROOT/src/functions/$fn"
  echo "[+] Building $fn"
  (cd "$DIR" && npm install --production --no-audit --no-fund >/dev/null 2>&1)
  (cd "$DIR" && rm -f "$fn.zip")
  if command -v zip >/dev/null 2>&1; then
    (cd "$DIR" && zip -rq "$fn.zip" index.js node_modules package.json)
  else
    # 兜底：python zipfile（Windows / 无 zip 命令环境）
    (cd "$DIR" && python -m zipfile -c "$fn.zip" index.js node_modules package.json 2>/dev/null \
      || python3 -m zipfile -c "$fn.zip" index.js node_modules package.json)
  fi
  echo "    -> $DIR/$fn.zip ($(du -h "$DIR/$fn.zip" | cut -f1))"
done

echo "[+] 全部函数构建完成。执行 terraform apply 前请确认 zip 已存在。"
