resource "azurerm_user_assigned_identity" "default_identity" {
  resource_group_name  = "${azurerm_resource_group.azure_default_rg.name}"
  location             = "${var.location}"
  name                 = "${var.env_name}-default"

  # wait for server replication before attempting role assignment creation
  provisioner "local-exec" {
    command = "sleep 180"
  }
}

resource "azurerm_role_assignment" "assign_default_identity" {
  scope                = "${azurerm_resource_group.azure_default_rg.id}"
  role_definition_name = "Contributor"
  principal_id         = "${azurerm_user_assigned_identity.default_identity.principal_id}"
}

resource "azurerm_user_assigned_identity" "identity" {
  resource_group_name  = "${azurerm_resource_group.azure_default_rg.name}"
  location             = "${var.location}"
  name                 = "${var.env_name}"

  # wait for server replication before attempting role assignment creation
  provisioner "local-exec" {
    command = "sleep 180"
  }
}

resource "azurerm_role_assignment" "assign_identity" {
  scope                = "${azurerm_resource_group.azure_default_rg.id}"
  role_definition_name = "Contributor"
  principal_id         = "${azurerm_user_assigned_identity.identity.principal_id}"
}

output "default_user_assigned_identity_name" {
  value = "${azurerm_user_assigned_identity.default_identity.name}"
}

output "user_assigned_identity_name" {
  value = "${azurerm_user_assigned_identity.identity.name}"
}
