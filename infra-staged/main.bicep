targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@minLength(1)
@description('Primary location for all resources (alias for compatibility)')
param primaryLocation string = location

@minLength(1)
@description('Secondary location for resources (for future multi-region support)')
param secondaryLocation string = 'West US 2'

@description('Environment type - determines networking configuration (dev/test/prod)')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Id of the user or app to assign application roles')
param principalId string = ''

@description('Type of the user or app to assign application roles')
@allowed(['User', 'ServicePrincipal'])
param principalType string = 'User'

// The principal parameters are available for role assignments if needed in the future
// Currently, the application uses managed identity for secure access

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
  'environment-type': envType
}

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources 'resources.bicep' = {
  scope: rg
  name: 'resources'
  params: {
    location: location
    tags: tags
    envType: envType
  }
}
output AZURE_RESOURCE_APP_ID string = resources.outputs.AZURE_RESOURCE_APP_ID
output AZURE_RESOURCE_STORAGE_ID string = resources.outputs.AZURE_RESOURCE_STORAGE_ID
