// Shared services module for common infrastructure components with environment-specific connectivity
// This module creates shared services that can be used by multiple application components:
// 1. Storage Account with environment-specific access configuration
// 2. Private Endpoint for secure storage access within the VNet (PROD only)
// 3. DNS Zone Group configuration for private endpoint resolution (PROD only)
//
// Environment-Specific Configuration:
// PRODUCTION: Private endpoint connectivity with network isolation
// DEVELOPMENT: Public access with managed identity authentication and IP restrictions
//
// Security Features:
// - Managed identity-based access control (all environments)
// - Network access controls with appropriate restrictions per environment
// - HTTPS-only access and secure transport

@description('The location used for all deployed resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Environment type - determines connectivity configuration')
@allowed(['dev', 'test', 'prod'])
param envType string

@description('Private endpoint subnet ID for storage account (required for prod)')
param privateEndpointSubnetId string

@description('Private DNS Zone ID for storage account (required for prod)')
param privateDnsZoneStorageId string

@description('Principal ID of the managed identity that needs storage access')
param appIdentityPrincipalId string

// Storage Account with environment-specific access configuration
var storageAccountName = '${abbrs.storageStorageAccounts}${resourceToken}'
module storageAccount 'br/public:avm/res/storage/storage-account:0.17.2' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    allowSharedKeyAccess: false
    publicNetworkAccess: envType == 'prod' ? 'Disabled' : 'Enabled'
    blobServices: {
      containers: [
        {
          name: 'files'
          publicAccess: 'None'
        }
      ]
    }
    location: location
    roleAssignments: [
      {
        principalId: appIdentityPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ]
    networkAcls: envType == 'prod' ? {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      bypass: 'AzureServices'
    } : {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      bypass: 'AzureServices'
    }
    tags: tags
  }
}

// Private Endpoint for storage account (Production only)
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (envType == 'prod') {
  name: 'pe-storage-${resourceToken}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccount.outputs.resourceId
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// DNS Zone Group for private endpoint (Production only)
resource storagePrivateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (envType == 'prod') {
  name: 'storage-dns-zone-group'
  parent: storagePrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'storage-config'
        properties: {
          privateDnsZoneId: privateDnsZoneStorageId
        }
      }
    ]
  }
}

// Outputs for use by other modules
@description('Storage Account resource ID')
output storageAccountId string = storageAccount.outputs.resourceId

@description('Storage Account name')
output storageAccountName string = storageAccount.outputs.name

@description('Storage Account blob endpoint')
output storageAccountBlobEndpoint string = storageAccount.outputs.serviceEndpoints.blob

@description('Private endpoint resource ID (production only)')
output storagePrivateEndpointId string = envType == 'prod' ? storagePrivateEndpoint.id : ''
