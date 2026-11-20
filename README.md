# Serverless Books Management API

![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue)

[中文版](./README.cn.md)
![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Compatible-green)
![Serverless](https://img.shields.io/badge/Serverless-Enabled-orange)

## Introduction

This project demonstrates how to build a **serverless books management API** on Huawei Cloud, providing book creation and query capabilities, with self-built JWT authentication protecting write operations.

**Core features:**

- `GET /books`: Public endpoint that returns the full list of books (ISBN, title, author, publisher, rating, pages, etc.)
- `POST /books`: Authenticated endpoint for creating a new book (requires a JWT access token)
- `POST /auth/login`: User login that validates credentials and issues a JWT (HS256, valid for 1 hour by default)
- Data is stored in GeminiDB Cassandra; the application accesses it via the standard SDK, only requiring an endpoint configuration

**Key value:**

1. **Fully serverless**: API gateway + function computing, no servers to manage, elastic scaling by invocation
2. **Zero data-access changes**: GeminiDB exposes the standard Cassandra data-access protocol (CQL), so application code uses a Cassandra driver
3. **Secure out of the box**: Self-built JWT authentication + custom authorizer + database password/keys injected via variables, no credentials hardcoded
4. **One-command deployment**: All infrastructure is managed by Terraform

**Use cases:**

- Teams that need to quickly build authenticated RESTful APIs
- Scenarios that want CRUD workloads on a serverless architecture with zero operations overhead
- Workloads that need a cloud-native wide-column NoSQL (Cassandra protocol)

## Table of Contents

- [Architecture](#architecture)
- [Highlights](#highlights)
- [Cloud Services](#cloud-services)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Usage](#usage)
- [Clean Up](#clean-up)
- [Detailed Description](#detailed-description)
- [FAQ](#faq)
- [License](#license)
- [Contact](#contact)

## Architecture

```
                        ┌────────────────────────────────────────────┐
                        │               APIG (Dedicated)             │
                        │                                            │
  HTTPS                 │  GET /books ──► books-get-all (FunctionGraph)
  ────────────────►     │  POST /books ─► Custom Authorizer ─► books-create
   Client               │      ▲            (JWT validation)          │
                        │  POST /auth/login ─► auth-login            │
                        └────────────┬───────────────────────────────┘
                                     │ FunctionGraph (VPC private)
                                     ▼
                        ┌─────────────────────────────┐
                        │  GeminiDB Cassandra
                        │  · books table (isbn key)   │
                        │  · users table (username key)
                        └─────────────────────────────┘
```

## Highlights

- **Self-built JWT authentication chain**: a login function issues tokens, and a custom authorizer validates them at the gateway layer — business functions stay unaware
- **Private data access**: functions reach the database over the VPC private network; data never leaves the private network
- **Automatic table initialization**: one-command script creates tables and seeds a default user
- **Post-deploy smoke test**: a built-in script verifies the full path — login, create, query, and unauthorized rejection

## Cloud Services

| Service | Purpose |
|---------|---------|
| APIG (API Gateway, dedicated) | Exposes the REST API and hosts the custom authorizer |
| FunctionGraph (function computing) | Business logic (4 functions) |
| GeminiDB Cassandra | Book and user data storage |
| VPC / Subnet / Security Group | Network isolation and access control |

Please clean up test resources after deployment (see [Clean Up](#clean-up)).

## Prerequisites

- A Huawei Cloud account (region `cn-north-4`) with permission to create APIG, GeminiDB and related resources
- Terraform >= 1.5, Node.js >= 18 + npm
- A local `bash` shell (Git Bash / WSL on Windows)

## Quick Start

```bash
# 1. Build the function code (generates zip packages)
bash scripts/build-functions.sh

# 2. Configure credentials and variables
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill in the DB password (provider credentials via env vars)

# 3. One-command deployment
terraform init && terraform apply

# 4. Initialize tables and default user
export DDB_ENDPOINT="http://$(terraform output -raw geminidb_lb_ip):8000"
bash ../scripts/init-tables.sh

# 5. Smoke test
export API_ENDPOINT="$(terraform output -raw api_endpoint)"
bash ../scripts/smoke-test.sh
```

## Step-by-Step Deployment

### Step 1: Build the function code

```bash
cd <repo root>
bash scripts/build-functions.sh
```

Expected output: `[+] 全部函数构建完成`, and `<fn>.zip` generated under `src/functions/<fn>/`.

### Step 2: Configure variables

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | Description |
|----------|-------------|
| `access_key` / `secret_key` | Cloud credentials (also injected into functions for DB access signing) |
| `db_password` | GeminiDB database password (8-32 chars, upper/lowercase + digits + special chars) |
| `region` / `project_name` | Region and resource name prefix (defaults: cn-north-4 / books-api) |

### Step 3: Deploy

```bash
terraform init
terraform plan    # review the resources to be created
terraform apply   # type yes to deploy
```

Expected output: `Apply complete!` along with outputs such as `api_endpoint`.

### Step 4: Initialize tables

```bash
export DDB_ENDPOINT="http://<geminidb_lb_ip>:8000"   # from terraform output
export AWS_ACCESS_KEY_ID="<AK>"
export AWS_SECRET_ACCESS_KEY="<SK>"
export ADMIN_PASSWORD="PLACEHOLDER-ADMIN-PASS"                  # default admin initial password
bash ../scripts/init-tables.sh
```

Expected output: `[+] 表已创建: books`, `[+] 表已创建: users`, `[+] 默认用户已写入: admin`.

### Step 5: Smoke test

```bash
export API_ENDPOINT="<terraform output api_endpoint>"
bash ../scripts/smoke-test.sh
```

Expected output: all 4 checks pass with `✓`, ending with `[+] 冒烟验证通过`.

## Usage

### Login to obtain a token

```bash
curl -X POST "$API_ENDPOINT/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<initial password>"}'
```

Response example:

```json
{ "token": "eyJhbGciOiJIUzI1NiIs...", "token_type": "Bearer", "expires_in": 3600 }
```

### Create a book (authenticated)

```bash
curl -X POST "$API_ENDPOINT/books" \
  -H "Authorization: Bearer <token>" \
  -H 'Content-Type: application/json' \
  -d '{"isbn":"978-3-16-148410-0","title":"Example Book","year":2026,"author":"Author","publisher":"Pub","rating":5,"pages":200}'
```

Expected: `HTTP 201`.

### Query books (public)

```bash
curl "$API_ENDPOINT/books"
```

Expected: `HTTP 200` with a JSON array of books.

> **Verification note**: after deployment, please follow the steps in this section to verify (login → create → query → unauthorized rejection). Only when the business functions are confirmed working is the delivery considered complete.

## Clean Up

```bash
cd infra
terraform destroy
```

> Note: GeminiDB instances take about 30 minutes to release. If the destroy times out, wait for the release to finish and run `terraform destroy` again.

## Detailed Description

### Authentication flow

1. The client calls `POST /auth/login`; the `auth-login` function validates the username/password (HMAC-SHA256 with salt) against the `users` table and issues an HS256 JWT (valid for 1 hour by default)
2. The client sends `Authorization: Bearer <token>` when calling the protected `POST /books`
3. The APIG custom authorizer validates the token signature and expiry; on success the request is forwarded to the business function, otherwise 401/403 is returned

### Function list

| Function | Handler | Responsibility | Environment variables |
|----------|---------|----------------|----------------------|
| books-create | index.handler | Write a book (PutItem) | TABLE / DDB_ENDPOINT / cloud credentials |
| books-get-all | index.handler | Query books (Scan) | TABLE / DDB_ENDPOINT / cloud credentials |
| auth-login | index.handler | Validate user and issue JWT | USERS_TABLE / JWT_SECRET / JWT_EXPIRES / DDB_ENDPOINT |
| apig-authorizer | index.handler | Validate JWT (gateway custom authorizer) | JWT_SECRET / JWT_EXPIRES |

### Configuration

| Environment variable | Default | Description |
|----------------------|---------|-------------|
| `TABLE` | `books` | Books table name |
| `USERS_TABLE` | `users` | Users table name |
| `JWT_EXPIRES` | `3600` | JWT validity (seconds) |
| `DDB_ENDPOINT` | - | GeminiDB compatible endpoint (injected by Terraform) |

## FAQ

**Q1: `terraform apply` fails with `APIC.9220 Insufficient account balance`?**
A: The account status is abnormal, preventing the APIG dedicated instance from being created. Check the account status and re-run `terraform apply`.

**Q2: The login endpoint times out or fails?**
A: Check: ① whether `DDB_ENDPOINT` is the GeminiDB private address; ② whether the security group allows the function subnet to reach port 8000; ③ whether the function is configured with the VPC (done automatically by `terraform apply`).

**Q3: How to update function code after changes?**
A: Run `bash scripts/build-functions.sh` and then `cd infra && terraform apply` — only the functions are updated.

**Q4: How to change the default admin password?**
A: The `ADMIN_PASSWORD` environment variable of `init-tables.sh` controls the initial password; user management can be extended after login.

## License

This project is licensed under [MIT No Attribution](LICENSE).

## Contact

- Maintainer: Public Cloud Continuous Operations Department
- Feedback: please open an Issue in this repository
