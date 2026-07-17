output "issuer_url" {
  description = "OAuth issuer (no trailing slash). Set every repo's OAUTH_ISSUER GitHub variable to this; the authorizer derives <issuer>/token/introspection."
  value       = "https://${var.public_domain}/auth"
}

output "token_endpoint" {
  description = "Token mint endpoint for the BFF's OPDA_TOKEN_ENDPOINT variable and Bruno stub-auth environments."
  value       = "https://${var.public_domain}/auth/token"
}

output "private_invoke_url" {
  description = "The private API Gateway invoke URL registered in the shared proxy's routing table (debug reference; not directly reachable from outside the VPC)."
  value       = module.api_gateway.invoke_url
}
