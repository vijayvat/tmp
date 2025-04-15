{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2019-05-01/workflowDefinition.json#",
    "actions": {
      "Response": {
        "runAfter": {},
        "type": "Response",
        "inputs": {
          "statusCode": 200,
          "body": {
            "message": "Storage access test passed"
          }
        }
      }
    },
    "triggers": {
      "Every_hour": {
        "recurrence": {
          "frequency": "Hour",
          "interval": 1
        },
        "type": "Recurrence"
      }
    },
    "contentVersion": "1.0.0.0"
  },
  "kind": "Stateful"
}


site/wwwroot/workflows/ping/ping.workflow.json
