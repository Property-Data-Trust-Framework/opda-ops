module "api_gateway" {
  source = "git::https://github.com/OpenPropertyDataAssociation/opda-shared-infra.git//modules/api-gateway?ref=main"

  name = local.name_prefix

  openapi_body = templatefile("${path.module}/../openapi/api.yml", {
    service_invoke_arn    = aws_lambda_function.app.invoke_arn
    authorizer_invoke_arn = coalesce(module.authorizer.function_invoke_arn, "arn:aws:lambda:placeholder")
  })

  execute_api_vpc_endpoint_id = local.execute_api_vpc_endpoint_id
  tags                        = local.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway.execution_arn}/*/*"
}
