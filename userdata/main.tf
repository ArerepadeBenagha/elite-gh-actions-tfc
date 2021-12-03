###########------ docker Server -----########
resource "aws_instance" "dockerserver" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main-public-1.id
  key_name               = aws_key_pair.mykeypair.key_name
  vpc_security_group_ids = [aws_security_group.ec2-sg.id, aws_security_group.main-alb.id]
  user_data_base64       = data.cloudinit_config.userdata.rendered
  lifecycle {
    ignore_changes = [ami, user_data_base64]
  }
  tags = merge(local.common_tags,
    { Name = "docker-server"
  Application = "public" })
}
###-------- ALB -------###
resource "aws_lb" "dockerlb" {
  name               = join("-", [local.application.app_name, "dockerlb"])
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2-sg.id, aws_security_group.main-alb.id]
  subnets            = [aws_subnet.main-public-1.id, aws_subnet.main-public-2.id]
  idle_timeout       = "60"

  access_logs {
    bucket  = aws_s3_bucket.logs_s3dev.bucket
    prefix  = join("-", [local.application.app_name, "dockerlb-s3logs"])
    enabled = true
  }
  tags = merge(local.common_tags,
    { Name = "dockerserver"
  Application = "public" })
}

###------- ALB Health Check -------###
resource "aws_lb_target_group" "dockerapp_tglb" {
  name     = join("-", [local.application.app_name, "dockerapptglb"])
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = "5"
    unhealthy_threshold = "2"
    timeout             = "5"
    interval            = "30"
    matcher             = "200"
  }
}

resource "aws_lb_target_group_attachment" "dockerapp_tglbat" {
  target_group_arn = aws_lb_target_group.dockerapp_tglb.arn
  target_id        = aws_instance.dockerserver.id
  port             = 80
}

####-------- SSL Cert ------#####
resource "aws_lb_listener" "dockerapp_lblist2" {
  load_balancer_arn = aws_lb.dockerlb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = "arn:aws:acm:us-east-1:901445516958:certificate/48b8cf75-798a-427e-8301-8f23ab6fde38"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dockerapp_tglb.arn
  }
}

####---- Redirect Rule -----####
resource "aws_lb_listener" "dockerapp_lblist" {
  load_balancer_arn = aws_lb.dockerlb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

########------- S3 Bucket -----------####
resource "aws_s3_bucket" "logs_s3dev" {
  bucket = join("-", [local.application.app_name, "logdev"])
  acl    = "private"

  tags = merge(local.common_tags,
    { Name = "dockerserver"
  bucket = "private" })
}
resource "aws_s3_bucket_policy" "logs_s3dev" {
  bucket = aws_s3_bucket.logs_s3dev.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "MYBUCKETPOLICY"
    Statement = [
      {
        Sid       = "Allow"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.logs_s3dev.arn,
          "${aws_s3_bucket.logs_s3dev.arn}/*",
        ]
        Condition = {
          NotIpAddress = {
            "aws:SourceIp" = "8.8.8.8/32"
          }
        }
      },
    ]
  })
}

#IAM
resource "aws_iam_role" "docker_role" {
  name = join("-", [local.application.app_name, "dockerrole"])

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(local.common_tags,
    { Name = "dockerserver"
  Role = "dockerrole" })
}

#######------- IAM Role ------######
resource "aws_iam_role_policy" "docker_policy" {
  name = join("-", [local.application.app_name, "dockerpolicy"])
  role = aws_iam_role.docker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

#####------ Certificate -----------####
resource "aws_acm_certificate" "dockercert" {
  domain_name       = "*.elietesolutionsit.de"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
  tags = merge(local.common_tags,
    { Name = "elite-jenkins-server.elietesolutionsit.de"
  Cert = "dockercert" })
}

###------- Cert Validation -------###
data "aws_route53_zone" "main-zone" {
  name         = "elietesolutionsit.de"
  private_zone = false
}

resource "aws_route53_record" "dockerzone_record" {
  for_each = {
    for dvo in aws_acm_certificate.dockercert.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "dockercert" {
  certificate_arn         = aws_acm_certificate.dockercert.arn
  validation_record_fqdns = [for record in aws_route53_record.dockerzone_record : record.fqdn]
}

##------- ALB Alias record ----------##
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main-zone.zone_id
  name    = "elite-jenkins-server.elietesolutionsit.de"
  type    = "A"

  alias {
    name                   = aws_lb.dockerlb.dns_name
    zone_id                = aws_lb.dockerlb.zone_id
    evaluate_target_health = true
  }
}