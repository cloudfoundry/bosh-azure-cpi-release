resource "azurerm_resource_group" "rg" {
  name     = "${module.namings.resource-group-name}"
  location = "${var.location}"

  tags {
    environment = "${module.namings.environment-tag}"
  }
}
