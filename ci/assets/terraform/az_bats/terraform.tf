# Variables
variable "azure_client_id" {}
variable "azure_client_secret" {}
variable "azure_subscription_id" {}
variable "azure_tenant_id" {}
variable "location" {
  default = "East US"
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
locals {
  bats_public_ip_sku = "Standard"
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
# Create a resource group
resource "azurerm_resource_group" "azure_rg_bosh" {
  name     = "${var.resource_group_prefix}${var.env_name}-rg"
  location = var.location
}
# Create a virtual network in the azure_rg_bosh resource group
resource "azurerm_virtual_network" "azure_bosh_network" {
  name                = "azure_bosh_network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_rg_bosh.name
}

resource "azurerm_subnet" "azure_bosh_subnet" {
  name                 = "azure_bosh_subnet"
  resource_group_name  = azurerm_resource_group.azure_rg_bosh.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "azure_bats_subnet" {
  name                 = "azure_bats_subnet"
  resource_group_name  = azurerm_resource_group.azure_rg_bosh.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network.name
  address_prefixes     = ["10.0.16.0/24"]
}

resource "azurerm_subnet" "azure_bats_subnet_2" {
  name                 = "azure_bats_subnet_2"
  resource_group_name  = azurerm_resource_group.azure_rg_bosh.name
  virtual_network_name = azurerm_virtual_network.azure_bosh_network.name
  address_prefixes     = ["10.0.17.0/24"]
}

# Create a Storage Account in the azure_rg_bosh resouce group
resource "azurerm_storage_account" "azure_bosh_sa" {
  name                            = replace(var.env_name, "-", "")
  resource_group_name             = azurerm_resource_group.azure_rg_bosh.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = true
}
# Create a Storage Container for the bosh director
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

# Create a Network Securtiy Group
resource "azurerm_network_security_group" "azure_bosh_nsg" {
  name                = "azure_bosh_nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_rg_bosh.name

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

# Public IP Address for bosh
resource "azurerm_public_ip" "azure_ip_bosh" {
  name                = "azure_ip_bosh"
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_rg_bosh.name
  allocation_method   = "Static"
}

# Public IP Address for BATS
resource "azurerm_public_ip" "azure_ip_bats" {
  name                = "azure_ip_bats"
  location            = var.location
  resource_group_name = azurerm_resource_group.azure_rg_bosh.name
  allocation_method   = "Static"
  sku                 = local.bats_public_ip_sku
}

output "external_ip" {
  value = azurerm_public_ip.azure_ip_bosh.ip_address
}
output "environment" {
  value = var.azure_environment
}
output "vnet_name" {
  value = azurerm_virtual_network.azure_bosh_network.name
}
output "subnet_name" {
  value = azurerm_subnet.azure_bosh_subnet.name
}
output "internal_ip" {
  value = cidrhost(azurerm_subnet.azure_bosh_subnet.address_prefix, 6)
}
output "resource_group_name" {
  value = azurerm_resource_group.azure_rg_bosh.name
}
output "storage_account_name" {
  value = azurerm_storage_account.azure_bosh_sa.name
}
output "security_group" {
  value = azurerm_network_security_group.azure_bosh_nsg.name
}
output "default_security_group" {
  value = azurerm_network_security_group.azure_bosh_nsg.name
}
output "internal_cidr" {
  value = azurerm_subnet.azure_bosh_subnet.address_prefix
}
output "internal_gw" {
  value = cidrhost(azurerm_subnet.azure_bosh_subnet.address_prefix, 1)
}
output "reserved_range" {
  value = "${cidrhost(azurerm_subnet.azure_bosh_subnet.address_prefix, 2)}-${cidrhost(azurerm_subnet.azure_bosh_subnet.address_prefix, 6)}"
}
output "bats_public_ip" {
  value = azurerm_public_ip.azure_ip_bats.ip_address
}
output "bats_first_network" {
  value = {
    name           = azurerm_subnet.azure_bats_subnet.name
    cidr           = azurerm_subnet.azure_bats_subnet.address_prefix
    gateway        = cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 1)
    reserved_range = "${cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 2)}-${cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 3)}"
    static_range   = "${cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 4)}-${cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 10)}"
    static_ip_1    = cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 4)
    static_ip_2    = cidrhost(azurerm_subnet.azure_bats_subnet.address_prefix, 5)
  }
}
output "bats_second_network" {
  value = {
    name           = azurerm_subnet.azure_bats_subnet_2.name
    cidr           = azurerm_subnet.azure_bats_subnet_2.address_prefix
    gateway        = cidrhost(azurerm_subnet.azure_bats_subnet_2.address_prefix, 1)
    reserved_range = "${cidrhost(azurerm_subnet.azure_bats_subnet_2.address_prefix, 2)}-${cidrhost(azurerm_subnet.azure_bats_subnet_2.address_prefix, 3)}"
    static_range   = "${cidrhost(azurerm_subnet.azure_bats_subnet_2.address_prefix, 4)}-${cidrhost(azurerm_subnet.azure_bats_subnet_2.address_prefix, 10)}"
    static_ip_1    = cidrhost(azurerm_subnet.azure_bats_subnet_2.address_prefix, 4)
  }
}
