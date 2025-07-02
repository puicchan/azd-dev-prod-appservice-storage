// Conditional Network Integration Implementation for environment-specific connectivity
// This configuration deploys different networking patterns based on environment type:
// 
// PRODUCTION (envType = 'prod'):
// 1. Virtual Network with two subnets:
//    - vnet-integration-subnet: For App Service VNet integration (delegated to Microsoft.Web/serverfarms)
//    - private-endpoint-subnet: For private endpoints to backend services
// 2. Private DNS Zone for storage account resolution within the VNet
// 3. Private endpoint for storage account (blocks public access)
// 4. App Service with VNet integration enabled
// 5. Storage account with public access disabled (only accessible via private endpoint)
//
// DEVELOPMENT (envType != 'prod'):
// 1. No VNet integration - simplified connectivity
// 2. Storage account with public access enabled (with network restrictions)
// 3. App Service without VNet integration
// 4. Managed identity still used for secure authentication
//
// Security Benefits (Production):
// - All traffic between App Service and Storage Account flows through the private network
// - Storage account is not accessible from the public internet
// - DNS resolution for storage account happens through private DNS zone
// - App Service can reach storage account using private IP addresses

@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Deploy network infrastructure only for production environments
module network './network.bicep' = if (envType == 'prod') {
  name: 'networkDeployment'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: resourceToken
  }
}

// Monitor application with Azure Monitor
module monitoring './monitoring.bicep' = {
  name: 'monitoringDeployment'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: resourceToken
  }
}

module appIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'appidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}app-${resourceToken}'
    location: location
  }
}

// Shared services including storage account with environment-specific connectivity
module shared './shared.bicep' = {
  name: 'sharedDeployment'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: resourceToken
    envType: envType
    privateEndpointSubnetId: envType == 'prod' ? network.outputs.privateEndpointSubnetId : ''
    privateDnsZoneStorageId: envType == 'prod' ? network.outputs.privateDnsZoneStorageId : ''
    appIdentityPrincipalId: appIdentity.outputs.principalId
  }
}

// Application hosting infrastructure
module app './app.bicep' = {
  name: 'appDeployment'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: resourceToken
    envType: envType
    vnetIntegrationSubnetId: envType == 'prod' ? network.outputs.vnetIntegrationSubnetId : ''
    applicationInsightsResourceId: monitoring.outputs.applicationInsightsResourceId
    appIdentityResourceId: appIdentity.outputs.resourceId
    appIdentityClientId: appIdentity.outputs.clientId
    storageAccountName: shared.outputs.storageAccountName
    storageAccountBlobEndpoint: shared.outputs.storageAccountBlobEndpoint
  }
}

output AZURE_RESOURCE_APP_ID string = app.outputs.appServiceResourceId
output AZURE_RESOURCE_STORAGE_ID string = shared.outputs.storageAccountId
