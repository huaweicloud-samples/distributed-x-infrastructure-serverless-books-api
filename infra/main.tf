# ============================================================================
# 华为云 无服务器图书 API（Books API）
#
# 架构：APIG（专享版）→ FunctionGraph（Node.js）→ GeminiDB（Cassandra，CQL 9042）
#       自建 JWT 鉴权：auth 函数签发 token，authorizer 函数作为 APIG
#       自定义鉴权器校验 token。
#
# 关键配置说明（真机验证结论，cn-north-4）：
#   · FunctionGraph：app="default"；runtime="Node.js18.15"（带小版本）；
#     code_type="inline" 且 func_code 必须 base64（zip 用 filebase64() 直接读取）；
#     函数挂 VPC 用顶层 vpc_id + network_id（子网），无 subnet_id 参数；
#     Node.js handler 签名必须 (event, context)。
#   · IAM 委托：delegated_service_name 必须是 "op_svc_cff"（FunctionGraph
#     云服务主体），GeminiDB 为项目级服务 → 用 project_role 授权。
#   · GeminiDB Cassandra：datastore { type="cassandra", version="3.11",
#     storage_engine="rocksDB" }；CQL 端口 9042，账户 root + 实例密码。
#   · APIG 专享版：必填 vpc_id/subnet_id/security_group_id/available_zones，
#     bandwidth_size >= 5（下限约束）；
#     API 鉴权字段为 security_authentication（NONE / AUTHORIZER 等），
#     绑定自定义鉴权器时用 AUTHORIZER + authorizer_id。
#
# 凭证：terraform provider 凭据经环境变量传入，不写入任何文件。
# 注意：apply 前先运行 scripts/build-functions.sh 构建函数 zip 包。
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.96.0"
    }
  }

  backend "local" {}
}

provider "huaweicloud" {
  region = var.region
}

# ---------------------------------------------------------------------------
# 可用区
# ---------------------------------------------------------------------------
data "huaweicloud_availability_zones" "main" {}

# ---------------------------------------------------------------------------
# VPC 网络
# ---------------------------------------------------------------------------
resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.0.0/24"
  gateway_ip = "10.0.0.1"
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for books api"
}

# 放行函数子网 → GeminiDB Cassandra（CQL 端口 9042）
resource "huaweicloud_networking_secgroup_rule" "geminidb_from_fgs" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8000
  port_range_max    = 8000
  remote_ip_prefix  = "10.0.0.0/24"
  security_group_id = huaweicloud_networking_secgroup.main.id
}

# ---------------------------------------------------------------------------
# IAM 委托（FunctionGraph 云服务委托）
# 服务名必须是 op_svc_cff；GeminiDB 是项目级服务 → project_role
# ---------------------------------------------------------------------------
resource "huaweicloud_identity_agency" "functiongraph" {
  name                   = "${var.project_name}-fgs-agency"
  description            = "Agency for FunctionGraph (cloud service delegation)"
  duration               = "FOREVER"
  delegated_service_name = "op_svc_cff"

  project_role {
    project = var.region
    roles = [
      "GeminiDB FullAccess",
    ]
  }
}

# ---------------------------------------------------------------------------
# JWT 密钥（auth / authorizer 共享）
# ---------------------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

# ---------------------------------------------------------------------------
# FunctionGraph 函数（Node.js 18.15，inline + base64 zip）
# 函数访问 GeminiDB Cassandra 通过 VPC 内网（lb_ip_address:9042），
# 连接凭据（实例密码）经环境变量传递，不落盘。
# ---------------------------------------------------------------------------
locals {
  fgs_common = {
    agency      = huaweicloud_identity_agency.functiongraph.name
    app         = "default"
    memory_size = 256
    timeout     = 20
    vpc_id      = huaweicloud_vpc.main.id
    network_id  = huaweicloud_vpc_subnet.main.id
    cql_hosts   = huaweicloud_geminidb_instance.main.lb_ip_address
    cql_port    = "9042"
    region      = var.region
  }
}

resource "huaweicloud_fgs_function" "create" {
  name        = "${var.project_name}-books-create"
  app         = local.fgs_common.app
  agency      = local.fgs_common.agency
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = "Node.js18.15"
  vpc_id      = local.fgs_common.vpc_id
  network_id  = local.fgs_common.network_id

  code_type = "inline"
  func_code = filebase64("${path.module}/../src/functions/create/create.zip")

  user_data = jsonencode({
    CASSANDRA_HOSTS    = local.fgs_common.cql_hosts
    CASSANDRA_PORT     = local.fgs_common.cql_port
    CASSANDRA_KEYSPACE = "booksdemo"
    CASSANDRA_USERNAME = "root"
    CASSANDRA_PASSWORD = var.db_password
  })
}

resource "huaweicloud_fgs_function" "get_all" {
  name        = "${var.project_name}-books-get-all"
  app         = local.fgs_common.app
  agency      = local.fgs_common.agency
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = "Node.js18.15"
  vpc_id      = local.fgs_common.vpc_id
  network_id  = local.fgs_common.network_id

  code_type = "inline"
  func_code = filebase64("${path.module}/../src/functions/get-all/get-all.zip")

  user_data = jsonencode({
    CASSANDRA_HOSTS    = local.fgs_common.cql_hosts
    CASSANDRA_PORT     = local.fgs_common.cql_port
    CASSANDRA_KEYSPACE = "booksdemo"
    CASSANDRA_USERNAME = "root"
    CASSANDRA_PASSWORD = var.db_password
  })
}

resource "huaweicloud_fgs_function" "auth" {
  name        = "${var.project_name}-auth-login"
  app         = local.fgs_common.app
  agency      = local.fgs_common.agency
  handler     = "index.handler"
  memory_size = local.fgs_common.memory_size
  timeout     = local.fgs_common.timeout
  runtime     = "Node.js18.15"
  vpc_id      = local.fgs_common.vpc_id
  network_id  = local.fgs_common.network_id

  code_type = "inline"
  func_code = filebase64("${path.module}/../src/functions/auth/auth.zip")

  user_data = jsonencode({
    CASSANDRA_HOSTS    = local.fgs_common.cql_hosts
    CASSANDRA_PORT     = local.fgs_common.cql_port
    CASSANDRA_KEYSPACE = "booksdemo"
    CASSANDRA_USERNAME = "root"
    CASSANDRA_PASSWORD = var.db_password
    JWT_SECRET         = random_password.jwt_secret.result
    JWT_EXPIRES        = "3600"
  })
}

resource "huaweicloud_fgs_function" "authorizer" {
  name        = "${var.project_name}-apig-authorizer"
  app         = local.fgs_common.app
  agency      = local.fgs_common.agency
  handler     = "index.handler"
  memory_size = 128
  timeout     = 20
  runtime     = "Node.js18.15"
  vpc_id      = local.fgs_common.vpc_id
  network_id  = local.fgs_common.network_id

  code_type = "inline"
  func_code = filebase64("${path.module}/../src/functions/authorizer/authorizer.zip")

  user_data = jsonencode({
    JWT_SECRET  = random_password.jwt_secret.result
    JWT_EXPIRES = "3600"
  })
}

# ---------------------------------------------------------------------------
# APIG 专享版实例（BASIC，bandwidth_size >= 5）
# ---------------------------------------------------------------------------
resource "huaweicloud_apig_instance" "main" {
  name              = "${var.project_name}-apig"
  edition           = "BASIC"
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.main.id
  security_group_id = huaweicloud_networking_secgroup.main.id
  maintain_begin    = "06:00:00"
  bandwidth_size    = 5
  available_zones = [
    data.huaweicloud_availability_zones.main.names[0],
    data.huaweicloud_availability_zones.main.names[1],
  ]

  tags = {
    project = var.project_name
  }
}

resource "huaweicloud_apig_group" "main" {
  name        = "${var.project_name}-api-group"
  instance_id = huaweicloud_apig_instance.main.id
}

resource "huaweicloud_apig_environment" "main" {
  # 注意：实例默认自带 "release" 环境（APIG.3205 同名冲突），
  # 自建环境须用唯一名，API 发布后访问路径为 https://<域名>/release-v1/<path>
  name        = "release-v1"
  instance_id = huaweicloud_apig_instance.main.id
}

# APIG 自定义鉴权器（校验 JWT）
resource "huaweicloud_apig_custom_authorizer" "main" {
  instance_id  = huaweicloud_apig_instance.main.id
  name         = "${var.project_name}-jwt-authorizer"
  type         = "FRONTEND"
  function_urn = huaweicloud_fgs_function.authorizer.urn
  identity {
    name     = "Authorization"
    location = "HEADER"
  }
}

# GET /books —— 公开
resource "huaweicloud_apig_api" "get_all" {
  name                    = "get-all-books"
  group_id                = huaweicloud_apig_group.main.id
  instance_id             = huaweicloud_apig_instance.main.id
  type                    = "FunctionGraph"
  request_method          = "GET"
  request_path            = "/books"
  request_protocol        = "HTTPS"
  security_authentication = "NONE"

  func_graph {
    function_urn = huaweicloud_fgs_function.get_all.urn
  }
}

# POST /books —— 需 JWT 鉴权
resource "huaweicloud_apig_api" "create" {
  name                    = "create-book"
  group_id                = huaweicloud_apig_group.main.id
  instance_id             = huaweicloud_apig_instance.main.id
  type                    = "FunctionGraph"
  request_method          = "POST"
  request_path            = "/books"
  request_protocol        = "HTTPS"
  security_authentication = "AUTHORIZER"
  authorizer_id           = huaweicloud_apig_custom_authorizer.main.id

  func_graph {
    function_urn = huaweicloud_fgs_function.create.urn
  }
}

# API 发布到环境（apig_api 创建后不会自动发布，须用 publishment 显式发布，
# 否则 https://<域名>/<环境>/<路径> 无法访问）
resource "huaweicloud_apig_api_publishment" "get_all" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.get_all.id
  env_id      = huaweicloud_apig_environment.main.id
}

resource "huaweicloud_apig_api_publishment" "create" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.create.id
  env_id      = huaweicloud_apig_environment.main.id
}

# ---------------------------------------------------------------------------
# GeminiDB Cassandra 实例（CQL 端口 9042）
# ---------------------------------------------------------------------------
resource "huaweicloud_geminidb_instance" "main" {
  name = "${var.project_name}-geminidb-cql"
  mode = "Cluster"
  flavor {
    num       = 3
    size      = 100
    storage   = "ULTRAHIGH"
    spec_code = "geminidb.cassandra.large.4"
  }
  datastore {
    type           = "cassandra"
    version        = "3.11"
    storage_engine = "rocksDB"
  }
  availability_zone = data.huaweicloud_availability_zones.main.names[0]
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.main.id
  security_group_id = huaweicloud_networking_secgroup.main.id
  password          = var.db_password

  tags = {
    project = var.project_name
  }
}
