# ── Core ─────────────────────────────────────────────────────────────────────

variable "name" {
  type        = string
  description = "Resource name prefix — injected from the GitHub repo name by the pipeline"
}

variable "environment" {
  type        = string
  description = "Deployment environment name (e.g. dev, staging, prod)"
}

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in owner/repo format"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

# ── OAuth2 / Authorizer ──────────────────────────────────────────────────────

variable "oauth_issuer" {
  type        = string
  description = "OAuth2 issuer URL (no trailing slash)"
  default     = ""
}

variable "oauth_client_id" {
  type        = string
  description = "OAuth2 client ID registered with the authorisation server"
  default     = ""
}

variable "bypass_auth" {
  type        = bool
  description = "When true the authorizer skips token introspection. Dev/smoke-test only."
  default     = false
}

variable "signing_key" {
  type        = string
  description = "PEM RS256 private key for private_key_jwt assertions to the authorisation server"
  sensitive   = true
  default     = ""
}

# ── Provenance signing ───────────────────────────────────────────────────────

variable "provenance_signing_kid" {
  type        = string
  description = "KID Raidiam issued for the provenance signing cert. Empty disables signing."
  default     = ""
}

variable "dataprov_key" {
  type        = string
  description = "PEM RSA private key for response provenance signing. Distinct from signing_key (which is the rtssigning key used for private_key_jwt AuthN)."
  sensitive   = true
  default     = ""
}

variable "provenance_signing_key_path" {
  type        = string
  description = "Override-only: SSM parameter name to read the provenance signing key from. Defaults to the dataprov_key resource when empty."
  default     = ""
}

# ── Transport TLS (mTLS proxy) ───────────────────────────────────────────────

variable "transport_certificate" {
  type      = string
  sensitive = true
  default   = ""
}

variable "transport_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "ca_trusted_list" {
  type        = string
  description = "PEM bundle of CAs trusted for mTLS client cert verification"
  sensitive   = true
  default     = ""
}

# ── Shared services images ───────────────────────────────────────────────────

variable "authorizer_image_tag" {
  type        = string
  description = "Image tag for the authorizer Lambda"
  default     = ""
}

variable "shared_services_ecr_base" {
  type        = string
  description = "Base ECR URI for shared services images (no tag)"
  default     = ""
}

variable "proxy_path_prefix" {
  type        = string
  description = "Path prefix this API registers in the shared proxy routing table"
  default     = "/v1/placeholder"
}
