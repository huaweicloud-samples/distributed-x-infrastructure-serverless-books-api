# 部署指导书

本文档指导在华为云（以 cn-north-4 北京四为例）上完成整套部署与验证流程。

## 1. 前置条件

- 华为云账号（区域 `cn-north-4`），且拥有创建 APIG、GeminiDB 等资源的权限
- 已安装 [Terraform](https://developer.hashicorp.com/terraform/downloads)（>= 1.5）
- 已安装 Node.js（>= 18）与 npm，用于构建函数代码
- 本地可执行 `bash`（Windows 用户可使用 Git Bash / WSL）

## 2. 部署步骤

### 2.1 准备凭证

```bash
export HW_ACCESS_KEY="<你的AK>"
export HW_SECRET_KEY="<你的SK>"
```

### 2.2 构建函数代码

```bash
cd <本仓库根目录>
bash scripts/build-functions.sh
```

该脚本为 4 个函数安装依赖并生成 zip 包（`src/functions/<fn>/<fn>.zip`），这些包会被 Terraform 以内联方式（base64）上传到 FunctionGraph。

### 2.3 配置变量并部署

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars：填入 access_key / secret_key / db_password

terraform init
terraform plan      # 确认创建计划
terraform apply     # 部署全部资源
```

部署完成后记录输出的 `api_endpoint`（形如 `https://<apig域名>/release-v1`）与 `geminidb_lb_ip`。

> 注意：`terraform apply` 会创建 APIG 专享版、GeminiDB 集群等资源，请确认部署范围后再执行。若 APIG 实例创建失败并返回 `APIC.9220 Insufficient account balance`，请检查账号状态后重试。

### 2.4 初始化数据库表与默认用户

```bash
export DDB_ENDPOINT="http://<geminidb_lb_ip>:8000"
export AWS_ACCESS_KEY_ID="<你的AK>"
export AWS_SECRET_ACCESS_KEY="<你的SK>"
export ADMIN_PASSWORD="<初始密码，如 Admin@12345>"
bash ../scripts/init-tables.sh
```

该脚本创建 `books` / `users` 表，并写入默认用户 `admin`。

### 2.5 冒烟验证

```bash
export API_ENDPOINT="<terraform output api_endpoint>"
export SMOKE_USERNAME="admin"
export SMOKE_PASSWORD="<ADMIN_PASSWORD>"
bash ../scripts/smoke-test.sh
```

验证项：
1. 登录获取 JWT
2. 携带 token 创建图书 → 期望 HTTP 201
3. 查询图书列表 → 应包含刚创建的记录
4. 无 token 创建 → 期望被拒绝（401/403）

## 3. 接口说明

### 3.1 登录

```bash
curl -X POST "$API_ENDPOINT/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<密码>"}'
```

响应：

```json
{ "token": "<jwt>", "token_type": "Bearer", "expires_in": 3600 }
```

### 3.2 新增图书

```bash
curl -X POST "$API_ENDPOINT/books" \
  -H "Authorization: Bearer <jwt>" \
  -H 'Content-Type: application/json' \
  -d '{"isbn":"978-3-16-148410-0","title":"Example Book","year":2026,"author":"Author","publisher":"Pub","rating":5,"pages":200}'
```

期望：`HTTP 201`

### 3.3 查询图书

```bash
curl "$API_ENDPOINT/books"
```

期望：`HTTP 200`，返回图书 JSON 数组。

## 4. 更新函数代码

修改 `src/functions/<fn>/index.js` 后：

```bash
bash scripts/build-functions.sh   # 重新构建 zip
cd infra
terraform apply                   # 更新函数代码（仅变更函数）
```

## 5. 清理资源

```bash
cd infra
terraform destroy
```

> 提示：GeminiDB 实例删除较慢（约 30 分钟）。若删除时提示超时（`context deadline exceeded`），等待删除完成后再执行一次 `terraform destroy` 即可，实例可能已在删除中。

## 6. 常见问题

| 现象 | 原因与处理 |
|------|-----------|
| `APIC.9220 Insufficient account balance` | 账号状态异常导致 APIG 专享版创建失败，检查账号状态后重试 |
| `FSS.1501 The delegate not exist` | IAM 委托服务主体错误，确认委托为 `op_svc_cff` 云服务委托 |
| 函数创建报 `FSS.1027 Invalid packageName` | 函数缺少应用分组，确认 `app = "default"` |
| `handler expect to have 2 or 3 parameters` | Node.js handler 签名必须为 `(event, context)` |
| 登录接口报错/超时 | 确认 DDB_ENDPOINT 指向 GeminiDB 内网地址、安全组已放行 8000 端口、函数已配置 VPC |
