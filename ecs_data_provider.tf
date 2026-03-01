# ============================================================
# ECS Fargate — Data Provider (scheduled task)
# (Runs periodically via EventBridge, not as always-on service)
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

      command = ["python", "src/updater.py", "--once"]

      # Environment variables (non-sensitive)
      environment = [
        { name = "DB_HOST", value = split(":", aws_db_instance.postgres.endpoint)[0] },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_NAME", value = var.db_name },
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

# ---- IAM Role: EventBridge Scheduler can run ECS tasks ----
resource "aws_iam_role" "data_provider_scheduler" {
  name = "${var.project_name}-data-provider-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "data_provider_scheduler" {
  name = "${var.project_name}-data-provider-scheduler-policy"
  role = aws_iam_role.data_provider_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          aws_ecs_task_definition.data_provider.arn,
          "${aws_ecs_task_definition.data_provider.arn_without_revision}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      }
    ]
  })
}

# ---- EventBridge Rule: run data provider task periodically ----
resource "aws_cloudwatch_event_rule" "data_provider_schedule" {
  name                = "${var.project_name}-data-provider-schedule"
  description         = "Run data provider ECS task on a schedule"
  schedule_expression = var.data_provider_schedule_expression
}

resource "aws_cloudwatch_event_target" "data_provider_schedule" {
  rule      = aws_cloudwatch_event_rule.data_provider_schedule.name
  target_id = "${var.project_name}-data-provider"
  arn       = aws_ecs_cluster.main.arn
  role_arn  = aws_iam_role.data_provider_scheduler.arn

  ecs_target {
    launch_type         = "FARGATE"
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.data_provider.arn

    network_configuration {
      subnets = [
        aws_subnet.public_1.id,
        aws_subnet.public_2.id,
      ]
      security_groups  = [aws_security_group.data_provider.id]
      assign_public_ip = true
    }
  }
}

