# Outputs
output "subnet_id" {
  value = aws_subnet.public.id
}

output "security_group_id" {
  value = aws_security_group.ssh.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}