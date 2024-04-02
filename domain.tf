# 
resource "aws_acm_certificate" "cert" {
  domain_name       = "lamorre.com"
  validation_method = "DNS"

  subject_alternative_names = ["www.lamorre.com"]

  tags = {
    Name = "my_domain_certificate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 
data "aws_route53_zone" "selected" {
  name = "lamorre.com"
}

# 
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.selected.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_route53_record" "root_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "lamorre.com"
  type    = "A"

  alias {
    name                   = aws_lb.default.dns_name
    zone_id                = aws_lb.default.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "www_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "www.lamorre.com"
  type    = "A"

  alias {
    name                   = aws_lb.default.dns_name
    zone_id                = aws_lb.default.zone_id
    evaluate_target_health = true
  }
}

# Successful validation of an ACM certificate in concert
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Security group for ALB, allows HTTPS traffic
resource "aws_security_group" "alb_sg" {
  vpc_id      = aws_vpc.default.id
  name        = "alb-https-security-group"
  description = "Allow all inbound HTTPS traffic"

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
}

# Application Load Balancer for HTTPS traffic
resource "aws_lb" "default" {
  name               = "django-ec2-alb-https"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  enable_deletion_protection = false
}

# Target group for the ALB
resource "aws_lb_target_group" "default" {
  name     = "django-ec2-tg-https"
  port     = 443
  protocol = "HTTP" # Protocol used between the load balancer and targets
  vpc_id   = aws_vpc.default.id
}

# Attach the EC2 instance to the target group
resource "aws_lb_target_group_attachment" "default" {
  target_group_arn = aws_lb_target_group.default.arn
  target_id        = aws_instance.web.id # Your EC2 instance ID
  port             = 80                  # Port the EC2 instance listens on; adjust if different
}


# HTTPS listener for the ALB
resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Default policy, adjust as needed
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}
