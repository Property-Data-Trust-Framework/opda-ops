# Sandbox auth stub (ADR-0012) — replaces the Raidiam directory for token mint +
# RFC 7662 introspection. Exposed as a PRIVATE API Gateway routed through the
# shared mTLS proxy under the /auth prefix (public Lambda Function URLs on this
# account need an extra lambda:InvokeFunction grant that aws_lambda_permission
# cannot express — console-only, lost on recreate; see Key-Learnings). The issuer is
# therefore https://<public domain>/auth for every consumer: Bruno, the BFF, and
# the per-API authorizers (which reach it via NAT exactly like they reached
# Raidiam). The proxy exempts /auth/ from its bearer-presence check (these
# endpoints are where tokens come from) and never requests client certificates
# it can't get — mTLS remains optional at the proxy as for every other route.

locals {
  name = "opda-auth-stub"
  tags = {
    Project   = "opda"
    ManagedBy = "terraform"
  }
}

data "aws_caller_identity" "current" {}

# ── Secrets / registry ────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "hmac_key" {
  name      = "/opda/auth-stub/hmac_key"
  type      = "SecureString"
  value     = var.hmac_key
  overwrite = true
  tags      = local.tags
}

resource "aws_ssm_parameter" "clients" {
  name      = "/opda/auth-stub/clients"
  type      = "String"
  value     = var.clients_json
  overwrite = true
  tags      = local.tags
}

# ── Lambda ────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "authstub" {
  name = "${local.name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "authstub" {
  name = "authstub"
  role = aws_iam_role.authstub.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SsmRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [aws_ssm_parameter.hmac_key.arn, aws_ssm_parameter.clients.arn]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid      = "KmsDecryptViaSsm"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringEquals = { "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com" }
        }
      },
    ]
  })
}

resource "aws_lambda_function" "authstub" {
  function_name = local.name
  role          = aws_iam_role.authstub.arn
  package_type  = "Image"
  image_uri     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/opda-shared-services:${var.authstub_image_tag}"
  timeout       = 10
  memory_size   = 128
  architectures = ["x86_64"]

  environment {
    variables = {
      SSM_CLIENTS_PARAM  = aws_ssm_parameter.clients.name
      SSM_HMAC_KEY_PARAM = aws_ssm_parameter.hmac_key.name
      TOKEN_TTL_SECONDS  = tostring(var.token_ttl_seconds)
    }
  }

  tags = local.tags
}

# ── Private API Gateway + shared-proxy route ─────────────────────────────────

data "aws_ssm_parameter" "execute_api_vpc_endpoint_id" {
  name = "/opda/shared/execute_api_vpc_endpoint_id"
}

module "api_gateway" {
  source = "git::https://github.com/Property-Data-Trust-Framework/opda-shared-infra.git//modules/api-gateway?ref=main"

  name = local.name

  openapi_body = templatefile("${path.module}/openapi/api.yml", {
    service_invoke_arn = aws_lambda_function.authstub.invoke_arn
  })

  execute_api_vpc_endpoint_id = data.aws_ssm_parameter.execute_api_vpc_endpoint_id.value
  tags                        = local.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authstub.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway.execution_arn}/*/*"
}

# Register /auth in the shared proxy's routing table. The proxy loads routes at
# start-up — force-cycle the shared ECS tasks after first apply (see README).
resource "aws_ssm_parameter" "proxy_route" {
  name = "/opda/proxy/routes/${local.name}"
  type = "String"
  value = jsonencode({
    prefix = "/auth"
    url    = module.api_gateway.invoke_url
  })
  overwrite = true
  tags      = local.tags
}
