output "issuer_url" {
  description = "OAuth issuer (no trailing slash). Set every repo's OAUTH_ISSUER GitHub variable to this; the authorizer derives <issuer>/token/introspection."
  value       = trimsuffix(aws_lambda_function_url.authstub.function_url, "/")
}

output "token_endpoint" {
  description = "Token mint endpoint for the BFF's OPDA_TOKEN_ENDPOINT variable and Bruno stub-auth environments."
  value       = "${trimsuffix(aws_lambda_function_url.authstub.function_url, "/")}/token"
}
