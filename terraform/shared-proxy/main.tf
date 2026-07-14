locals {
  name = "opda-shared-proxy-${var.environment}"

  tags = {
    Project     = "opda-shared-proxy"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── Shared VPC (read from SSM) ───────────────────────────────────────────────

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

# ─── Shared proxy ─────────────────────────────────────────────────────────────

module "shared_proxy" {
  source = "git::https://github.com/OpenPropertyDataAssociation/opda-shared-infra.git//modules/shared-proxy?ref=main"

  name                            = local.name
  vpc_id                          = data.aws_ssm_parameter.vpc_id.value
  public_subnet_ids               = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
  private_subnet_ids              = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  vpc_endpoints_security_group_id = data.aws_ssm_parameter.vpc_endpoints_security_group_id.value
  image_uri                       = "${var.shared_services_ecr_base}:mtls-${var.mtls_proxy_image_tag}"
  routes_ssm_path                 = "/opda/proxy/routes/"
  ca_trusted_list                 = var.ca_trusted_list
  server_tls_certificate          = var.server_tls_certificate
  server_tls_key                  = var.server_tls_key
  external_hostname               = var.environment
  external_domain_name            = "api.smartpropdata.org.uk"
  external_hosted_zone_id         = var.external_hosted_zone_id
  tags                            = local.tags
}
