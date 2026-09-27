resource "azurerm_network_interface" "linux" {
  count               = var.enable_linux_spoke ? 1 : 0
  name                = "${var.prefix}-linux-01-se-nic"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location_linux
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.spoke[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.linux_private_ip
  }
}

resource "azurerm_linux_virtual_machine" "linux" {
  count                 = var.enable_linux_spoke ? 1 : 0
  name                  = "${var.prefix}-linux-01"
  resource_group_name   = azurerm_resource_group.lab.name
  location              = var.location_linux
  size                  = var.linux_size
  admin_username        = var.linux_admin_username
  secure_boot_enabled   = true
  vtpm_enabled          = true
  network_interface_ids = [azurerm_network_interface.linux[0].id]
  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = var.linux_ssh_public_key
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  os_disk {
    name                 = "${var.prefix}-linux-01-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 32
  }
}
