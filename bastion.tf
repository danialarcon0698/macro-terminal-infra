# ============================================================
# SSM Bastion Host — Secure tunnel to private RDS
# (t4g.nano ~$3/mo, stopped when not in use = pennies)
# ============================================================

# ---- Latest Amazon Linux 2023 ARM AMI (for Graviton t4g) ----
# NOTE: Using the full AMI (not minimal) because it includes SSM agent
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# ---- IAM Role for SSM ----
resource "aws_iam_role" "bastion" {
  name = "${var.project_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-bastion-role"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project_name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

# ---- Security Group (outbound only — no inbound needed) ----
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Bastion for SSM tunnel - outbound to SSM and RDS"
  vpc_id      = aws_vpc.main.id

  # Outbound: SSM (HTTPS) + RDS (5432)
  # RDS SG controls inbound — bastion just needs to be allowed out
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

# ---- EC2 Instance ----
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t4g.nano"
  subnet_id              = aws_subnet.public_1.id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # No SSH key — access is via SSM only
  associate_public_ip_address = true # Needed for SSM agent to reach SSM service

  metadata_options {
    http_tokens   = "required" # IMDSv2 only (security best practice)
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

