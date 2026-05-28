resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda"
  description = "App Lambda - HTTPS egress to VPC endpoints via NAT"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to VPC endpoints (SSM) and external services via NAT"
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_lambda_function" "app" {
  function_name = local.name_prefix
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"

  timeout     = 30
  memory_size = 256

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  dynamic "environment" {
    for_each = var.provenance_signing_kid != "" ? [1] : []
    content {
      variables = {
        PROVENANCE_SIGNING_KID      = var.provenance_signing_kid
        PROVENANCE_SIGNING_KEY_PATH = var.provenance_signing_key_path != "" ? var.provenance_signing_key_path : aws_ssm_parameter.dataprov_key.name
      }
    }
  }

  depends_on = [aws_cloudwatch_log_group.app]

  tags = local.tags
}
