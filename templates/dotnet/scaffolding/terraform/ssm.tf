resource "aws_ssm_parameter" "signing_key" {
  name  = "/${local.name_prefix}/signing_key"
  type  = "SecureString"
  value = var.signing_key

  overwrite = true
  tags = local.tags
}

resource "aws_ssm_parameter" "dataprov_key" {
  name  = "/${local.name_prefix}/dataprov_key"
  type  = "SecureString"
  value = var.dataprov_key

  overwrite = true
  tags = local.tags
}

# ── Shared proxy certs (moved from mtls-proxy module) ─────────────────────────

resource "aws_ssm_parameter" "transport_certificate" {
  name  = "/${local.name_prefix}/transport_certificate"
  type  = "String"
  value = var.transport_certificate
  overwrite = true
  tags  = local.tags
}

resource "aws_ssm_parameter" "transport_key" {
  name  = "/${local.name_prefix}/transport_key"
  type  = "SecureString"
  value = var.transport_key
  overwrite = true
  tags  = local.tags
}

resource "aws_ssm_parameter" "ca_trusted_list" {
  name  = "/${local.name_prefix}/ca_trusted_list"
  type  = "String"
  value = var.ca_trusted_list
  tier  = "Intelligent-Tiering"
  overwrite = true
  tags  = local.tags
}

# ── Shared proxy route registration ───────────────────────────────────────────

resource "aws_ssm_parameter" "proxy_route" {
  name  = "/opda/proxy/routes/${local.name_prefix}"
  type  = "String"
  value = jsonencode({
    prefix = var.proxy_path_prefix
    url    = module.api_gateway.invoke_url
  })
  overwrite = true
  tags  = local.tags
}
