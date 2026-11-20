# 架构说明

## 1. 系统概述

本项目是一个**无服务器图书管理 API**：对外提供图书的新增（写）与查询（读）能力，支持基于 JWT 的访问鉴权。

- `GET /books`：公开接口，返回全部图书列表
- `POST /books`：受保护接口，需携带有效的 JWT 访问令牌，用于新增图书
- `POST /auth/login`：登录接口，校验用户凭证后签发 JWT

## 2. 架构图

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

## 3. 组件说明

| 组件 | 说明 |
|------|------|
| **APIG（专享版）** | API 网关，承载路由、鉴权、流控。GET /books 公开；POST /books 绑定自定义鉴权器 |
| **FunctionGraph** | 无服务器函数运行时，承载全部业务逻辑（4 个函数） |
| **GeminiDB Cassandra** | 分布式 NoSQL 数据库，标准 Cassandra 协议（CQL），应用侧驱动仅需配置节点与凭据即可访问 |
| **IAM 委托** | 授予 FunctionGraph 访问 GeminiDB 的权限（项目级角色） |

## 4. 函数清单

| 函数 | 入口 | 职责 |
|------|------|------|
| books-create | index.handler | 解析请求体，将图书写入 books 表，返回 201 |
| books-get-all | index.handler | 扫描 books 表，返回全部图书（JSON 数组） |
| auth-login | index.handler | 校验用户名/密码（HMAC-SHA256 加盐），签发 JWT |
| apig-authorizer | index.handler | APIG 自定义鉴权器：校验 JWT 签名与有效期 |

## 5. 鉴权流程

1. 客户端调用 `POST /auth/login`（用户名 + 密码），`auth-login` 校验 users 表记录后签发 JWT（HS256，默认 1 小时有效）
2. 客户端携带 `Authorization: Bearer <token>` 调用 `POST /books`
3. APIG 先调用自定义鉴权器 `apig-authorizer` 校验 JWT；通过后放行到 `books-create`
4. 鉴权失败返回 401/403，不进入业务函数

## 6. 数据模型

### books 表

| 属性 | 类型 | 说明 |
|------|------|------|
| isbn | String（分区键） | 图书 ISBN |
| title | String | 书名 |
| year | Number | 出版年份 |
| author | String | 作者 |
| publisher | String | 出版社 |
| rating | Number | 评分 |
| pages | Number | 页数 |

### users 表

| 属性 | 类型 | 说明 |
|------|------|------|
| username | String（分区键） | 用户名 |
| password_hash | String | 密码哈希（HMAC-SHA256） |
| salt | String | 哈希盐值 |
| email | String | 邮箱 |

## 7. 网络与安全

- 全部资源部署在专属 VPC（10.0.0.0/16）内，函数经 VPC 内网访问 GeminiDB
- 安全组仅放行函数子网 → GeminiDB（CQL 端口 9042）
- 数据库密码、云凭据、JWT 密钥均通过变量/环境变量传递，不写入代码库
- JWT 密钥由 Terraform 随机生成（`random_password`），避免硬编码
