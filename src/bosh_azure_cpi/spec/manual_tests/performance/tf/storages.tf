resource "azurerm_storage_account" "bosh-default-storage" {
  name                     = "${module.namings.bosh-default-storage-name}"
  resource_group_name      = "${azurerm_resource_group.rg.name}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  location                 = "${var.location}"
  depends_on               = ["azurerm_resource_group.rg"]

  tags {
    environment = "${module.namings.environment-tag}"
  }
}
