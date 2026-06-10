output "apex_zone_id" {
  value       = aws_route53_zone.apex.zone_id
  description = "Route53 zone ID for smartpropdata.org.uk"
}

output "apex_nameservers" {
  value       = aws_route53_zone.apex.name_servers
  description = "Nameservers to set at the registrar for smartpropdata.org.uk"
}
