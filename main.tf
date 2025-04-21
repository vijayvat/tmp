resource "azurerm_cosmosdb_mongo_role_definition" "mongo_role_definition" {
  depends_on = [azurerm_cosmosdb_mongo_database.cosmosdb_mongo_database]
  for_each   = var.mongo_roles

  cosmos_mongo_database_id = azurerm_cosmosdb_mongo_database.cosmosdb_mongo_database.id
  role_name                = each.value.role_name

  dynamic "privilege" {
    for_each = each.value.privilege
    content {
      actions = privilege.value.actions

      dynamic "resource" {
        for_each = [privilege.value.resource]  # Wrapped in list to use dynamic block
        content {
          collection_name = resource.value.collection_name
          db_name         = resource.value.db_name
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.role_name != null
      error_message = "The input variable 'role_name' is mandatory and cannot be null for creating role definition."
    }
  }
}
