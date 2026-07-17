# Sandbox auth stub (ADR-0012) — replaces the Raidiam directory for token mint +
# RFC 7662 introspection. One Lambda behind a public Function URL; the URL is the
# OAuth issuer every API repo's OAUTH_ISSUER GitHub variable points at.
# No VPC: authorizer Lambdas egress via NAT and reach it over public HTTPS.
# A Function URL never requests client certificates, so the per-API authorizer's
# mTLS introspection client works unchanged (it only presents a cert when asked).

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

resource "aws_lambda_function_url" "authstub" {
  function_name      = aws_lambda_function.authstub.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "function_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.authstub.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
