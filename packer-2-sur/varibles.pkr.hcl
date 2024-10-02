variable "aws_security_group_id" {
  description = "The ID of the AWS security group"
  type        = string
  default     = "sg-059c7b30031c81f0d"
}

variable "aws_subnet_id" {
  description = "The ID of the AWS subnet"
  type        = string
  default     = "subnet-085c6713c789edc91"
}

variable "aws_vpc_id" {
  description = "The ID of the AWS VPC"
  type        = string
  default     = "vpc-01a8230e50e13923b"
}
variable "root_volume_size" {
  description = "Size in GB of the root volume"
  type        = number
  default     = 20
}
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "ssh_username" {
  description = "The username for SSH"
  type        = string
  default     = "ec2-user"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "my-project"  # Replace with your project name
}

variable "instance_type" {
  description = "The instance type to use for the build"
  type        = string
  default     = "t3.medium"
}