## Vars.tf
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  enable_classiclink   = "false"
  tags = {
    Name = "main"
  }
}

#SG
resource "aws_security_group" "main-sg" {
  vpc_id      = aws_vpc.main.id
  name        = "public web allow"
  description = "security group for ALB"
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags,
  { Name = "efs-sg" })
}

#Efs
resource "aws_efs_file_system" "foo" {
  creation_token = "my-product"

  tags = merge(local.common_tags,
    { Name = "elite-product"
  Environment = "dev" })
  depends_on = [
    aws_security_group.main-sg
  ]
}