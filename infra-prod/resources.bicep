// Virtual Network Integration Implementation for secure back-end communication
// This configuration follows the pattern from: https://learn.microsoft.com/en-us/azure/app-service/tutorial-networking-isolate-vnet
// 
// Architecture:
// 1. Virtual Network with two subnets:
//    - vnet-integration-subnet: For App Service VNet integration (delegated to Microsoft.Web/serverfarms)
//    - private-endpoint-subnet: For private endpoints to backend services
// 2. Private DNS Zone for storage account resolution within the VNet
// 3. Private endpoint for storage account (blocks public access)
// 4. App Service with VNet integration enabled
// 5. Storage account with public access disabled (only accessible via private endpoint)
//
// Security Benefits:
// - All traffic between App Service and Storage Account flows through the private network
// - Storage account is not accessible from the public internet
// - DNS resolution for storage account happens through private DNS zone
// - App Service can reach storage account using private IP addresses

@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Monitor application with Azure Monitor
module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
    location: location
    tags: tags
  }
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  name: 'appServicePlanDeployment'
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    kind: 'linux'
    skuCapacity: 1
    skuName: 'S1'
  }
}

// Virtual Network for secure networking
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${abbrs.networkVirtualNetworks}${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vnet-integration-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: 'app-service-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'private-endpoint-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Private DNS Zone for storage account
resource privateDnsZoneStorage 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}

// VNet link for private DNS zone
resource privateDnsZoneStorageVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'storage-vnet-link'
  parent: privateDnsZoneStorage
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
}

var storageAccountName = '${abbrs.storageStorageAccounts}${resourceToken}'
module storageAccount 'br/public:avm/res/storage/storage-account:0.17.2' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    blobServices: {
      containers: [
        {
          name: 'files'
        }
      ]
    }
    location: location
    roleAssignments: [
      {
        principalId: appIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
      }
    ]
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
    }
    tags: tags
  }
  dependsOn: [
    virtualNetwork
  ]
}

// Private Endpoint for storage account
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-storage-${resourceToken}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${virtualNetwork.id}/subnets/private-endpoint-subnet'
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

// DNS Zone Group for private endpoint
resource storagePrivateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'storage-dns-zone-group'
  parent: storagePrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'storage-config'
        properties: {
          privateDnsZoneId: privateDnsZoneStorage.id
        }
      }
    ]
  }
}

module appIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'appidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}app-${resourceToken}'
    location: location
  }
}

module app 'br/public:avm/res/web/site:0.15.1' = {
  name: 'appServiceDeployment-app'
  params: {
    name: '${abbrs.webSitesAppService}app-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'app' })
    kind: 'app,linux'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    managedIdentities:{
      systemAssigned: false
      userAssignedResourceIds: [appIdentity.outputs.resourceId]
    }
    siteConfig: {
      linuxFxVersion: 'python|3.13'
      appCommandLine: ''
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          'https://ms.portal.azure.com'
        ]
      }
    }
    clientAffinityEnabled: false
    httpsOnly: true
    appSettingsKeyValuePairs: {
      AZURE_CLIENT_ID: appIdentity.outputs.clientId
      AZURE_STORAGE_ACCOUNT_NAME: storageAccount.outputs.name
      AZURE_STORAGE_BLOB_ENDPOINT: storageAccount.outputs.serviceEndpoints.blob
      PORT: '80'
      ENABLE_ORYX_BUILD: 'true'
      PYTHON_ENABLE_GUNICORN_MULTIWORKERS: 'true'
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    }
    virtualNetworkSubnetId: '${virtualNetwork.id}/subnets/vnet-integration-subnet'
    appInsightResourceId: monitoring.outputs.applicationInsightsResourceId
    keyVaultAccessIdentityResourceId: appIdentity.outputs.resourceId
    basicPublishingCredentialsPolicies: [
      {
        name: 'ftp'
        allow: false
      }
      {
        name: 'scm'
        allow: false
      }
    ]
    logsConfiguration: {
      applicationLogs: { fileSystem: { level: 'Verbose' } }
      detailedErrorMessages: { enabled: true }
      failedRequestsTracing: { enabled: true }
      httpLogs: { fileSystem: { enabled: true, retentionInDays: 1, retentionInMb: 35 } }
    }
  }
  dependsOn: [
    storagePrivateEndpoint
  ]
}

output AZURE_RESOURCE_APP_ID string = app.outputs.resourceId
output AZURE_RESOURCE_STORAGE_ID string = storageAccount.outputs.resourceId
