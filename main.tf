variable "name" {
  description = "Name of Storage Credentials, must be unique within the databricks_metastore."
  type        = string
}

variable "owner" {
  description = "Username/groupname/service principal application_id of the storage credential owner."
  type        = string
  default     = null
}

variable "read_only" {
  description = "Whether the storage credential is only usable for read operations."
  type        = bool
  default     = true
}

variable "skip_validation" {
  description = "Suppress validation errors if any and force save the storage credential."
  type        = bool
  default     = null
}

variable "force_destroy" {
  description = "Delete storage credential regardless of its dependencies."
  type        = bool
  default     = null
}

variable "force_update" {
  description = "Update storage credential regardless of its dependents."
  type        = bool
  default     = null
}

variable "isolation_mode" {
  description = "Defines access scope: ISOLATION_MODE_ISOLATED (only current workspace) or ISOLATION_MODE_OPEN (all workspaces)."
  type        = string
  default     = null
}

# AWS IAM Role block
variable "aws_iam_role" {
  description = "Configuration block for AWS IAM Role used for S3 access."
  type = object({
    role_arn = string
  })
  default = null
}

# Azure Managed Identity block
variable "azure_managed_identity" {
  description = "Configuration block for Azure Managed Identity used via Databricks Access Connector."
  type = object({
    access_connector_id  = string
    managed_identity_id  = optional(string)
  })
  default = null
}

# GCP Service Account block
variable "databricks_gcp_service_account" {
  description = "Optional configuration for Databricks-managed GCP Service Account (email is output only)."
  type        = bool
  default     = null
}

# Cloudflare API Token block
variable "cloudflare_api_token" {
  description = "Configuration block for Cloudflare R2 access using API token credentials."
  type = object({
    account_id        = string
    access_key_id     = string
    secret_access_key = string
  })
  default = null
}

# Azure Service Principal block (Legacy)
variable "azure_service_principal" {
  description = "Legacy configuration block for Azure Service Principal credentials."
  type = object({
    directory_id   = string
    application_id = string
    client_secret  = string
  })
  default = null
}


#-------------------

resource "databricks_storage_credential" "this" {
  name          = var.name
  read_only     = var.read_only  
  isolation_mode = "ISOLATION_MODE_ISOLATED"  # set based on security review

  # Optional block: aws_iam_role
  dynamic "aws_iam_role" {
    for_each = var.aws_iam_role == null ? [] : [var.aws_iam_role]
    content {
      role_arn = aws_iam_role.value.role_arn
    }
  }

  # Optional block: azure_managed_identity
  dynamic "azure_managed_identity" {
    for_each = var.azure_managed_identity == null ? [] : [var.azure_managed_identity]
    content {
      access_connector_id = azure_managed_identity.value.access_connector_id

      # Optional field inside block
      managed_identity_id = azure_managed_identity.value.managed_identity_id != null ? azure_managed_identity.value.managed_identity_id : null
    }
  }

  # Optional block: cloudflare_api_token
  dynamic "cloudflare_api_token" {
    for_each = var.cloudflare_api_token == null ? [] : [var.cloudflare_api_token]
    content {
      account_id        = cloudflare_api_token.value.account_id
      access_key_id     = cloudflare_api_token.value.access_key_id
      secret_access_key = cloudflare_api_token.value.secret_access_key
    }
  }

  # Optional flag for GCP managed service account (email is output only)
  databricks_gcp_service_account = var.databricks_gcp_service_account
}
