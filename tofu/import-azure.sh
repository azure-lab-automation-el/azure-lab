#!/usr/bin/env bash
# Import existing lab resources into throwaway local state so `tofu plan` reports REAL drift
# (no-op = in sync, ~ = drift, + = missing). Read-only against Azure; missing resources are
# skipped and simply show up as "+ create" in the plan. Names only - the subscription ID
# comes from ARM_SUBSCRIPTION_ID at runtime and never enters git.
set -uo pipefail
cd "$(dirname "$0")/stacks/azure"
SUB=${ARM_SUBSCRIPTION_ID:?required}; RG=${RG_NAME:-rg-learning-monitoring}; P=${PREFIX:-esther}
MEDIA=${MEDIA_ACCOUNT:-estherlabmedia8c8c3c92}
imp() { tofu import -input=false -no-color "$1" "$2" >/dev/null 2>&1 \
  && echo "imported $1" || echo "skip $1 (absent live -> plan shows + create)"; }
B=/subscriptions/$SUB/resourceGroups/$RG/providers
imp module.lab.azurerm_resource_group.lab                       "$B/resourceGroups/$RG"
imp module.lab.azurerm_virtual_network.hub                      "$B/Microsoft.Network/virtualNetworks/$P-lab-vnet"
imp module.lab.azurerm_subnet.hub                               "$B/Microsoft.Network/virtualNetworks/$P-lab-vnet/subnets/$P-lab-subnet"
imp module.lab.azurerm_network_security_group.hub               "$B/Microsoft.Network/networkSecurityGroups/$P-lab-nsg"
imp module.lab.azurerm_subnet_network_security_group_association.hub "$B/Microsoft.Network/virtualNetworks/$P-lab-vnet/subnets/$P-lab-subnet"
imp module.lab.azurerm_virtual_network_dns_servers.hub          "$B/Microsoft.Network/virtualNetworks/$P-lab-vnet"
imp module.lab.azurerm_virtual_network.spoke[0]                 "$B/Microsoft.Network/virtualNetworks/$P-se-vnet"
imp module.lab.azurerm_subnet.spoke[0]                          "$B/Microsoft.Network/virtualNetworks/$P-se-vnet/subnets/$P-se-subnet"
imp module.lab.azurerm_virtual_network_peering.hub_to_spoke[0]  "$B/Microsoft.Network/virtualNetworks/$P-lab-vnet/virtualNetworkPeerings/hub-to-se"
imp module.lab.azurerm_virtual_network_peering.spoke_to_hub[0]  "$B/Microsoft.Network/virtualNetworks/$P-se-vnet/virtualNetworkPeerings/se-to-hub"
imp module.lab.azurerm_virtual_network_dns_servers.spoke[0]     "$B/Microsoft.Network/virtualNetworks/$P-se-vnet"
imp module.lab.azurerm_storage_account.media                    "$B/Microsoft.Storage/storageAccounts/$MEDIA"
imp module.lab.azurerm_storage_container.media                  "https://$MEDIA.blob.core.windows.net/containers/media"
imp module.lab.azurerm_network_interface.dc                     "$B/Microsoft.Network/networkInterfaces/$P-dc-01-nic"
imp module.lab.azurerm_network_interface.esther                 "$B/Microsoft.Network/networkInterfaces/$P-adaxes-01-nic"
imp module.lab.azurerm_network_interface.linux[0]               "$B/Microsoft.Network/networkInterfaces/$P-linux-01-se-nic"
imp module.lab.azurerm_windows_virtual_machine.dc               "$B/Microsoft.Compute/virtualMachines/$P-dc-01"
imp module.lab.azurerm_windows_virtual_machine.esther           "$B/Microsoft.Compute/virtualMachines/$P-adaxes-01"
imp module.lab.azurerm_linux_virtual_machine.linux[0]           "$B/Microsoft.Compute/virtualMachines/$P-linux-01"
echo IMPORT_SWEEP_DONE
