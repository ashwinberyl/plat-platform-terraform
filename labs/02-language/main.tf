# Post 02 lab. Uses only the built-in terraform_data resource, so it needs no AWS account.
terraform {
  required_version = ">= 1.10"
}

variable "names" {
  type    = list(string)
  default = ["alpha", "bravo", "charlie"]
}

variable "subnets" {
  type = map(object({
    cidr   = string
    public = optional(bool, false)
  }))
  default = {
    a = { cidr = "10.0.0.0/24", public = true }
    b = { cidr = "10.0.1.0/24" }
    c = { cidr = "10.0.2.0/24" }
  }
}

locals {
  public_cidrs  = [for k, s in var.subnets : s.cidr if s.public]
  by_cidr       = { for k, s in var.subnets : s.cidr => k }
  subnet_names  = [for k in sort(keys(var.subnets)) : "plat-${k}"]
  private_count = length([for s in var.subnets : s if !s.public])
  tags          = merge({ project = "plat" }, { env = "dev" })
}

# Same list, two ways of addressing it.
resource "terraform_data" "by_count" {
  count = length(var.names)

  triggers_replace = var.names[count.index]
}

resource "terraform_data" "by_key" {
  for_each = toset(var.names)

  triggers_replace = each.key
}

output "by_count_addresses" {
  value = [for i, r in terraform_data.by_count : "terraform_data.by_count[${i}]"]
}

output "by_key_addresses" {
  value = [for k, r in terraform_data.by_key : "terraform_data.by_key[\"${k}\"]"]
}

output "locals_preview" {
  description = "Everything the locals compute, so `terraform plan` shows it and tflint sees them used."
  value       = {
    public_cidrs  = local.public_cidrs
    by_cidr       = local.by_cidr
    subnet_names  = local.subnet_names
    private_count = local.private_count
    tags          = local.tags
  }
}
