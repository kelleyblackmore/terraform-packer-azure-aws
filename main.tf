# AWS Module
module "aws_infrastructure" {
  source = "./modules/aws"

  aws_region = var.aws_region

  # Optional: Override defaults if needed
  # vpc_cidr_block = "10.0.0.0/16"
  # vpc_name = "custom-vpc-name"
  # ...
}

# Azure Module
module "azure_infrastructure" {
  source = "./modules/azure"

  location = var.azure_location

  # Optional: Override defaults if needed
  # resource_group_name = "custom-rg-name"
  # vnet_address_space = "10.1.0.0/16"
  # ...
}

# Outputs from modules
output "aws_subnet_id" {
  value = module.aws_infrastructure.subnet_id
}

output "aws_security_group_id" {
  value = module.aws_infrastructure.security_group_id
}

output "aws_vpc_id" {
  value = module.aws_infrastructure.vpc_id
}

output "azure_subnet_name" {
  value = module.azure_infrastructure.subnet_name
}

output "azure_virtual_network_name" {
  value = module.azure_infrastructure.virtual_network_name
}

output "azure_resource_group_name" {
  value = module.azure_infrastructure.resource_group_name
}

output "azure_location" {
  value = module.azure_infrastructure.location
}