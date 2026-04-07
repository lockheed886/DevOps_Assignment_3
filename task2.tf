# 1. AWS Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = file("${path.module}/devops_key.pub")
}

# 2. Web Server Security Group (Restricted to YOUR IP: 121.52.152.39)
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  description = "Allow inbound HTTP, HTTPS, SSH from my IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["121.52.152.39/32"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["121.52.152.39/32"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["121.52.152.39/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. Database Security Group (Restricted to Web SG)
resource "aws_security_group" "db_sg" {
  name        = "db-server-sg"
  description = "Allow MySQL from Web SG only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Public Web Server EC2
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y nginx
              INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
              echo "<h1>Welcome to DevOps Assignment! Instance ID: $INSTANCE_ID</h1>" > /var/www/html/index.html
              systemctl restart nginx
              EOF

  tags = {
    Name = "Web-Server"
  }
}

# 5. Private DB Server EC2
resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_1.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  tags = {
    Name = "DB-Server"
  }
}

# 6. Outputs
output "web_public_ip" {
  value = aws_instance.web.public_ip
}
output "db_private_ip" {
  value = aws_instance.db.private_ip
}