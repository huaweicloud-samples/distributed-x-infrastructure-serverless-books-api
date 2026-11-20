# 无服务器图书管理 API

![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue)

[English](./README.md)
![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Compatible-green)
![Serverless](https://img.shields.io/badge/Serverless-Enabled-orange)

## 简介

本项目演示如何在华为云上构建一个**无服务器的图书管理 API**，提供图书的新增与查询能力，并通过自建 JWT 鉴权保护写操作。

**核心功能：**

- `GET /books`：公开查询全部图书列表（ISBN、书名、作者、出版社、评分、页数等）
- `POST /books`：鉴权后新增图书（携带 JWT 访问令牌）
- `POST /auth/login`：用户登录，校验凭证并签发 JWT（HS256，默认 1 小时有效）
- 数据存储使用 GeminiDB Cassandra，应用侧通过标准 SDK 访问，仅需配置 endpoint

**核心价值：**

1. **完全无服务器**：API 网关 + 函数计算，无需管理任何服务器，按调用量弹性伸缩
2. **数据访问零改造**：标准 CQL 数据访问协议，应用代码使用 Cassandra 驱动
3. **安全开箱即用**：自建 JWT 鉴权 + 自定义鉴权器 + 数据库密码/密钥均经环境变量传递，不硬编码任何凭据
4. **一键部署**：Terraform 统一管理全部基础设施，一条命令完成部署

**适用场景：**

- 需要快速构建带鉴权的 RESTful API 的团队
- 希望用无服务器架构承载 CRUD 业务、零运维负担的场景
- 需要云原生宽表 NoSQL（Cassandra 协议）的场景

## 目录

- [架构图](#架构图)
- [方案亮点](#方案亮点)
- [涉及云服务](#涉及云服务)
- [前置条件](#前置条件)
- [快速开始](#快速开始)
- [分步部署](#分步部署)
- [使用方法](#使用方法)
- [清理资源](#清理资源)
- [详细说明](#详细说明)
- [常见问题](#常见问题faq)
- [许可证](#许可证)
- [联系方式](#联系方式)

## 架构图

```
                        ┌────────────────────────────────────────────┐
                        │                 APIG（专享版）              │
                        │                                            │
  HTTPS                 │  GET /books ──► books-get-all (FunctionGraph)
  ────────────────►     │  POST /books ─► 自定义鉴权器 ─► books-create │
  客户端                 │      ▲            (JWT 校验)                │
                        │  POST /auth/login ─► auth-login            │
                        └────────────┬───────────────────────────────┘
                                     │ FunctionGraph（VPC 内网）
                                     ▼
                        ┌─────────────────────────────┐
                        │  GeminiDB Cassandra   │
                        │  · books 表（isbn 主键）     │
                        │  · users 表（username 主键） │
                        └─────────────────────────────┘
```

## 方案亮点

- **JWT 自建鉴权链路**：登录函数签发令牌 + 自定义鉴权器在网关层校验，业务函数无感知
- **内网数据访问**：函数通过 VPC 内网连接数据库，数据不出私网
- **表结构自动初始化**：提供一键脚本创建数据表并写入默认用户
- **部署后冒烟验证**：内置 smoke-test 脚本，部署完成后自动验证登录/写入/查询/鉴权全链路

## 涉及云服务

| 服务 | 用途 |
|------|------|
| APIG（API 网关，专享版） | 对外暴露 REST API，承载自定义鉴权 |
| FunctionGraph（函数计算） | 业务逻辑（4 个函数） |
| GeminiDB Cassandra | 图书与用户数据存储 |
| VPC / 子网 / 安全组 | 网络隔离与访问控制 |

部署完成后请及时清理测试资源（见 [清理资源](#清理资源)）。

## 前置条件

- 华为云账号（区域 `cn-north-4`），且拥有创建 APIG、GeminiDB 等资源的权限
- Terraform >= 1.5，Node.js >= 18 + npm
- 本地可执行 `bash`（Windows 用户使用 Git Bash / WSL）

## 快速开始

```bash
# 1. 构建函数代码（生成 zip 包）
bash scripts/build-functions.sh

# 2. 配置凭证与变量
cd infra
cp terraform.tfvars.example terraform.tfvars   # 填入数据库密码（provider 凭据走环境变量）

# 3. 一键部署
terraform init && terraform apply

# 4. 初始化数据表与默认用户
export DDB_ENDPOINT="http://$(terraform output -raw geminidb_lb_ip):8000"
bash ../scripts/init-tables.sh

# 5. 冒烟验证
export API_ENDPOINT="$(terraform output -raw api_endpoint)"
bash ../scripts/smoke-test.sh
```

## 分步部署

### 步骤 1：构建函数代码

```bash
cd <本仓库根目录>
bash scripts/build-functions.sh
```

预期输出：`[+] 全部函数构建完成`，并在 `src/functions/<fn>/` 下生成 `<fn>.zip`。

### 步骤 2：配置变量

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

编辑 `terraform.tfvars`，填入：

| 变量 | 说明 |
|------|------|
| `access_key` / `secret_key` | 云凭证（也会注入函数，用于数据库访问签名） |
| `db_password` | GeminiDB 数据库密码（8-32 位，含大小写字母、数字、特殊字符） |
| `region` / `project_name` | 区域与资源命名前缀（默认 cn-north-4 / books-api） |

### 步骤 3：部署

```bash
terraform init
terraform plan    # 确认将创建的资源
terraform apply   # 输入 yes 开始部署
```

预期输出：`Apply complete!`，并显示 `api_endpoint` 等输出值。

### 步骤 4：初始化数据表

```bash
export DDB_ENDPOINT="http://<geminidb_lb_ip>:8000"   # 来自 terraform output
export AWS_ACCESS_KEY_ID="<AK>"
export AWS_SECRET_ACCESS_KEY="<SK>"
export ADMIN_PASSWORD="PLACEHOLDER-ADMIN-PASS"                  # 默认管理员初始密码
bash ../scripts/init-tables.sh
```

预期输出：`[+] 表已创建: books`、`[+] 表已创建: users`、`[+] 默认用户已写入: admin`。

### 步骤 5：冒烟验证

```bash
export API_ENDPOINT="<terraform output api_endpoint>"
bash ../scripts/smoke-test.sh
```

预期输出：4 项验证全部 `✓`，最后输出 `[+] 冒烟验证通过`。

## 使用方法

### 登录获取令牌

```bash
curl -X POST "$API_ENDPOINT/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<初始密码>"}'
```

响应示例：

```json
{ "token": "eyJhbGciOiJIUzI1NiIs...", "token_type": "Bearer", "expires_in": 3600 }
```

### 新增图书（需鉴权）

```bash
curl -X POST "$API_ENDPOINT/books" \
  -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' \
  -d '{"isbn":"978-3-16-148410-0","title":"Example Book","year":2026,"author":"Author","publisher":"Pub","rating":5,"pages":200}'
```

期望返回 `HTTP 201`。

### 查询图书（公开）

```bash
curl "$API_ENDPOINT/books"
```

期望返回 `HTTP 200` 与图书 JSON 数组。

> **验证提醒**：部署完成后，请按本节约步骤自行验证（登录 → 创建 → 查询 → 无令牌被拒），确认业务功能可用后，方可视为交付完成。

## 清理资源

```bash
cd infra
terraform destroy
```

> 提示：GeminiDB 实例释放较慢（约 30 分钟）。若释放时提示超时，等待释放完成后再次执行 `terraform destroy` 即可。

## 详细说明

### 鉴权流程

1. 客户端调用 `POST /auth/login`，`auth-login` 函数在 `users` 表校验用户名/密码（HMAC-SHA256 加盐），通过后签发 HS256 JWT（默认 1 小时有效）
2. 客户端携带 `Authorization: Bearer <token>` 调用受保护的 `POST /books`
3. APIG 自定义鉴权器校验令牌签名与有效期，通过后转发到业务函数，失败返回 401/403

### 函数清单

| 函数 | 入口 | 职责 | 环境变量 |
|------|------|------|----------|
| books-create | index.handler | 写入图书（PutItem） | TABLE / DDB_ENDPOINT / 云凭证 |
| books-get-all | index.handler | 查询图书（Scan） | TABLE / DDB_ENDPOINT / 云凭证 |
| auth-login | index.handler | 校验用户并签发 JWT | USERS_TABLE / JWT_SECRET / JWT_EXPIRES / DDB_ENDPOINT |
| apig-authorizer | index.handler | 校验 JWT（网关自定义鉴权） | JWT_SECRET / JWT_EXPIRES |

### 配置项

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `TABLE` | `books` | 图书表名 |
| `USERS_TABLE` | `users` | 用户表名 |
| `JWT_EXPIRES` | `3600` | JWT 有效期（秒） |
| `DDB_ENDPOINT` | - | GeminiDB 兼容端点（由 Terraform 注入） |

## 常见问题（FAQ）

**Q1：`terraform apply` 报 `APIC.9220 Insufficient account balance`？**
A：账号状态异常导致 APIG 专享版无法创建，请检查账号状态后重新 `terraform apply` 即可。

**Q2：登录接口超时/失败？**
A：依次检查：① `DDB_ENDPOINT` 是否为 GeminiDB 内网地址；② 安全组是否放行函数子网到 8000 端口；③ 函数是否已配置 VPC（`terraform apply` 后自动配置）。

**Q3：修改函数代码后如何更新？**
A：`bash scripts/build-functions.sh` 重新构建后 `cd infra && terraform apply` 即可，仅更新函数代码。

**Q4：如何修改默认管理员密码？**
A：`init-tables.sh` 的 `ADMIN_PASSWORD` 环境变量控制初始密码；登录后可调用接口自行扩展用户管理逻辑。

## 许可证

本项目采用 [MIT No Attribution](LICENSE) 许可证。

## 联系方式

- 维护团队：公有云持续运营部
- 问题反馈：请在本仓库提交 Issue
