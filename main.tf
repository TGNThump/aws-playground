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

data "cloudflare_zones" "zones" {
  filter {
    name = "pilgrim.me.uk"
    status = "active"
    paused = false
  }
}

resource "cloudflare_record" "ns-record" {
  count = length(aws_route53_zone.main.name_servers)

  name = "aws.pilgrim.me.uk"
  value = aws_route53_zone.main.name_servers[count.index]
  type = "NS"
  ttl = 30
  zone_id = data.cloudflare_zones.zones[0].id
}

resource "aws_route53_zone" "main" {
  name = "aws.pilgrim.me.uk"
}

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