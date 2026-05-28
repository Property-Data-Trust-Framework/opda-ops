output "vpc_id_ssm_path" {
  value = aws_ssm_parameter.vpc_id.name
}

output "public_subnet_ids_ssm_path" {
  value = aws_ssm_parameter.public_subnet_ids.name
}

output "private_subnet_ids_ssm_path" {
  value = aws_ssm_parameter.private_subnet_ids.name
}

output "vpc_endpoints_security_group_id_ssm_path" {
  value = aws_ssm_parameter.vpc_endpoints_security_group_id.name
}

output "execute_api_vpc_endpoint_id_ssm_path" {
  value = aws_ssm_parameter.execute_api_vpc_endpoint_id.name
}
