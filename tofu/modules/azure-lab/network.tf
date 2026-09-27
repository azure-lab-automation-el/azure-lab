resource "azurerm_resource_group" "lab" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_virtual_network" "hub" {
  name                = "${var.prefix}-lab-vnet"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [var.hub_cidr]
}

resource "azurerm_subnet" "hub" {
  name                            = "${var.prefix}-lab-subnet"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = [var.hub_subnet_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "hub" {
  name                = "${var.prefix}-lab-nsg"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
}

resource "azurerm_subnet_network_security_group_association" "hub" {
  subnet_id                 = azurerm_subnet.hub.id
  network_security_group_id = azurerm_network_security_group.hub.id
}

# Lab DNS: all hub VMs resolve esther.lab through the DC.
resource "azurerm_virtual_network_dns_servers" "hub" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = [var.dc_private_ip]
}

# ---- Linux spoke (separate region) ----
resource "azurerm_virtual_network" "spoke" {
  count               = var.enable_linux_spoke ? 1 : 0
  name                = "${var.prefix}-se-vnet"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location_linux
  address_space       = [var.spoke_cidr]
}

resource "azurerm_subnet" "spoke" {
  count                = var.enable_linux_spoke ? 1 : 0
  name                 = "${var.prefix}-se-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.spoke[0].name
  address_prefixes     = [var.spoke_subnet_cidr]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                     = var.enable_linux_spoke ? 1 : 0
  name                      = "hub-to-se"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke[0].id
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count                     = var.enable_linux_spoke ? 1 : 0
  name                      = "se-to-hub"
  resource_group_name       = azurerm_resource_group.lab.name
  virtual_network_name      = azurerm_virtual_network.spoke[0].name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
}

resource "azurerm_virtual_network_dns_servers" "spoke" {
  count              = var.enable_linux_spoke ? 1 : 0
  virtual_network_id = azurerm_virtual_network.spoke[0].id
  dns_servers        = [var.dc_private_ip]
}

# Install-media cache (idempotent staging target for the rebuild engine).
resource "azurerm_storage_account" "media" {
  name                            = var.media_account_name
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "media" {
  name                  = "media"
  storage_account_id    = azurerm_storage_account.media.id
  container_access_type = "private"
}
