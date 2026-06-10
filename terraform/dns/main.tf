# ── smartpropdata.org.uk apex zone ────────────────────────────────────────────
# The registrar delegates smartpropdata.org.uk to Route53. This zone is the
# authoritative parent; subdomain zones are delegated via NS records below.

resource "aws_route53_zone" "apex" {
  name = "smartpropdata.org.uk"

  tags = {
    ManagedBy = "terraform"
    Project   = "opda-ops"
  }
}

# ── Existing subdomain zones (look up nameservers dynamically) ─────────────────

data "aws_route53_zone" "api" {
  name = "api.smartpropdata.org.uk"
}

data "aws_route53_zone" "ext" {
  name = "ext.smartpropdata.org.uk"
}

# ── NS delegation records ──────────────────────────────────────────────────────

resource "aws_route53_record" "api_ns" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = "api.smartpropdata.org.uk"
  type    = "NS"
  ttl     = 300
  records = data.aws_route53_zone.api.name_servers
}

resource "aws_route53_record" "ext_ns" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = "ext.smartpropdata.org.uk"
  type    = "NS"
  ttl     = 300
  records = data.aws_route53_zone.ext.name_servers
}
