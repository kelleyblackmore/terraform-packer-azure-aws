variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name tag for the VPC"
  type        = string
  default     = "packer-vpc"
}

variable "igw_name" {
  description = "Name tag for the Internet Gateway"
  type        = string
  default     = "packer-gateway"
}

variable "subnet_cidr_block" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_name" {
  description = "Name tag for the subnet"
  type        = string
  default     = "packer-public-subnet"
}

variable "route_table_name" {
  description = "Name tag for the route table"
  type        = string
  default     = "packer-public-route-table"
}

variable "security_group_name" {
  description = "Name tag for the security group"
  type        = string
  default     = "packer-ssh-sg"
}