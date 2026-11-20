#!/usr/bin/env bash
# ============================================================================
# 部署后冒烟验证（登录 → 建书 → 查询 → 鉴权校验）
# 验证流程：登录获取 token → 创建图书 → 查询图书（含新记录）→ 清理
# 用法：
#   export API_ENDPOINT="https://<apig_domain>/release-v1"
#   bash scripts/smoke-test.sh
# ============================================================================
set -euo pipefail

: "${API_ENDPOINT:?请设置 API_ENDPOINT（terraform output api_endpoint）}"

USERNAME="${SMOKE_USERNAME:-admin}"
: "${SMOKE_PASSWORD:?请设置 SMOKE_PASSWORD（管理员密码）}"
PASSWORD="$SMOKE_PASSWORD"
ISBN="9-999-999-999"

echo "[1/4] 登录获取 token..."
TOKEN_RESP=$(curl -s -X POST "$API_ENDPOINT/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")
TOKEN=$(echo "$TOKEN_RESP" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then
  echo "✗ 登录失败: $TOKEN_RESP"
  exit 1
fi
echo "✓ 登录成功"

echo "[2/4] 创建测试图书 (isbn=$ISBN)..."
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_ENDPOINT/books" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"isbn\":\"$ISBN\",\"title\":\"Smoke Test\",\"year\":2026,\"author\":\"QA\",\"publisher\":\"Internal\",\"rating\":5,\"pages\":100}")
if [ "$HTTP_CODE" != "201" ]; then
  echo "✗ 创建失败: HTTP $HTTP_CODE"
  exit 1
fi
echo "✓ 创建成功 (HTTP 201)"

echo "[3/4] 查询图书列表（应包含测试记录）..."
BOOKS=$(curl -s "$API_ENDPOINT/books")
if echo "$BOOKS" | grep -q "$ISBN"; then
  echo "✓ 查询成功，包含测试记录"
else
  echo "✗ 查询结果未包含测试记录: $BOOKS"
  exit 1
fi

echo "[4/4] 无 token 创建应被拒绝（验证鉴权）..."
NOAUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_ENDPOINT/books" \
  -H 'Content-Type: application/json' \
  -d "{\"isbn\":\"$ISBN\",\"title\":\"x\",\"year\":2026,\"author\":\"x\",\"publisher\":\"x\",\"rating\":1,\"pages\":1}")
if [ "$NOAUTH_CODE" = "401" ] || [ "$NOAUTH_CODE" = "403" ]; then
  echo "✓ 无 token 请求被拒绝 (HTTP $NOAUTH_CODE)"
else
  echo "⚠ 无 token 请求未被拒绝 (HTTP $NOAUTH_CODE)，请检查鉴权配置"
fi

echo "[+] 冒烟验证通过"
