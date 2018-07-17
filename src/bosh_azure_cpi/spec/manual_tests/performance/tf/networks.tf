// Subnet for BOSH
resource "azurerm_virtual_network" "vnet" {
  name                = "${module.namings.vnet-name}"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  depends_on          = ["azurerm_resource_group.rg"]
  address_space       = ["${var.network_cidr}"]
}

resource "azurerm_subnet" "bosh-subnet" {
  name                 = "${module.namings.bosh-subnet-name}"
  resource_group_name  = "${azurerm_resource_group.rg.name}"
  depends_on           = ["azurerm_virtual_network.vnet"]
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  address_prefix       = "${cidrsubnet(var.network_cidr, 8, 0)}" //network_cidr = 10.0.0.0/16
}
