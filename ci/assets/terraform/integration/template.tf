# Variables
variable "azure_client_id" {}
variable "azure_client_secret" {}
variable "azure_subscription_id" {}
variable "azure_tenant_id" {}
variable "location" {
  default = "eastus2"
}
variable "env_name" {}
variable "azure_environment" {}
variable "environments" {
  type = map(string)
  default = {
    AzureCloud        = "public"
    AzureUSGovernment = "usgovernment"
    AzureGermanCloud  = "german"
    AzureChinaCloud   = "china"
  }
}
variable "resource_group_prefix" {
  type    = string
  default = ""
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  environment     = var.environments[var.azure_environment]
  features {}
}

# Create a default resource group
resource "azurerm_resource_group" "azure_default_rg" {
  name     = "${var.resource_group_prefix}${var.env_name}-default-rg"
  location = var.location
}

# Create a virtual network in the azure_default_rg resource group
resource "azurerm_virtual_network" "azure_bosh_network_in_default_rg" {
  name                = "azure_bosh_network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_default_rg.name
}
resource "azurerm_subnet" "azure_subnet_1_in_default_rg" {
  name                 = "azure_subnet_1"
  resource_group_name  = azurerm_resource_group.azure_default_rg.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network_in_default_rg.name
  address_prefixes       = ["10.0.0.0/24"]
}
resource "azurerm_subnet" "azure_subnet_2_in_default_rg" {
  name                 = "azure_subnet_2"
  resource_group_name  = azurerm_resource_group.azure_default_rg.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network_in_default_rg.name
  address_prefixes       = ["10.0.1.0/24"]
}
resource "azurerm_subnet" "azure_subnet_appgw_in_default_rg" {
  name                 = "azure_subnet_3"
  resource_group_name  = azurerm_resource_group.azure_default_rg.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network_in_default_rg.name
  address_prefixes       = ["10.0.2.0/24"]
}

# Create a default Storage Account in the azure_default_rg resouce group
resource "azurerm_storage_account" "azure_bosh_sa" {
  name                     = replace(var.env_name, "-", "")
  resource_group_name      = azurerm_resource_group.azure_default_rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = true
}
# Create a Storage Container for the disks
resource "azurerm_storage_container" "azure_bosh_container" {
  name                  = "bosh"
  storage_account_name  = azurerm_storage_account.azure_bosh_sa.name
  container_access_type = "private"
}
# Create a Storage Container for the stemcells
resource "azurerm_storage_container" "azure_stemcell_container" {
  name                  = "stemcell"
  storage_account_name  = azurerm_storage_account.azure_bosh_sa.name
  container_access_type = "blob"
}
# Create a Storage Table for the metadata of the stemcells
resource "azurerm_storage_table" "azure_stemcells_table" {
  name                  = "stemcells"
  storage_account_name  = azurerm_storage_account.azure_bosh_sa.name
}

# Create an extra Storage Account in the azure_default_rg resouce group
resource "azurerm_storage_account" "azure_bosh_sa_extra" {
  name                     = format("%sx", replace(var.env_name, "-", ""))
  resource_group_name      = azurerm_resource_group.azure_default_rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = true
}
# Create a Storage Container for the disks
resource "azurerm_storage_container" "azure_bosh_container_extra" {
  name                  = "bosh"
  storage_account_name  = azurerm_storage_account.azure_bosh_sa_extra.name
  container_access_type = "private"
}
# Create a Storage Container for the stemcells
resource "azurerm_storage_container" "azure_stemcell_container_extra" {
  name                  = "stemcell"
  storage_account_name  = azurerm_storage_account.azure_bosh_sa_extra.name
  container_access_type = "private"
}

# Create a Network Securtiy Group
resource "azurerm_network_security_group" "azure_bosh_nsg_in_default_rg" {
  name                = "azure_bosh_nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_default_rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "bosh-agent"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6868"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "bosh-director"
    priority                   = 202
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "25555"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "dns"
    priority                   = 203
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP Address for Integration Test
resource "azurerm_public_ip" "azure_ip_integration_in_default_rg" {
  name                         = "azure_ip_integration"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.azure_default_rg.name
  allocation_method            = "Static"
}

resource "azurerm_application_security_group" "azure_asg" {
  name                         = "azure_asg"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.azure_default_rg.name
}

# Public IP Address for Application Gateway
resource "azurerm_public_ip" "azure_ip_application_gateway" {
  name                         = "azure_ip_application_gateway"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.azure_default_rg.name
  allocation_method            = "Dynamic"
}

resource "azurerm_application_gateway" "azure_application_gateway" {
  name                = "azure_application_gateway"
  resource_group_name = azurerm_resource_group.azure_default_rg.name
  location            = var.location

  sku {
    name     = "Standard_Medium"
    tier     = "Standard"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.azure_subnet_appgw_in_default_rg.id
  }

  frontend_port {
    name = "appGWFEHttp"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appGatewayFrontendIP"
    public_ip_address_id = azurerm_public_ip.azure_ip_application_gateway.id
  }

  backend_address_pool {
    name = "appGatewayBackendPool"
  }

  backend_http_settings {
    name                  = "appGWBEHttpSettings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
  }

  http_listener {
    name                           = "appGatewayHttpListener"
    frontend_ip_configuration_name = "appGatewayFrontendIP"
    frontend_port_name             = "appGWFEHttp"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "HTTPrule"
    rule_type                  = "Basic"
    http_listener_name         = "appGatewayHttpListener"
    backend_address_pool_name  = "appGatewayBackendPool"
    backend_http_settings_name = "appGWBEHttpSettings"
  }
}

# Create an additional resource group
resource "azurerm_resource_group" "azure_additional_rg" {
  name     = "${var.resource_group_prefix}${var.env_name}-additional-rg"
  location = var.location
}

# Create a virtual network in the azure_additional_rg resource group
resource "azurerm_virtual_network" "azure_bosh_network_in_additional_rg" {
  name                = "azure_bosh_network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_additional_rg.name
}
resource "azurerm_subnet" "azure_subnet_1_in_additional_rg" {
  name                 = "azure_subnet_1"
  resource_group_name  = azurerm_resource_group.azure_additional_rg.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network_in_additional_rg.name
  address_prefixes       = ["10.0.0.0/24"]
}
resource "azurerm_subnet" "azure_subnet_2_in_additional_rg" {
  name                 = "azure_subnet_2"
  resource_group_name  = azurerm_resource_group.azure_additional_rg.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network_in_additional_rg.name
  address_prefixes       = ["10.0.1.0/24"]
}

# Create a Network Securtiy Group
resource "azurerm_network_security_group" "azure_bosh_nsg_in_additional_rg" {
  name                = "azure_bosh_nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_additional_rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "bosh-agent"
    priority                   = 201
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6868"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "bosh-director"
    priority                   = 202
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "25555"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "dns"
    priority                   = 203
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP Address for Integration Test
resource "azurerm_public_ip" "azure_ip_integration_in_additional_rg" {
  name                         = "azure_ip_integration"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.azure_additional_rg.name
  allocation_method            = "Static"
}

output "environment" {
  value = var.azure_environment
}
output "location" {
  value = var.location
}
output "default_resource_group_name" {
  value = azurerm_resource_group.azure_default_rg.name
}
output "additional_resource_group_name" {
  value = azurerm_resource_group.azure_additional_rg.name
}
output "storage_account_name" {
  value = azurerm_storage_account.azure_bosh_sa.name
}
output "extra_storage_account_name" {
  value = azurerm_storage_account.azure_bosh_sa_extra.name
}
output "default_security_group" {
  value = azurerm_network_security_group.azure_bosh_nsg_in_default_rg.name
}
output "vnet_name" {
  value = azurerm_virtual_network.azure_bosh_network_in_default_rg.name
}
output "subnet_1_name" {
  value = azurerm_subnet.azure_subnet_1_in_default_rg.name
}
output "subnet_2_name" {
  value = azurerm_subnet.azure_subnet_2_in_default_rg.name
}
output "public_ip_in_default_rg" {
  value = azurerm_public_ip.azure_ip_integration_in_default_rg.ip_address
}
output "public_ip_in_additional_rg" {
  value = azurerm_public_ip.azure_ip_integration_in_additional_rg.ip_address
}
output "asg_name" {
  value = azurerm_application_security_group.azure_asg.name
}
output "application_gateway_name" {
  value = azurerm_application_gateway.azure_application_gateway.name
}
