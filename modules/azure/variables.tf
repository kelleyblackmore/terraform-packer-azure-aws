variable "location" {
  description = "Azure location"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "packer-rg"
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "packer-vnet"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "packer-subnet"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "nsg_name" {
  description = "Name of the network security group"
  type        = string
  default     = "packer-nsg"
}