resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "apps" {
  name                 = "container-apps"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, 4, 0)]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "endpoints" {
  name                              = "private-endpoints"
  resource_group_name               = azurerm_resource_group.rg.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = [cidrsubnet(var.vnet_address_space, 4, 1)]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "jumpbox" {
  name                            = "jumpbox"
  resource_group_name             = azurerm_resource_group.rg.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = [cidrsubnet(var.vnet_address_space, 4, 2)]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space, 4, 3)]
}

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "main" {
  name                = "nat-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "apps" {
  subnet_id      = azurerm_subnet.apps.id
  nat_gateway_id = azurerm_nat_gateway.main.id
  depends_on     = [azurerm_nat_gateway_public_ip_association.main]
}

resource "azurerm_subnet_nat_gateway_association" "jumpbox" {
  subnet_id      = azurerm_subnet.jumpbox.id
  nat_gateway_id = azurerm_nat_gateway.main.id
  depends_on     = [azurerm_nat_gateway_public_ip_association.main]
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "acr-vnet"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pe-acr-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "acr"
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }
}

resource "azurerm_private_dns_zone" "apps" {
  name                = "privatelink.${azurerm_resource_group.rg.location}.azurecontainerapps.io"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "apps" {
  name                  = "apps-vnet"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.apps.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "apps" {
  name                = "pe-apps-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "apps"
    private_connection_resource_id = azurerm_container_app_environment.env.id
    subresource_names              = ["managedEnvironments"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "apps"
    private_dns_zone_ids = [azurerm_private_dns_zone.apps.id]
  }
}