# ============================================================
# ECS Fargate — Cluster, Task Definition, Service, Autoscaling
# ============================================================

# ---- CloudWatch Log Group ----
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}-api"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-api-logs"
  }
}

# ---- IAM Role: ECS Task Execution (pulling images, reading secrets) ----
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS to read secrets from Secrets Manager
resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.project_name}-ecs-secrets-policy"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [aws_secretsmanager_secret.app_secrets.arn]
      }
    ]
  })
}

# ---- IAM Role: ECS Task (what the running container can do) ----
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Allow ECS Exec (SSM) for debugging and port forwarding
resource "aws_iam_role_policy" "ecs_exec" {
  name = "${var.project_name}-ecs-exec-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---- ECS Cluster ----
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# ---- Task Definition ----
resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project_name}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-api"
      image = "${aws_ecr_repository.api.repository_url}:latest"

      portMappings = [
        {
          containerPort = var.api_container_port
          hostPort      = var.api_container_port
          protocol      = "tcp"
        }
      ]

      # Environment variables (non-sensitive)
      environment = [
        { name = "SERVER_HOST", value = "0.0.0.0" },
        { name = "SERVER_PORT", value = tostring(var.api_container_port) },
        { name = "RUST_LOG", value = "info" },
        { name = "JWT_EXPIRATION_HOURS", value = var.jwt_expiration_hours },
        { name = "FROM_EMAIL", value = var.from_email },
        { name = "FRONTEND_URL", value = var.frontend_url },
        { name = "API_BASE_URL", value = "https://${var.api_subdomain}.${var.domain_name}" },
        { name = "MP_API_BASE_URL", value = var.mp_api_base_url },
        { name = "MP_PLAN_IDS", value = var.mp_plan_ids },
        { name = "GOOGLE_REDIRECT_URI", value = "https://${var.api_subdomain}.${var.domain_name}/api/auth/google/callback" },
        { name = "REFRESH_TOKEN_EXPIRATION_DAYS", value = var.refresh_token_expiration_days },
      ]

      # Secrets (pulled from Secrets Manager at container start)
      secrets = [
        { name = "JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:JWT_SECRET::" },
        { name = "DATABASE_URL", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DATABASE_URL::" },
        { name = "SENDGRID_API_KEY", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:SENDGRID_API_KEY::" },
        { name = "RECAPTCHA_SECRET_KEY", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:RECAPTCHA_SECRET_KEY::" },
        { name = "GOOGLE_CLIENT_ID", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:GOOGLE_CLIENT_ID::" },
        { name = "GOOGLE_CLIENT_SECRET", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:GOOGLE_CLIENT_SECRET::" },
        { name = "MP_ACCESS_TOKEN", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:MP_ACCESS_TOKEN::" },
        { name = "MP_WEBHOOK_SECRET", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:MP_WEBHOOK_SECRET::" },
        { name = "DISCORD_WEBHOOK_URL", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:DISCORD_WEBHOOK_URL::" },
        { name = "ADMIN_SECRET", valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:ADMIN_SECRET::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.api_container_port}/api/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-api-task"
  }
}

# ---- ECS Service ----
resource "aws_ecs_service" "api" {
  name                   = "${var.project_name}-api"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.api.arn
  desired_count          = var.api_desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets = [
      aws_subnet.public_1.id,
      aws_subnet.public_2.id,
    ]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # Needed for outbound internet (no NAT Gateway)
  }

  # Service discovery registration (API Gateway finds containers via Cloud Map)
  service_registries {
    registry_arn   = aws_service_discovery_service.api.arn
    container_name = "${var.project_name}-api"
    container_port = var.api_container_port
  }

  # Allow new deployments to drain gracefully
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  tags = {
    Name = "${var.project_name}-api-service"
  }
}

# ============================================================
# Autoscaling
# ============================================================

resource "aws_appautoscaling_target" "api" {
  max_capacity       = var.api_max_count
  min_capacity       = var.api_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale up when CPU > 70%
resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${var.project_name}-api-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300 # Wait 5 min before scaling down
    scale_out_cooldown = 60  # Wait 1 min before scaling up again
  }
}

# Scale up when memory > 80%
resource "aws_appautoscaling_policy" "api_memory" {
  name               = "${var.project_name}-api-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

