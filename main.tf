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
  vpc_id      = module.vpc.vpc_id # Reference from VPC module
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