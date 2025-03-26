#variables.tf
variable "grants_raw" {
  description = "List of grants to apply to the securable"
  type = list(object({
    principal  = string
    privileges = list(string)
  }))
}

variable "metastore" {
  description = "The metastore ID to apply grants to"
  type        = string
  default     = null
}

variable "catalog" {
  description = "The catalog name to apply grants to"
  type        = string
  default     = null
}

variable "schema" {
  description = "The schema name in the format 'catalog.schema'"
  type        = string
  default     = null
}

variable "table" {
  description = "The table name in the format 'catalog.schema.table'"
  type        = string
  default     = null
}

variable "view" {
  description = "The view name in the format 'catalog.schema.view'"
  type        = string
  default     = null
}

variable "volume" {
  description = "The volume name in the format 'catalog.schema.volume'"
  type        = string
  default     = null
}

variable "function" {
  description = "The function name in the format 'catalog.schema.function'"
  type        = string
  default     = null
}

variable "external_location" {
  description = "The external location name"
  type        = string
  default     = null
}

variable "storage_credential" {
  description = "The storage credential name"
  type        = string
  default     = null
}

variable "connection" {
  description = "The connection name"
  type        = string
  default     = null
}

variable "share" {
  description = "The Delta Sharing share name"
  type        = string
  default     = null
}

variable "recipient" {
  description = "The Delta Sharing recipient name"
  type        = string
  default     = null
}

variable "provider" {
  description = "The Delta Sharing provider name"
  type        = string
  default     = null
}

variable "clean_room" {
  description = "The clean room name"
  type        = string
  default     = null
}

variable "service_credential" {
  description = "The service credential name"
  type        = string
  default     = null
}


#locals.tf

locals {
  grants = var.grants_raw

  target_keys_set = compact([
    var.metastore,
    var.catalog,
    var.schema,
    var.table,
    var.view,
    var.volume,
    var.function,
    var.external_location,
    var.storage_credential,
    var.connection,
    var.share,
    var.recipient,
    var.provider,
    var.clean_room,
    var.service_credential
  ])
}

#maint.tf

resource "databricks_grants" "this" {
  metastore          = var.metastore
  catalog            = var.catalog
  schema             = var.schema
  table              = var.table
  view               = var.view
  volume             = var.volume
  function           = var.function
  external_location  = var.external_location
  storage_credential = var.storage_credential
  connection         = var.connection
  share              = var.share
  recipient          = var.recipient
  provider           = var.provider
  clean_room         = var.clean_room
  service_credential = var.service_credential

  dynamic "grant" {
    for_each = local.grants
    content {
      principal  = grant.value.principal
      privileges = grant.value.privileges
    }
  }

  lifecycle {
    precondition {
      condition = length(local.target_keys_set) == 1
      error_message = "Exactly one grant target (e.g. metastore, catalog, table, etc.) must be specified."
    }

    precondition {
      condition     = length(local.grants) > 0
      error_message = "At least one grant must be defined."
    }
  }
}


#tfvars

metastore = "abc-123-metastore-id"

grants_raw = [
  {
    principal  = "Data Engineers"
    privileges = ["CREATE_CATALOG", "CREATE_EXTERNAL_LOCATION"]
  },
  {
    principal  = "Data Sharer"
    privileges = ["CREATE_SHARE"]
  }
]

