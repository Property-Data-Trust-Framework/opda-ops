output "endpoint" {
  description = "Public mTLS endpoint (e.g. https://dev.api.smartpropdata.org.uk)"
  value       = module.shared_proxy.endpoint
}

output "nlb_dns_name" {
  description = "Raw NLB DNS name"
  value       = module.shared_proxy.nlb_dns_name
}

output "routes_ssm_path" {
  description = "SSM path where APIs register their routes (/opda/proxy/routes/)"
  value       = "/opda/proxy/routes/"
}
