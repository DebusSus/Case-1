provider "aws" {
  region  = "eu-central-1"
  profile = "fictisb_IsbUsersPS-253137917008"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "project-vpc"
  }
}

# Public Subnet for ALB
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

# Private App Subnet for ECS
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "private-app-subnet"
  }
}

# Private DB Subnet for RDS
resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "private-db-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "project-igw"
  }
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP from anywhere (public)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all outbound
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# Security Group for ECS
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]  # Allow ALB traffic
  }

  egress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private_db.cidr_block]  # Allow RDS access
  }

  tags = {
    Name = "ecs-sg"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]  # Allow ECS traffic
  }

  tags = {
    Name = "rds-sg"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "ticket-cluster"
  tags = {
    Name = "ticket-cluster"
  }
}

# ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "ticket-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets          = [aws_subnet.private_app.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.id
    container_name   = "ticket-container"
    container_port   = 80
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_policy]

  tags = {
    Name = "ticket-service"
  }
}

# ECR Repository
resource "aws_ecr_repository" "ecr_repo" {
  name = "ecr-repo"
}

# EC2 Instance Role for ECS
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"
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
}

# Attach ECS Instance Policy
resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# Launch Template for ECS Instances
resource "aws_launch_template" "ecs" {
  name_prefix   = "ecs-template-"
  image_id      = "ami-001a4ee35c9b219b2"
  instance_type = "t2.micro"
  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance_profile.arn
  }
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=ticket-cluster >> /etc/ecs/ecs.config
  EOF
  )
  network_interfaces {
    associate_public_ip_address = false
    security_groups = [aws_security_group.ecs_sg.id]
    subnet_id       = aws_subnet.private_app.id
  }
  tags = {
    Name = "ecs-instance"
  }
}
# Auto Scaling Group for ECS
#resource "aws_autoscaling_group" "ecs" {
#  vpc_zone_identifier = [aws_subnet.private_app.id]
#  target_group_arns   = [aws_lb_target_group.app.id]
#  health_check_type   = "EC2"
#  min_size           = 0 #replace to 1 when done DONT FORGET
#  max_size           = 2
#  desired_capacity   = 0 #also replace to 1
#  launch_template {
#    id      = aws_launch_template.ecs.id
#    version = "$Latest"
#  }
#}

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "ticket-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_eu_central_1b.id]  
  tags = {
    Name = "ticket-alb"
  }
}

# Target Group for ALB
resource "aws_lb_target_group" "app" {
  name     = "ticket-target-group"
  target_type = "ip"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  lifecycle {
    create_before_destroy = true
  }
  
  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name = "ticket-target-group"
  }
}

# Listener for ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 3000
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Second Public Subnet in eu-central-1b
resource "aws_subnet" "public_eu_central_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.5.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-eu-central-1b"
  }
}