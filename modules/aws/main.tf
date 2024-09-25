# AWS Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Data source to get your public IP
data "http" "my_ip" {
  url = "http://checkip.amazonaws.com/"
}

# Extract the IP address
locals {
  my_public_ip = chomp(data.http.my_ip.response_body)
}

# Create a new VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.igw_name
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true  # Enable public IP assignment

  tags = {
    Name = var.subnet_name
  }
}

# Create a route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = var.route_table_name
  }
}

# Create a default route to the Internet Gateway
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

# Associate the route table with the public subnet
resource "aws_route_table_association" "public_subnet" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a security group that allows SSH access from your IP
resource "aws_security_group" "ssh" {
  name        = var.security_group_name
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description  = "SSH from my IP"
    from_port    = 22
    to_port      = 22
    protocol     = "tcp"
    cidr_blocks  = ["${local.my_public_ip}/32"]  # Use the corrected IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.security_group_name
  }
}

