variable "region" {
  type    = string
  default = "us-east-1"
}

variable "enable_ec2" {
  description = "Create the plat-ec2 instance. A t3.micro costs about a cent an hour."
  type        = bool
  default     = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "enable_ssm_endpoints" {
  description = "Interface endpoints so Session Manager works without a NAT gateway. Billed per hour per endpoint. Use this OR turn the NAT on in 20-network."
  type        = bool
  default     = false
}

variable "mount_efs" {
  description = "Mount plat-efs through the plat-ml-ap access point at /mnt/ml."
  type        = bool
  default     = true
}
