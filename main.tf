condition = var.azure_attributes == null || try(var.azure_attributes.first_on_demand, null) == null || try(var.azure_attributes.first_on_demand > 0, false)
