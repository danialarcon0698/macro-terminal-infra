# ============================================================
# API Gateway HTTP API + Custom Domain (replaces ALB — pay per request)
# ============================================================

# ---- SSL Certificate (auto-validated via DNS) ----
resource "aws_acm_certificate" "api" {
  domain_name       = "${var.api_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-api-cert"
  }
}

# ---- API Gateway HTTP API ----
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name = "${var.project_name}-api-gateway"
  }
}

# ---- VPC Link (API Gateway → ECS in VPC) ----
resource "aws_apigatewayv2_vpc_link" "api" {
  name = "${var.project_name}-vpc-link"
  subnet_ids = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id,
  ]
  security_group_ids = [aws_security_group.ecs.id]

  tags = {
    Name = "${var.project_name}-vpc-link"
  }
}

# ---- Cloud Map namespace for service discovery ----
resource "aws_service_discovery_private_dns_namespace" "api" {
  name = "${var.project_name}.local"
  vpc  = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-discovery-namespace"
  }
}

resource "aws_service_discovery_service" "api" {
  name = "api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.api.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ---- Integration (API Gateway → ECS via Cloud Map) ----
resource "aws_apigatewayv2_integration" "api" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_service_discovery_service.api.arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.api.id
}

# ---- Route: catch-all → ECS ----
resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

# ---- Stage (auto-deploy) ----
resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }
}

# ---- Log group for API Gateway ----
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/apigateway/${var.project_name}-api"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

# ---- Custom Domain (api.veridialy.com) ----
resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = "${var.api_subdomain}.${var.domain_name}"

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  depends_on = [aws_acm_certificate_validation.api]

  tags = {
    Name = "${var.project_name}-api-domain"
  }
}

# ---- Map custom domain → API stage ----
resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.api.id
}
