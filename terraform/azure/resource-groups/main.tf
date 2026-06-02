provider "azurerm" {
  {{block_to_replace_cred}}

  features {}
  skip_provider_registration = true
}

resource "azurerm_resource_group" "main" {
  location = var.location
  name     = var.resource_group_name
  tags     = var.tags
}