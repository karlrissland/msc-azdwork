output "AZURE_RESOURCE_GROUP" {
  value = azurerm_resource_group.rg.name
}

output "AZURE_LOCATION" {
  value = azurerm_resource_group.rg.location
}

output "AZURE_CONTAINER_REGISTRY_NAME" {
  value = azurerm_container_registry.acr.name
}

output "AZURE_CONTAINER_REGISTRY_ENDPOINT" {
  value = azurerm_container_registry.acr.login_server
}

output "AZURE_CONTAINER_APP_ENVIRONMENT_NAME" {
  value = azurerm_container_app_environment.env.name
}

output "SERVICE_WEB_NAME" {
  value = azurerm_container_app.web.name
}

output "SERVICE_WEB_IMAGE" {
  value = "${azurerm_container_registry.acr.login_server}/web:latest"
}

output "SERVICE_WEB_URI" {
  value = "https://${azurerm_container_app.web.ingress[0].fqdn}"
}

output "AZURE_JUMPBOX_NAME" {
  value = azurerm_linux_virtual_machine.jumpbox.name
}

output "AZURE_JUMPBOX_ID" {
  value = azurerm_linux_virtual_machine.jumpbox.id
}

output "AZURE_JUMPBOX_PRIVATE_IP" {
  value = azurerm_network_interface.jumpbox.private_ip_address
}

output "AZURE_JUMPBOX_ADMIN_USERNAME" {
  value = var.jumpbox_admin_username
}

output "AZURE_WINDOWS_DESKTOP_NAME" {
  value = azurerm_windows_virtual_machine.desktop.name
}

output "AZURE_WINDOWS_DESKTOP_ID" {
  value = azurerm_windows_virtual_machine.desktop.id
}

output "AZURE_WINDOWS_DESKTOP_PRIVATE_IP" {
  value = azurerm_network_interface.windows_desktop.private_ip_address
}

output "AZURE_WINDOWS_DESKTOP_ADMIN_USERNAME" {
  value = var.jumpbox_admin_username
}

output "AZURE_BASTION_NAME" {
  value = azurerm_bastion_host.main.name
}

output "AZURE_VNET_NAME" {
  value = azurerm_virtual_network.main.name
}
