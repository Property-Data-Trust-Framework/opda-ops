locals {
  tags = {
    Project   = "opda"
    ManagedBy = "terraform"
  }
}

module "vpc" {
  source = "git::https://github.com/OpenPropertyDataAssociation/opda-shared-infra.git//modules/vpc?ref=main"

  name                 = "opda-shared"
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.tags
}

# ── SSM outputs ───────────────────────────────────────────────────────────────
# All API repos read these at plan time via data "aws_ssm_parameter".
# Subnet IDs are stored as StringList; consumers split(",", value) to get a list.

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/opda/shared/vpc_id"
  type  = "String"
  value = module.vpc.vpc_id
  tags  = local.tags
}

resource "aws_ssm_parameter" "public_subnet_ids" {
  name  = "/opda/shared/public_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.public_subnet_ids)
  tags  = local.tags
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "/opda/shared/private_subnet_ids"
  type  = "StringList"
  value = join(",", module.vpc.private_subnet_ids)
  tags  = local.tags
}

resource "aws_ssm_parameter" "vpc_endpoints_security_group_id" {
  name  = "/opda/shared/vpc_endpoints_security_group_id"
  type  = "String"
  value = module.vpc.vpc_endpoints_security_group_id
  tags  = local.tags
}

resource "aws_ssm_parameter" "execute_api_vpc_endpoint_id" {
  name  = "/opda/shared/execute_api_vpc_endpoint_id"
  type  = "String"
  value = module.vpc.execute_api_vpc_endpoint_id
  tags  = local.tags
}
