# Auto Scaling
################################################
resource "aws_launch_configuration" "elitework-dev" {
  name_prefix   = "elitework-${var.app_tier}"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_size
  key_name      = aws_key_pair.mykeypair.key_name
  user_data     = data.cloudinit_config.userdata.rendered

  root_block_device {
    volume_size = 155
    volume_type = "gp2"
  }

  security_groups = [
    aws_security_group.ec2-sg.id,
    aws_security_group.main-alb.id
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "tfe_asg" {
  name                      = "elitework-${var.app_tier}"
  launch_configuration      = aws_launch_configuration.elitework-dev.name
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = [aws_subnet.main-public-1.id, aws_subnet.main-public-2.id]
  health_check_grace_period = 1800
  health_check_type         = "ELB"

  target_group_arns = [
    aws_lb_target_group.elitework_443.arn,
    aws_lb_target_group.elitework_8080.arn
  ]

  tag {
    key                 = "foo"
    value               = "bar"
    propagate_at_launch = true
  }
}
resource "aws_key_pair" "mykeypair" {
  key_name   = "mykeypair"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC98/ZrwBNqrQ662KrQGnUxUXg9EInl0rJP5OTVXzVoM+8gtD84Mgwap6L3NvC3BLRIzAjMb07P20CqOF8b+UVUT8Xoo4NKtkEZRyRLWcZQX8pIU/HcH1euejlC1w7SO5tlq5EY56TwF9oTIRzROwE3TkaKDpP27bQFZBVvoFnRBwwPWeP4BqmCZGk3THQOLoHkLNI0exX1ekSi/VrgWv7K38BIuDNQWzN75Yi5ZeLMYx50EAzIRtPqZgjJU9w3RjlDQCZr/y5epwc3+25SPU5V1+lIA5YeKQyFv/h9rVOajwfxdurq7ErpSV3mCh026Kdi9PS9SN5QaChKR4hxy2fgsWhzOMU89LoWx9q4Ho7zesQWUcapWiEVFRB6olN7IcVd7DpNy/JvCEAkTHj664LITV4NZla4mBea8pwPiZWRBkJo2RoC1Oz6m1H8xWn6l0KNhRiJzzxKzSreUZATh6gYZz4J32CyaLEVYHq0NncL5PjaPmiLvbpZbke0aL/6abs= lbena@LAPTOP-QB0DU4OG"
}

################################################
# Load Balancing
################################################
resource "aws_lb" "elitework_lb" {
  name               = "elitework-${var.app_tier}"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.ec2-sg.id,
    aws_security_group.main-alb.id
  ]

  subnets = [aws_subnet.main-public-1.id, aws_subnet.main-public-2.id]
  tags    = merge({ Name = "elitework-${var.app_tier}" }, local.common_tags)
}

resource "aws_lb_listener" "elitework_443" {
  load_balancer_arn = aws_lb.elitework_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.jenkinscert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.elitework_443.arn
  }
}

resource "aws_lb_listener" "elitework_80_rd" {
  load_balancer_arn = aws_lb.elitework_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "elitework_8080" {
  load_balancer_arn = aws_lb.elitework_lb.arn
  port              = 8080
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.jenkinscert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.elitework_8080.arn
  }
}

resource "aws_lb_target_group" "elitework_443" {
  name     = "elitework-443-${var.app_tier}"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/_health_check"
    protocol            = "HTTPS"
    matcher             = 200
    healthy_threshold   = 5
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
  }

  tags = merge(
    { Name = "elitework-443-${var.app_tier}" },
    { Description = "ALB Target Group for TFE web application HTTPS traffic" },
    local.common_tags
  )
}

resource "aws_lb_target_group" "elitework_8080" {
  name     = "elitework-8080-${var.app_tier}"
  port     = 8080
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path     = "/authenticate"
    protocol = "HTTPS"
    matcher  = 200
  }

  tags = merge(
    { Name = "elitework-8080-${var.app_tier}" },
    { Description = "ALB Target Group for TFE/Replicated web admin console traffic over port 8080" },
    local.common_tags
  )
}

################################################
# S3
################################################
# resource "aws_s3_bucket" "tfe_app" {
#   bucket = "bain-tfe-${var.app_tier}-app-${data.aws_caller_identity.current.account_id}"
# #  region = data.aws_region.current.name 

#   versioning {
#     enabled = true
#   }

#   server_side_encryption_configuration {
#     rule {
#       apply_server_side_encryption_by_default {
#         kms_master_key_id = data.aws_kms_key.storage_key.arn
#         sse_algorithm     = "aws:kms"
#       }
#     }
#   }

#   tags = merge(
#     { Name = "bain-tfe-app-${data.aws_caller_identity.current.account_id}" },
#     { Description = "TFE object storage" },
#     local.common_tags
#   )
# }
#####------ Certificate -----------####
resource "aws_acm_certificate" "jenkinscert" {
  domain_name       = "*.elietesolutionsit.de"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
  tags = merge(local.common_tags,
    { Name = "elitework-jenkins-server.elietesolutionsit.de"
  Cert = "jenkinscert" })
}

###------- Cert Validation -------###
data "aws_route53_zone" "main-zone" {
  name         = "elietesolutionsit.de"
  private_zone = false
}

resource "aws_route53_record" "jenkinszone_record" {
  for_each = {
    for dvo in aws_acm_certificate.jenkinscert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main-zone.zone_id
}

resource "aws_acm_certificate_validation" "jenkinscert" {
  certificate_arn         = aws_acm_certificate.jenkinscert.arn
  validation_record_fqdns = [for record in aws_route53_record.jenkinszone_record : record.fqdn]
}

##------- ALB Alias record ----------##
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main-zone.zone_id
  name    = "elitework-jenkins-devserver.elietesolutionsit.de"
  type    = "A"

  alias {
    name                   = aws_lb.elitework_lb.dns_name
    zone_id                = aws_lb.elitework_lb.zone_id
    evaluate_target_health = true
  }
}

#EC2-SG
resource "aws_security_group" "ec2-sg" {
  vpc_id      = aws_vpc.main.id
  name        = "public web jenkins sg"
  description = "security group Ec2-server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.main-alb.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.main-alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags,
  { Name = "Ec2 security group" })
}

#ALB-SG
resource "aws_security_group" "main-alb" {
  vpc_id      = aws_vpc.main.id
  name        = "public web allow"
  description = "security group for ALB"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags,
  { Name = "Alb security group" })
}

////VPC
# Vars.tf
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

# Subnets
resource "aws_subnet" "main-public-1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "us-east-1a"

  tags = {
    Name = "Main-public-1"
  }
}
resource "aws_subnet" "main-public-2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "us-east-1b"

  tags = {
    Name = "Main-public-2"
  }
}
resource "aws_subnet" "main-public-3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = "true"
  availability_zone       = "us-east-1c"

  tags = {
    Name = "Main-public-3"
  }
}
resource "aws_subnet" "main-private-1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "us-east-1a"

  tags = {
    Name = "Main-private-1"
  }
}
resource "aws_subnet" "main-private-2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.5.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "us-east-1b"

  tags = {
    Name = "Main-private-2"
  }
}
resource "aws_subnet" "main-private-3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.6.0/24"
  map_public_ip_on_launch = "false"
  availability_zone       = "us-east-1c"

  tags = {
    Name = "Main-private-3"
  }
}

# Internet GW
resource "aws_internet_gateway" "main-gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

# route tables
resource "aws_route_table" "main-public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main-gw.id
  }

  tags = {
    Name = "main-public-1"
  }
}

# route associations public
resource "aws_route_table_association" "main-public-1-a" {
  subnet_id      = aws_subnet.main-public-1.id
  route_table_id = aws_route_table.main-public.id
}
resource "aws_route_table_association" "main-public-2-a" {
  subnet_id      = aws_subnet.main-public-2.id
  route_table_id = aws_route_table.main-public.id
}
resource "aws_route_table_association" "main-public-3-a" {
  subnet_id      = aws_subnet.main-public-3.id
  route_table_id = aws_route_table.main-public.id
}