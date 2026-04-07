variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "Invalid instance_type. Must be t3.micro, t3.small, or t3.medium."
  }
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}