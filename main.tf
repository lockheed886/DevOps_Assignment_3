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