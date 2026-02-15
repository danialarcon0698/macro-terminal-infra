# ============================================================
# ECS Fargate — Data Provider Service
# (Runs on a schedule, fetches macro data, writes to shared DB)
# ============================================================

# ---- CloudWatch Log Group ----
resource "aws_cloudwatch_log_group" "data_provider" {
  name              = "/ecs/${var.project_name}-data-provider"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-data-provider-logs"
  }
}

# ---- Task Definition ----
resource "aws_ecs_task_definition" "data_provider" {
  family                   = "${var.project_name}-data-provider"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.data_provider_cpu
  memory                   = var.data_provider_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-data-provider"
      image = "${aws_ecr_repository.data_provider.repository_url}:latest"

      command = ["python", "src/updater.py", "--interval", var.data_provider_update_interval]

      # Environment variables (non-sensitive)
      environment = [
        { name = "DB_HOST", value = split(":", aws_db_instance.postgres.endpoint)[0] },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = var.db_name },
        { name = "UPDATE_INTERVAL", value = var.data_provider_update_interval },
        { name = "CHROME_BIN", value = "/usr/bin/chromium" },
        { name = "CHROMEDRIVER_PATH", value = "/usr/bin/chromedriver" },
      ]

      # Secrets (pulled from Secrets Manager)
      secrets = [
        { name = "DB_USER", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_USER::" },
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DB_PASSWORD::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.data_provider.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "data-provider"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-data-provider-task"
  }
}

# ---- ECS Service (always running, restarts on failure) ----
resource "aws_ecs_service" "data_provider" {
  name            = "${var.project_name}-data-provider"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.data_provider.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
    ]
    security_groups  = [aws_security_group.data_provider.id]
    assign_public_ip = true # Needed for outbound internet (web scraping, APIs)
  }

  # No load balancer — this service doesn't receive HTTP traffic
  # It only makes outbound requests and writes to the database

  deployment_minimum_healthy_percent = 0   # OK to have 0 during deploy (no traffic)
  deployment_maximum_percent         = 100

  tags = {
    Name = "${var.project_name}-data-provider-service"
  }
}

