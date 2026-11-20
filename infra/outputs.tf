output "api_endpoint" {
  description = "APIG API 调用地址"
  value       = "https://${huaweicloud_apig_instance.main.ingress_address}/release-v1"
}

output "geminidb_lb_ip" {
  description = "GeminiDB Cassandra 内网负载均衡地址（函数经 VPC 内网 CQL 9042 访问）"
  value       = huaweicloud_geminidb_instance.main.lb_ip_address
}

output "function_create_urn" {
  description = "books-create 函数 URN"
  value       = huaweicloud_fgs_function.create.urn
}

output "function_get_all_urn" {
  description = "books-get-all 函数 URN"
  value       = huaweicloud_fgs_function.get_all.urn
}

output "function_auth_urn" {
  description = "auth-login 函数 URN"
  value       = huaweicloud_fgs_function.auth.urn
}

output "authorizer_urn" {
  description = "APIG 自定义鉴权器函数 URN"
  value       = huaweicloud_fgs_function.authorizer.urn
}
