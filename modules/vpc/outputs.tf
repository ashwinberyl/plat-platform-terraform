output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Map of AZ letter to subnet id, for example { a = subnet-..., b = subnet-... }."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "Map of AZ letter to subnet id."
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "nat_enabled" {
  value = var.enable_nat
}
