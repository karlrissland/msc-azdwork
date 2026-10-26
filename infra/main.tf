data "azurerm_client_config" "current" {}

locals {
  resource_token = substr(sha1("${data.azurerm_client_config.current.subscription_id}${var.environment_name}${var.location}"), 0, 8)
  tags           = { "azd-env-name" = var.environment_name }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.environment_name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags
}

resource "azurerm_container_registry" "acr" {
  name                          = "cr${local.resource_token}"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = azurerm_resource_group.rg.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  network_rule_bypass_option    = "None"
  tags                          = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_container_app_environment" "env" {
  name                     = "cae-${local.resource_token}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  infrastructure_subnet_id = azurerm_subnet.apps.id
  public_network_access    = "Disabled"
  tags                     = local.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 0
  }

  depends_on = [azurerm_subnet_nat_gateway_association.apps]
}

resource "azurerm_container_app" "web" {
  name                         = "ca-web-${local.resource_token}"
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = merge(local.tags, { "azd-service-name" = "web" })

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = "web"
      image  = var.image_placeholder
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_private_endpoint.acr,
    azurerm_private_endpoint.apps,
    azurerm_private_dns_zone_virtual_network_link.acr,
    azurerm_private_dns_zone_virtual_network_link.apps,
  ]

  # azd deploy owns the image (and revision suffix) after the first apply.
  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      template[0].revision_suffix,
    ]
  }
}
