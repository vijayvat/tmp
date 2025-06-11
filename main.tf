condition = var.azure_attributes != null ? (var.azure_attributes.first_on_demand == null || (var.azure_attributes.first_on_demand != null && var.azure_attributes.first_on_demand > 0)) : true
