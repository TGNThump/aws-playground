output "az-subnet-id-mapping" {
  description = "maps subnet name and AWS subnet ID"
  value       = zipmap(aws_subnet.main.*.tags.Name, aws_subnet.main.*.id)
}

output "vpc-id" {
  description = "ID of the generated vpc"
  value       = aws_vpc.main.id
}