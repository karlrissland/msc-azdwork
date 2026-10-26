resource "azurerm_network_security_group" "jumpbox" {
  name                = "nsg-jumpbox-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags

  security_rule {
    name                       = "AllowBastionSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = azurerm_subnet.bastion.address_prefixes[0]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowBastionRDP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = azurerm_subnet.bastion.address_prefixes[0]
    destination_address_prefix = azurerm_network_interface.windows_desktop.private_ip_address
  }

  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "jumpbox" {
  subnet_id                 = azurerm_subnet.jumpbox.id
  network_security_group_id = azurerm_network_security_group.jumpbox.id
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "nic-jumpbox-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags

  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.jumpbox.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                            = "vm-build-${local.resource_token}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = var.jumpbox_vm_size
  admin_username                  = var.jumpbox_admin_username
  admin_password                  = var.jumpbox_admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.jumpbox.id]
  tags                            = local.tags

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  custom_data = base64encode(join("\n", ["#cloud-config", yamlencode({
    ssh_pwauth     = true
    package_update = true
    packages       = ["docker.io", "git", "curl", "ca-certificates", "jq", "unzip"]
    runcmd = [
      ["systemctl", "enable", "--now", "docker"],
      ["usermod", "-aG", "docker", var.jumpbox_admin_username],
      ["bash", "-c", "set -euo pipefail; curl -fsSL https://aka.ms/InstallAzureCLIDeb -o /tmp/install-azure-cli.sh; bash /tmp/install-azure-cli.sh; rm /tmp/install-azure-cli.sh"],
    ]
  })]))

  depends_on = [
    azurerm_subnet_nat_gateway_association.jumpbox,
    azurerm_subnet_network_security_group_association.jumpbox,
  ]
}

resource "azurerm_role_assignment" "jumpbox_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_linux_virtual_machine.jumpbox.identity[0].principal_id
}

resource "azurerm_network_interface" "windows_desktop" {
  name                = "nic-desktop-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = local.tags

  ip_configuration {
    name                          = "private"
    subnet_id                     = azurerm_subnet.jumpbox.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "desktop" {
  name                  = "vm-desktop-${local.resource_token}"
  computer_name         = "win-${local.resource_token}"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.windows_desktop_vm_size
  admin_username        = var.jumpbox_admin_username
  admin_password        = var.jumpbox_admin_password
  license_type          = "Windows_Client"
  secure_boot_enabled   = true
  vtpm_enabled          = true
  network_interface_ids = [azurerm_network_interface.windows_desktop.id]
  tags                  = local.tags

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-25h2-ent"
    version   = "latest"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.jumpbox,
    azurerm_subnet_network_security_group_association.jumpbox,
  ]
}

resource "azurerm_virtual_machine_extension" "windows_desktop_setup" {
  name                       = "desktop-tools"
  virtual_machine_id         = azurerm_windows_virtual_machine.desktop.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(file("${path.module}/../scripts/setup-windows-desktop.ps1"), "UTF-16LE")}"
  })

  tags = local.tags
}

resource "azurerm_role_assignment" "windows_desktop_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_windows_virtual_machine.desktop.identity[0].principal_id
}

resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_bastion_host" "main" {
  name                = "bas-${local.resource_token}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  tunneling_enabled   = true
  tags                = local.tags

  ip_configuration {
    name                 = "bastion"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}