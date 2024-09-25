# Outputs
output "subnet_name" {
  value = azurerm_subnet.public.name
}

output "virtual_network_name" {
  value = azurerm_virtual_network.main.name
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "location" {
  value = azurerm_resource_group.main.location
}