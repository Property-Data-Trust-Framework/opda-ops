variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, staging). Used as the hostname label and resource suffix."
}

variable "shared_services_ecr_base" {
  type        = string
  description = "ECR repository base URL (SHARED_SERVICES_ECR_BASE from shared-services terraform output)"
}

variable "mtls_proxy_image_tag" {
  type        = string
  description = "Tag of the mtls proxy image to deploy (e.g. latest or a specific SHA tag)"
  default     = "latest"
}

variable "server_tls_certificate" {
  type        = string
  description = "PEM fullchain certificate for dev.api.smartpropdata.org.uk (Let's Encrypt)"
}

variable "server_tls_key" {
  type        = string
  description = "PEM private key matching server_tls_certificate"
  sensitive   = true
}

variable "ca_trusted_list" {
  type        = string
  description = "PEM bundle of CAs trusted for inbound client cert verification (Raidiam sandbox CA bundle)"
}

variable "external_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for api.smartpropdata.org.uk"
}
