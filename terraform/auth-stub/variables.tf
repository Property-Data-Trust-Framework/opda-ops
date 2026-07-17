variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "authstub_image_tag" {
  type        = string
  description = "Image tag in the shared ECR repo (authstub-<sha> from opda-shared-services publish.yml)"
}

variable "token_ttl_seconds" {
  type        = number
  description = "Lifetime of minted tokens. Generous by design — sandbox demo ergonomics, not production security."
  default     = 3600
}

variable "hmac_key" {
  type        = string
  description = "HMAC-SHA256 signing key for stub tokens. Generate with e.g. `openssl rand -base64 48`."
  sensitive   = true
}

variable "clients_json" {
  type        = string
  description = <<-EOT
    Client registry as a JSON object: {"<client_id>": {"scopes": ["land-registry", ...]}}.
    client_assertion signatures are NOT validated (sandbox-grade) — registration
    constrains client_id + scopes only.
  EOT
}

variable "public_domain" {
  type        = string
  description = "Public hostname of the shared mTLS proxy the /auth route hangs off."
  default     = "dev.api.smartpropdata.org.uk"
}
