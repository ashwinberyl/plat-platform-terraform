variable "name" {
  description = "Name prefix for every resource, for example plat."
  type        = string
  default     = "plat"
}

variable "cidr_block" {
  type    = string
  default = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones, in order."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ, same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs needs exactly one CIDR for each entry in azs."
  }
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ, same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs needs exactly one CIDR for each entry in azs."
  }
}

variable "enable_nat" {
  description = "Create one NAT gateway (in the first AZ) and route private subnets through it. Costs money every hour."
  type        = bool
  default     = false
}

variable "gateway_endpoints" {
  description = "Free gateway endpoints to attach to the private route table. Supported: s3, dynamodb."
  type        = set(string)
  default     = ["s3", "dynamodb"]

  validation {
    condition     = alltrue([for e in var.gateway_endpoints : contains(["s3", "dynamodb"], e)])
    error_message = "gateway_endpoints may only contain s3 and dynamodb."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
