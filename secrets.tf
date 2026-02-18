# ============================================================
# AWS Secrets Manager — Application secrets for ECS
# ============================================================

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.project_name}/${var.environment}/app-secrets"
  description             = "Application secrets for ${var.project_name}"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-app-secrets"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    # API secrets
    JWT_SECRET           = var.jwt_secret
    SENDGRID_API_KEY     = var.sendgrid_api_key
    RECAPTCHA_SECRET_KEY = var.recaptcha_secret_key
    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    MP_ACCESS_TOKEN      = var.mp_access_token
    MP_WEBHOOK_SECRET    = var.mp_webhook_secret
    DISCORD_WEBHOOK_URL   = var.discord_webhook_url
    DATABASE_URL         = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.endpoint}/${var.db_name}"

    # Data provider secrets (shared DB credentials)
    DB_USER     = var.db_username
    DB_PASSWORD = var.db_password
  })
}
