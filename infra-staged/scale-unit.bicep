// Multi-Region Scale Unit Infrastructure for High Availability
// This module creates a complete scale unit that can be deployed across multiple regions
// 
// Architecture Overview:
// 1. Azure Front Door for global load balancing and CDN
// 2. Regional App Services with environment-specific networking
// 3. Geo-replicated storage with read replicas
// 4. Shared monitoring and health probes
// 5. Automatic failover and traffic routing
//
// Benefits:
// - High availability across regions
// - Disaster recovery capabilities
// - Improved performance with global CDN
// - Automatic health monitoring and failover
// - Consistent security policies across regions

@description('The primary location for the scale unit')
param primaryLocation string = 'East US'

@description('The secondary location for the scale unit')
param secondaryLocation string = 'West US 2'

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Application name for naming resources')
param applicationName string = 'fileapp'

// Global resources (shared across regions)
var globalResourceNames = {
  frontDoor: '${abbrs.cdnProfiles}${applicationName}-${resourceToken}'
  trafficManager: '${abbrs.networkTrafficManagerProfiles}${applicationName}-${resourceToken}'
  globalStorage: '${abbrs.storageStorageAccounts}global${resourceToken}'
}

// Regional resource names
var primaryResourceNames = {
  resourceGroup: 'rg-${applicationName}-primary-${resourceToken}'
  appService: '${abbrs.webSitesAppService}${applicationName}-primary-${resourceToken}'
  storage: '${abbrs.storageStorageAccounts}primary${resourceToken}'
}

var secondaryResourceNames = {
  resourceGroup: 'rg-${applicationName}-secondary-${resourceToken}'
  appService: '${abbrs.webSitesAppService}${applicationName}-secondary-${resourceToken}'
  storage: '${abbrs.storageStorageAccounts}secondary${resourceToken}'
}

// Deploy primary region infrastructure
module primaryRegion 'regional-deployment.bicep' = {
  name: 'primaryRegionDeployment'
  params: {
    location: primaryLocation
    tags: union(tags, { 'region-role': 'primary' })
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    regionSuffix: 'primary'
    isPrimary: true
  }
}

// Deploy secondary region infrastructure
module secondaryRegion 'regional-deployment.bicep' = {
  name: 'secondaryRegionDeployment'
  params: {
    location: secondaryLocation
    tags: union(tags, { 'region-role': 'secondary' })
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    regionSuffix: 'secondary'
    isPrimary: false
  }
}

// Global Front Door for load balancing and CDN
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: globalResourceNames.frontDoor
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {}
}

// Front Door endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoorProfile
  name: '${applicationName}-${resourceToken}'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin group for the App Services
resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: 'app-services'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

// Primary region origin
resource primaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: frontDoorOriginGroup
  name: 'primary-app-service'
  properties: {
    hostName: primaryRegion.outputs.appServiceHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: primaryRegion.outputs.appServiceHostName
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Secondary region origin
resource secondaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: frontDoorOriginGroup
  name: 'secondary-app-service'
  properties: {
    hostName: secondaryRegion.outputs.appServiceHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: secondaryRegion.outputs.appServiceHostName
    priority: 2
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Routing rule
resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: frontDoorEndpoint
  name: 'default-route'
  properties: {
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    primaryOrigin
    secondaryOrigin
  ]
}

// Global Storage Account for shared data (e.g., configuration, metadata)
resource globalStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: globalResourceNames.globalStorage
  location: primaryLocation // Global storage needs a location, using primary
  tags: union(tags, { 'storage-role': 'global' })
  sku: {
    name: 'Standard_GRS' // Geo-redundant storage for global data
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: envType == 'prod' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob service for global storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: globalStorageAccount
  name: 'default'
}

// Container for global configuration
resource globalConfigContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'global-config'
  properties: {
    publicAccess: 'None'
  }
}

// Application Insights for global monitoring
resource globalAppInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${abbrs.insightsComponents}global-${resourceToken}'
  location: primaryLocation
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: primaryRegion.outputs.logAnalyticsWorkspaceResourceId
  }
}

// Outputs
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName
output frontDoorId string = frontDoorProfile.id
output primaryAppServiceHostname string = primaryRegion.outputs.appServiceHostName
output secondaryAppServiceHostname string = secondaryRegion.outputs.appServiceHostName
output globalStorageAccountName string = globalStorageAccount.name
output globalAppInsightsInstrumentationKey string = globalAppInsights.properties.InstrumentationKey
output globalAppInsightsConnectionString string = globalAppInsights.properties.ConnectionString
