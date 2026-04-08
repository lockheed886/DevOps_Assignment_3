terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" 
    }
  }
  backend "s3" {
    bucket         = "devops-state-bucket-22f-3664"
    key            = "devops/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devops-state-locks-22f-3664"
    encrypt        = true 
  }
}

provider "aws" { region = "us-east-1" }

# Requirement: Task 6 Cross-Module References 
module "vpc" {
  source               = "./modules/vpc"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  environment          = "prod"
}

module "security" {
  source      = "./modules/security"
  vpc_id      = module.vpc.vpc_id
  alb_sg_id   = aws_security_group.alb_sg.id 
  environment = "prod"
}

module "compute" {
  source             = "./modules/compute"
  ami_id             = "ami-055ad543fd78ed043"
  instance_type      = "t3.micro"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security.web_sg_id]
  key_name           = aws_key_pair.deployer.key_name
  environment        = "prod"
}

resource "aws_key_pair" "deployer" {
  key_name   = "devops_key"
  public_key = file("${path.module}/devops_key.pub") 
}
# 1. Security Group for the ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to the world
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Application Load Balancer
resource "aws_lb" "web_alb" {
  name               = "devops-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnet_ids # Spans both public subnets
}

# 3. Target Group with Health Checks
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2 # Requirement
    unhealthy_threshold = 3 # Requirement
  }
}

# 4. Listener
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}
# 1. Launch Template
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-launch-template-"
  image_id      = var.ami_id           # Your Packer AMI ID 
  instance_type = var.instance_type    # t3.micro 
  key_name      = var.key_name        # devops_key 

  vpc_security_group_ids = [module.security.web_sg_id] # 

  # Requirement: Install stress-ng on boot [cite: 69]
  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y stress-ng
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ASG-Web-Server" # Requirement: Propagating tags [cite: 71]
    }
  }
}
# 2. Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  desired_capacity    = 1 # 
  max_size            = 3 # 
  min_size            = 1 # 
  vpc_zone_identifier = module.vpc.public_subnet_ids # Spans public subnets 

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  # Task 5 Requirement: Attach ASG to the ALB Target Group [cite: 91]
  target_group_arns = [aws_lb_target_group.web_tg.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300
}
# 3. Scale-Out Policy (Add 1 instance) [cite: 72]
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 120 # Requirement [cite: 76]
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

# 4. Scale-Out Alarm (CPU >= 60%) [cite: 73]
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-high-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "60"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

# 5. Scale-In Policy (Remove 1 instance) [cite: 74]
resource "aws_autoscaling_policy" "scale_in" {
  name                   = "scale-in-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 120 # Requirement [cite: 74]
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

# 6. Scale-In Alarm (CPU <= 20%) [cite: 75]
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu-low-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "20"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}