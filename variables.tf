# ============================================================
# Variables — customize these for your environment
# ============================================================

variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for naming resources"
  type        = string
  default     = "macro-terminal"
}

variable "environment" {
  description = "Environment (e.g. production, staging)"
  type        = string
  default     = "production"
}

# ---- Domain ----
variable "domain_name" {
  description = "Root domain name (e.g. veridialy.com)"
  type        = string
  default     = "veridialy.com"
}

variable "api_subdomain" {
  description = "Subdomain for the API (e.g. api → api.veridialy.com)"
  type        = string
  default     = "api"
}

# ---- Database ----
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "macro_terminal"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "macro_admin"
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.micro"
}

# ---- ECS / Fargate ----
variable "api_container_port" {
  description = "Port the API container listens on"
  type        = number
  default     = 3000
}

variable "api_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 512
}

variable "api_desired_count" {
  description = "Number of API containers to run"
  type        = number
  default     = 1
}

variable "api_min_count" {
  description = "Minimum number of containers for autoscaling"
  type        = number
  default     = 1
}

variable "api_max_count" {
  description = "Maximum number of containers for autoscaling"
  type        = number
  default     = 4
}

# ---- Application Secrets ----
variable "jwt_secret" {
  description = "JWT signing secret"
  type        = string
  sensitive   = true
}

variable "jwt_expiration_hours" {
  description = "JWT expiration in hours"
  type        = string
  default     = "24"
}

variable "sendgrid_api_key" {
  description = "SendGrid API key for emails"
  type        = string
  sensitive   = true
}

variable "from_email" {
  description = "From email address for outgoing emails"
  type        = string
  default     = "noreply@veridialy.com"
}

variable "recaptcha_secret_key" {
  description = "Google reCAPTCHA secret key"
  type        = string
  sensitive   = true
}

variable "google_client_id" {
  description = "Google OAuth client ID"
  type        = string
}

variable "google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  sensitive   = true
}

variable "mp_access_token" {
  description = "Mercado Pago access token"
  type        = string
  sensitive   = true
}

variable "mp_webhook_secret" {
  description = "Mercado Pago webhook signing secret"
  type        = string
  sensitive   = true
}

variable "mp_api_base_url" {
  description = "Mercado Pago API base URL"
  type        = string
  default     = "https://api.mercadopago.com"
}

variable "mp_plan_ids" {
  description = "Comma-separated Mercado Pago preapproval_plan IDs"
  type        = string
  default     = ""
}

variable "frontend_url" {
  description = "Frontend URL for CORS and redirects"
  type        = string
  default     = "https://veridialy.com"
}

variable "discord_webhook_url" {
  description = "Discord webhook URL for admin notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "refresh_token_expiration_days" {
  description = "Refresh token expiration in days"
  type        = string
  default     = "30"
}

variable "admin_secret" {
  description = "Secret token for admin API endpoints"
  type        = string
  sensitive   = true
}

# ---- Data Provider ----
variable "data_provider_cpu" {
  description = "Fargate task CPU units for data provider"
  type        = number
  default     = 512 # 0.5 vCPU (Chromium needs more)
}

variable "data_provider_memory" {
  description = "Fargate task memory in MB for data provider"
  type        = number
  default     = 1024 # 1 GB (Chromium needs more)
}

variable "data_provider_update_interval" {
  description = "Data provider update interval in seconds"
  type        = string
  default     = "21600" # 6 hours
}

