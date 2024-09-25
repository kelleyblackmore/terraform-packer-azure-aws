# Azure Provider Configuration
provider "azurerm" {
  features {}
}

# Data source to get your public IP
data "http" "my_ip" {
  url = "http://checkip.amazonaws.com/"
}

# Extract the IP address
locals {
  my_public_ip = chomp(data.http.my_ip.response_body)
}

# Create a resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Create a virtual network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    Name = var.vnet_name
  }
}

# Create a subnet
resource "azurerm_subnet" "public" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Create a network security group
resource "azurerm_network_security_group" "ssh" {
  name                = var.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = ["${local.my_public_ip}/32"]
    destination_address_prefix = "*"
  }

  tags = {
    Name = var.nsg_name
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "ssh" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.ssh.id
}

