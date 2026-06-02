output "resource_group_id" {
  description = "The ID of the created Azure Resource Group."
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "The Azure region of the created Resource Group."
  value       = azurerm_resource_group.main.location
}

output "resource_group_name" {
  description = "The name of the created Azure Resource Group."
  value       = azurerm_resource_group.main.name
}