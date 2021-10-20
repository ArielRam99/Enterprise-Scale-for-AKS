#data "terraform_remote_state" "existing-lz" {
#  backend = "azurerm"
#
#  config = {
#    storage_account_name = var.state_sa_name
#    container_name       = var.container_name
#    key                  = "lz-net"
#    access_key = var.access_key
#  }
#}
#
#data "terraform_remote_state" "existing-hub" {
#  backend = "azurerm"
#
#  config = {
#    storage_account_name = var.state_sa_name
#    container_name       = var.container_name
#    key                  = "hub-net"
#    access_key = var.access_key
#  }
#}

#data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "postgressql_rg" {
  name     = "postgressql-rg"
  location = var.location #eastus make default
}

resource "azurerm_postgresql_server" "postgresql_server" {
  name                = "postgresql-00000001"
  location            = azurerm_resource_group.postgressql_rg.location
  resource_group_name = azurerm_resource_group.postgressql_rg.name

  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_login_password
  auto_grow_enabled            = var.auto_grow_enabled
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled
  sku_name                     = var.sku_name
  ssl_enforcement_enabled      = var.ssl_enforcement_enabled
  storage_mb                   = var.storage_mb
  version                      = 11
}

resource "azurerm_private_endpoint" "postgressql_pe" {
  name                = "postgres-pe"
  location            = azurerm_resource_group.postgressql_rg.location
  resource_group_name = azurerm_resource_group.postgressql_rg.name
  subnet_id           = data.terraform_remote_state.existing-lz.outputs.aks_subnet_id

  private_service_connection {
    name                           = "postgresql-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_postgresql_server.postgresql_server.id
    subresource_names              = ["postgresqlServer"]
  }
}

#output "aks_subnet_id" {
#  value = azurerm_subnet.aks.id
#}

resource "azurerm_private_dns_zone" "postgressql_dns" {
  name                = var.postgressql_private_dns_zone_name
  resource_group_name = azurerm_resource_group.postgressql_rg.name
}

# Needed for Jumpbox to resolve postgressql using a private endpoint and private dns zone
resource "azurerm_private_dns_zone_virtual_network_link" "hub_postgressql" {
  name                  = "hub_to_postgressql"
  resource_group_name   = azurerm_resource_group.postgressql_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgressql_dns.name
  virtual_network_id    = data.terraform_remote_state.existing-hub.outputs.hub_vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "lz_postgressql" {
  name                  = "lz_to_postgressql"
  resource_group_name   = azurerm_resource_group.postgressql_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgressql_dns.name
  virtual_network_id    = data.terraform_remote_state.existing-lz.outputs.lz_vnet_id
}

resource "azurerm_private_dns_a_record" "a_record" {
  name                = "test"
  zone_name           = azurerm_private_dns_zone.postgressql_dns.name
  resource_group_name = azurerm_resource_group.postgressql_rg.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.postgressql_pe.private_service_connection.private_ip_address]
}

resource "azurerm_role_assignment" "postgres-to-dnszone" {
  scope                = azurerm_private_dns_zone.postgressql_dns.id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.mi-aks-cp.principal_id
}

output "postgressql_private_zone_id" {
  value = azurerm_private_dns_zone.postgressql_dns.id
}
output "postgressql_private_zone_name" {
  value = azurerm_private_dns_zone.postgressql_dns.name
}

################################

variable "location" {
    default = "EastUS"
}

variable "postgressql_private_dns_zone_name" {
    default = "privatelink.postgres.database.azure.com"
}

variable "administrator_login" {
    default = "psqladmin"
}

variable "administrator_login_password" {
    default = "H@Sh1CoR3!"
}

variable "auto_grow_enabled" {
    default = true
}

variable "backup_retention_days" {
    default = 7
}

variable "geo_redundant_backup_enabled" {
    default = false
}

variable "sku_name" {
    default = "GP_Gen5_2"
}

variable "ssl_enforcement_enabled" {
    default = true
}

variable "storage_mb" {
    default = 51200
}