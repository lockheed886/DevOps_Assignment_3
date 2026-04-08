variable "vpc_id" { type = string }
variable "environment" { type = string }
# Add this new variable:
variable "alb_sg_id" { 
  type        = string
  description = "The ID of the ALB security group"
}