locals {
  win_common = {
    size                = var.dc_size
    admin_username      = var.admin_username
    license_type        = "None"
    secure_boot_enabled = true
    vtpm_enabled        = true
  }
}

resource "azurerm_network_interface" "dc" {
  name                = "${var.prefix}-dc-01-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.hub.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.dc_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                  = "${var.prefix}-dc-01"
  computer_name         = "ESTHERDC01"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  size                  = local.win_common.size
  admin_username        = local.win_common.admin_username
  admin_password        = var.admin_password
  license_type          = local.win_common.license_type
  secure_boot_enabled   = local.win_common.secure_boot_enabled
  vtpm_enabled          = local.win_common.vtpm_enabled
  network_interface_ids = [azurerm_network_interface.dc.id]
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-core-smalldisk-g2"
    version   = "latest"
  }
  os_disk {
    name                 = "${var.prefix}-dc-01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 32
  }
}

resource "azurerm_network_interface" "esther" {
  name                = "${var.prefix}-adaxes-01-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.hub.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.esther_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "esther" {
  name                  = "${var.prefix}-adaxes-01"
  computer_name         = "ESTHERLAB"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = azurerm_resource_group.lab.location
  size                  = var.esther_size
  admin_username        = local.win_common.admin_username
  admin_password        = var.admin_password
  license_type          = local.win_common.license_type
  secure_boot_enabled   = local.win_common.secure_boot_enabled
  vtpm_enabled          = local.win_common.vtpm_enabled
  network_interface_ids = [azurerm_network_interface.esther.id]
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition-smalldisk"
    version   = "latest"
  }
  os_disk {
    name                 = "${var.prefix}-adaxes-01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }
}
