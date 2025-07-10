  firewall_rules = var.delegate_subnet_id != null && var.delegate_subnet_id != "" ? [] : concat(local.tfe_firewall.tfe_servers, local.default_fw_rules, var.firewall_rules)
