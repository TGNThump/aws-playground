terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
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

resource "aws_subnet" "dmz-eu-west-1a" {
  cidr_block              = "10.0.0.0/24"
  vpc_id                  = aws_vpc.main.id
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-1a"
  tags = {
    Name = "dmz-eu-west-1a"
  }
}

resource "aws_route_table" "dmz" {
  vpc_id = aws_vpc.main.id

  route {
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "dmz-eu-west-1a" {
  vpc_id = aws_vpc.main.id
  route_table_id = aws_route_table.dmz.id
  subnet_id = aws_subnet.dmz-eu-west-1a.id
}

resource "aws_subnet" "app-eu-west-1a" {
  cidr_block              = "10.1.0.0/24"
  vpc_id                  = aws_vpc.main.id
  availability_zone       = "eu-west-1a"
  tags = {
    Name = "app-eu-west-1a"
  }
}

resource "aws_eip" "app-eu-west-1a-nat" {

}

resource "aws_nat_gateway" "app-eu-west-1a" {
  allocation_id = aws_eip.app-eu-west-1a-nat.id
  subnet_id = aws_subnet.app-eu-west-1a.id
  tags = {
    Name = "app-eu-west-1a"
  }
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.app-eu-west-1a.id
  }
}

resource "aws_route_table_association" "app-eu-west-1a" {
  vpc_id = aws_vpc.main.id
  route_table_id = aws_route_table.app.id
  subnet_id = aws_subnet.app-eu-west-1a.id
}
