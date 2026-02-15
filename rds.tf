# ============================================================
# RDS PostgreSQL Database
# ============================================================

resource "aws_db_subnet_group" "main" {
  name = "${var.project_name}-db-subnet"
  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id,
  ]

  tags = {
    Name = "${var.project_name}-db-subnet"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-db"

  # Engine
  engine         = "postgres"
  engine_version = "15.10"
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = 20
  max_allocated_storage = 100 # Auto-scales storage up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # Set to true for high availability ($$$)

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00" # UTC
  maintenance_window      = "sun:04:00-sun:05:00"

  # Protection
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project_name}-db-final-snapshot"

  # Monitoring
  performance_insights_enabled = true

  tags = {
    Name = "${var.project_name}-db"
  }
}

