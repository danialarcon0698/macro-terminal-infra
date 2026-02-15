# ============================================================
# Security Groups
# ============================================================

# ---- ECS API Security Group (API Gateway VPC Link + outbound internet) ----
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Allow traffic from API Gateway VPC Link to ECS containers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "From API Gateway VPC Link"
    from_port   = var.api_container_port
    to_port     = var.api_container_port
    protocol    = "tcp"
    self        = true # VPC Link uses the same security group
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-sg"
  }
}

# ---- Data Provider Security Group (outbound only, no inbound traffic) ----
resource "aws_security_group" "data_provider" {
  name        = "${var.project_name}-data-provider-sg"
  description = "Data provider - outbound internet + database access"
  vpc_id      = aws_vpc.main.id

  # No ingress rules — data provider doesn't receive any traffic

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-data-provider-sg"
  }
}

# ---- RDS Security Group (API + Data Provider can reach it) ----
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL traffic from ECS services"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from API"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  ingress {
    description     = "PostgreSQL from Data Provider"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.data_provider.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}
