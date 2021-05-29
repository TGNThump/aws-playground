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

resource "aws_eip" "app-nat-eips" {
  count = length(var.availability_zones)

  tags = {
    Name = "app-${var.availability_zones[count.index].id}-nat"
  }
}

resource "aws_nat_gateway" "app-nat-gateways" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.app-nat-eips[count.index].id
  subnet_id = aws_subnet.app-subnets[count.index].id
  tags = {
    Name = "app-${var.availability_zones[count.index].id}"
  }
}

resource "aws_route_table" "app-route-tables" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.app-nat-gateways[count.index].id
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

resource "aws_security_group" "dmz" {
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
}

resource "aws_security_group" "app" {
  name = "APP"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "APP"
  }

  ingress {
    from_port = 80
    protocol = "TCP"
    to_port = 80
    security_groups = [aws_security_group.dmz.id]
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

resource "aws_alb" "dmz-lb" {
  name = "DMZ-ALB"
  security_groups = [aws_security_group.dmz.id]
  subnets = aws_subnet.dmz-subnets.*.id

  tags = {
    Name = "DMZ-ALB"
  }
}

resource "aws_route53_record" "dmz-lb-a" {
  name = aws_route53_zone.main.name
  type = "A"
  zone_id = aws_route53_zone.main.id
  alias {
    evaluate_target_health = false
    name = aws_alb.dmz-lb.dns_name
    zone_id = aws_alb.dmz-lb.zone_id
  }
}