module "authorizer" {
  source = "git::https://github.com/Property-Data-Trust-Framework/opda-shared-infra.git//modules/authorizer?ref=main"

  name                            = local.name_prefix
  vpc_id                          = local.vpc_id
  private_subnet_ids              = local.private_subnet_ids
  vpc_endpoints_security_group_id = local.vpc_endpoints_security_group_id
  image_uri                       = "${var.shared_services_ecr_base}:authorizer-${var.authorizer_image_tag}"
  alb_authentication_issuer       = var.oauth_issuer
  client_id                       = var.oauth_client_id
  ssm_transport_certificate_name  = aws_ssm_parameter.transport_certificate.name
  ssm_transport_key_name          = aws_ssm_parameter.transport_key.name
  ssm_ca_trusted_list_name        = aws_ssm_parameter.ca_trusted_list.name
  ssm_transport_certificate_arn   = aws_ssm_parameter.transport_certificate.arn
  ssm_transport_key_arn           = aws_ssm_parameter.transport_key.arn
  ssm_ca_trusted_list_arn         = aws_ssm_parameter.ca_trusted_list.arn
  ssm_signing_key_name            = aws_ssm_parameter.signing_key.name
  ssm_signing_key_arn             = aws_ssm_parameter.signing_key.arn

  # Scoped broadly to avoid a circular dependency with the api_gateway module.
  api_execution_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"

  bypass_auth = var.bypass_auth || var.disconnected_mode

  # Matches Raidiam production; module default is -1 (unreserved).
  reserved_concurrent_executions = 12

  tags = local.tags
}
