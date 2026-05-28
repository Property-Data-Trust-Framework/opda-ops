# Shared VPC — provisioned once in opda-ops/terraform/shared-vpc and
# published to SSM. All API repos read these values at plan time.

data "aws_ssm_parameter" "vpc_id" {
  name = "/opda/shared/vpc_id"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/opda/shared/public_subnet_ids"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/opda/shared/private_subnet_ids"
}

data "aws_ssm_parameter" "vpc_endpoints_security_group_id" {
  name = "/opda/shared/vpc_endpoints_security_group_id"
}

data "aws_ssm_parameter" "execute_api_vpc_endpoint_id" {
  name = "/opda/shared/execute_api_vpc_endpoint_id"
}

locals {
  vpc_id                          = data.aws_ssm_parameter.vpc_id.value
  public_subnet_ids               = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
  private_subnet_ids              = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  vpc_endpoints_security_group_id = data.aws_ssm_parameter.vpc_endpoints_security_group_id.value
  execute_api_vpc_endpoint_id     = data.aws_ssm_parameter.execute_api_vpc_endpoint_id.value
}
