# The Web Security Group
resource "aws_security_group" "web_sg" {
  name        = "${var.environment}-web-server-sg"
  description = "Allow inbound HTTP from ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    # Task 5 Requirement: Only allow traffic from ALB SG
    security_groups = [var.alb_sg_id] 
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["121.52.152.39/32"] # Your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# The Database Security Group (This is what is missing!)
resource "aws_security_group" "db_sg" {
  name        = "${var.environment}-db-server-sg"
  description = "Allow MySQL from Web SG only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id] # Only allows Web SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}