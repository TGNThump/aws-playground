terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 2.0"
    }
  }
}

locals {
  region = "eu-west-1"
}

provider "aws" {
  profile = "default"
  alias = "us-east-1"
  region  = "us-east-1"
}

provider "aws" {
  profile = "default"
  region  = local.region
}

provider "cloudflare" {}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = local.region
  }
}

resource "aws_vpc_dhcp_options" "main" {
  domain_name = "aws.pilgrim.me.uk"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name = "DHCP Option Set"
  }
}

resource "aws_vpc_dhcp_options_association" "main" {
  dhcp_options_id = aws_vpc_dhcp_options.main.id
  vpc_id = aws_vpc.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

variable "availability_zones" {
  type = list(object({
    name: string
    id: string
  }))
  default = [{
    name: "eu-west-1a"
    id: "euw1-az1"
  },
  {
    name: "eu-west-1b"
    id: "euw1-az2"
  }]
}

// DMZ

resource "aws_route_table" "dmz" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "dmz-euw1"
  }
}

resource "aws_subnet" "dmz-subnets" {
  count = length(var.availability_zones)

  cidr_block              = "10.0.${count.index}.0/24"
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zones[count.index].name
  tags = {
    Name = "dmz-${var.availability_zones[count.index].id}"
  }
}

resource "aws_route_table_association" "dmz-route-table-associations" {
  count = length(var.availability_zones)

  route_table_id = aws_route_table.dmz.id
  subnet_id = aws_subnet.dmz-subnets[count.index].id
}

// NAT

//resource "aws_route_table" "nat" {
//  vpc_id = aws_vpc.main.id
//
//  route {
//    cidr_block = "0.0.0.0/0"
//    gateway_id = aws_internet_gateway.main.id
//  }
//
//  tags = {
//    Name = "nat-euw1"
//  }
//}
//
//resource "aws_subnet" "nat-subnets" {
//  count = length(var.availability_zones)
//
//  cidr_block              = "10.0.${20 + count.index}.0/24"
//  vpc_id                  = aws_vpc.main.id
//  map_public_ip_on_launch = true
//  availability_zone       = var.availability_zones[count.index].name
//  tags = {
//    Name = "nat-${var.availability_zones[count.index].id}"
//  }
//}
//
//resource "aws_route_table_association" "dmz-route-table-associations" {
//  count = length(var.availability_zones)
//
//  route_table_id = aws_route_table.dmz.id
//  subnet_id = aws_subnet.dmz-subnets[count.index].id
//}

resource "aws_eip" "nat-eips" {
  count = length(var.availability_zones)

  tags = {
    Name = "${var.availability_zones[count.index].id}-nat"
  }
}

resource "aws_nat_gateway" "nat-gateways" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat-eips[count.index].id
//  subnet_id = aws_subnet.nat-subnets[count.index].id
  subnet_id = aws_subnet.dmz-subnets[count.index].id
  tags = {
    Name = "nat-${var.availability_zones[count.index].id}"
  }
}

// APP

resource "aws_subnet" "app-subnets" {
  count = length(var.availability_zones)

  cidr_block              = "10.0.${10 + count.index}.0/24"
  vpc_id                  = aws_vpc.main.id
  availability_zone       = var.availability_zones[count.index].name
  tags = {
    Name = "app-${var.availability_zones[count.index].id}"
  }
}

resource "aws_route_table" "app-route-tables" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gateways[count.index].id
  }

  tags = {
    Name = "app-${var.availability_zones[count.index].id}"
  }
}

resource "aws_route_table_association" "app-route-table-associations" {
  count = length(var.availability_zones)

  route_table_id = aws_route_table.app-route-tables[count.index].id
  subnet_id = aws_subnet.app-subnets[count.index].id
}

resource "aws_security_group" "app" {
  name = "APP"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "APP"
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "TCP"
    security_groups = [aws_security_group.albs.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

data "cloudflare_zones" "main" {
  filter {
    name = "pilgrim.me.uk"
    status = "active"
    paused = false
  }
}

resource "cloudflare_record" "ns-records" {
  count = length(aws_route53_zone.main.name_servers)

  name = "aws.pilgrim.me.uk"
  value = aws_route53_zone.main.name_servers[count.index]
  type = "NS"
  ttl = 1
  zone_id = data.cloudflare_zones.main.zones[0].id
}

resource "aws_route53_zone" "main" {
  name = "aws.pilgrim.me.uk"
}

resource "aws_acm_certificate" "cert" {
  domain_name = "aws.pilgrim.me.uk"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "aws.pilgrim.me.uk"
  }
}

//noinspection HILUnresolvedReference
resource "aws_route53_record" "domain-validation-records" {
  for_each = {
  for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
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
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "validation" {
  certificate_arn = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.domain-validation-records : record.fqdn]
}

resource "aws_acm_certificate" "cert-us-east-1" {
  provider = aws.us-east-1
  domain_name = "aws.pilgrim.me.uk"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "aws.pilgrim.me.uk"
  }
}

//noinspection HILUnresolvedReference
resource "aws_route53_record" "domain-validation-records-us-east-1" {
  provider = aws.us-east-1
  for_each = {
  for dvo in aws_acm_certificate.cert-us-east-1.domain_validation_options : dvo.domain_name => {
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
  zone_id         = aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "validation-us-east-1" {
  provider = aws.us-east-1
  certificate_arn = aws_acm_certificate.cert-us-east-1.arn
  validation_record_fqdns = [for record in aws_route53_record.domain-validation-records : record.fqdn]
}

resource "aws_route53_record" "dmz-cloudfront" {
  name = aws_route53_zone.main.name
  type = "A"
  zone_id = aws_route53_zone.main.id
  alias {
    evaluate_target_health = false
    name = aws_cloudfront_distribution.main.domain_name
    zone_id = aws_cloudfront_distribution.main.hosted_zone_id
  }
}

resource "aws_alb" "dmz-lb" {
  name = "DMZ-ALB"
  security_groups = [aws_security_group.albs.id]
  subnets = aws_subnet.dmz-subnets.*.id

  tags = {
    Name = "DMZ-ALB"
  }
}

resource "aws_security_group" "albs" {
  name = "DMZ"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "DMZ"
  }

  ingress {
    from_port = 443
    protocol = "TCP"
    to_port = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.dmz-lb.arn
  port = 443
  protocol = "HTTPS"
  certificate_arn = aws_acm_certificate.cert.arn
  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.test_service.arn
  }
}

resource "aws_ecs_cluster" "main" {
  name = "app"
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
  }
}


resource "random_uuid" "test_service_tg_name" {}
resource "aws_alb_target_group" "test_service" {
//  https://stackoverflow.com/questions/57183814/
//  https://github.com/hashicorp/terraform-provider-aws/issues/1666
  name  = substr(format("%s-%s", "test-service-tg", replace(random_uuid.test_service_tg_name.result, "-", "")), 0, 32)
  protocol = "HTTP"
  port = 80
  target_type = "ip"
  vpc_id = aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_cloudwatch_log_group" "test_log_group" {
  name = "ecs-service-test"
}

resource "aws_ecs_task_definition" "test_task_definition" {
  family = "test_task_definition"
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = 256
  memory = 512
  execution_role_arn = data.aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([
    {
      name = "hello-world"
      image = "tutum/hello-world"
      essential = true
      networkMode = "awsvpc"
      portMappings = [
        {
          containerPort = 80
        }
      ],
      logConfiguration: {
        logDriver: "awslogs",
        options: {
          awslogs-group: aws_cloudwatch_log_group.test_log_group.name,
          awslogs-region: "eu-west-1",
          awslogs-stream-prefix: aws_cloudwatch_log_group.test_log_group.name
        }
      },
    }
  ])
}

resource "aws_ecs_service" "test_service" {
  name = "test_service"
  cluster = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.test_task_definition.arn
  desired_count = 2
  launch_type = "FARGATE"

  load_balancer {
    target_group_arn = aws_alb_target_group.test_service.arn
    container_name = "hello-world"
    container_port = 80
  }

  network_configuration {
    subnets = aws_subnet.app-subnets.*.id
    security_groups = [aws_security_group.app.id]
  }
}

data "aws_cloudfront_cache_policy" "managedCachingOptimized"{
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "managedAllViewer"{
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "main" {
  enabled = true
  price_class = "PriceClass_100"
  default_cache_behavior {

    allowed_methods = ["GET","HEAD"]
    cached_methods = ["GET","HEAD"]
    cache_policy_id = data.aws_cloudfront_cache_policy.managedCachingOptimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.managedAllViewer.id

    target_origin_id = aws_alb.dmz-lb.name
    viewer_protocol_policy = "redirect-to-https"
  }
  origin {
    domain_name = aws_alb.dmz-lb.dns_name
    origin_id = aws_alb.dmz-lb.name

    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = ["SSLv3"]
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert-us-east-1.arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
}