# ============================================================
# Route 53 DNS + ACM Certificate Validation
# ============================================================

# Look up existing hosted zone for veridialy.com
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ---- DNS record to validate the SSL certificate ----
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ---- SendGrid Domain Authentication ----
resource "aws_route53_record" "sendgrid_em" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "em9234.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["u59905925.wl176.sendgrid.net"]
}

resource "aws_route53_record" "sendgrid_dkim1" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "s1._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["s1.domainkey.u59905925.wl176.sendgrid.net"]
}

resource "aws_route53_record" "sendgrid_dkim2" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "s2._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["s2.domainkey.u59905925.wl176.sendgrid.net"]
}

resource "aws_route53_record" "sendgrid_dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=none;"]
}

# ---- api.veridialy.com -> API Gateway ----
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }
}
