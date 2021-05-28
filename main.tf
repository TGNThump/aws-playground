terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "eu-west-1"
}

module "networking" {
  source = "./networking"
  cidr = "10.0.0.0/16"

  az-subnet-mapping = [
    {
      name = "dmz-eu-west-1a"
      az   = "eu-west-1a"
      cidr = "10.0.0.0/24"
    },
    {
      name = "dmz-eu-west-1b"
      az   = "eu-west-1b"
      cidr = "10.0.1.0/24"
    },
    {
      name = "dmz-eu-west-1c"
      az   = "eu-west-1c"
      cidr = "10.0.2.0/24"
    },
  ]
}