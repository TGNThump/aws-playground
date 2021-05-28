variable "az-subnet-mapping" {
  type = list(object({
    name: string
    az: string
    cidr: string
  }))
  description = "Lists the subnets to be created in their respective AZ."

  default = [
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

variable "region" {
  description = "AWS Region"
  type = string
}

variable "cidr" {
  description = "CIDR block to assign to the VPC"
  type        = string
}