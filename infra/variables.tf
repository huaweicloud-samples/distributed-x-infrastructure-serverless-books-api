variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名称（资源命名前缀）"
  type        = string
  default     = "books-api"
}

variable "db_password" {
  description = "GeminiDB 数据库密码（8-32位，含大小写字母、数字、特殊字符）"
  type        = string
  sensitive   = true
}
