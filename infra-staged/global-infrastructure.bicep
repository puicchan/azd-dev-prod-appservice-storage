// Global infrastructure module for multi-region scale unit
// This module creates global resources that span multiple regions:
// - Azure Front Door for global load balancing and CDN
// - Global storage account for shared configuration
// - Cross-region monitoring and alerting
//
// Benefits:
// - Single global endpoint for users
// - Automatic failover between regions
// - CDN capabilities for improved performance
// - Centralized configuration management

@description('The primary location for global resources')
param primaryLocation string

@description('The secondary location for reference')
param secondaryLocation string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Primary App Service hostname')
param primaryAppServiceHostname string

@description('Secondary App Service hostname')
param secondaryAppServiceHostname string

@description('Primary region Log Analytics workspace ID')
param primaryLogAnalyticsWorkspaceId string

// Global Front Door for load balancing and CDN
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: '${abbrs.cdnProfiles}global-${resourceToken}'
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
  name: 'app-${resourceToken}'
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
    hostName: primaryAppServiceHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: primaryAppServiceHostname
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
    hostName: secondaryAppServiceHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: secondaryAppServiceHostname
    priority: 2
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Routing rule for the application
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

// Global Storage Account for shared configuration and metadata
resource globalStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${abbrs.storageStorageAccounts}global${resourceToken}'
  location: primaryLocation
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

// Container for shared application data
resource sharedDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'shared-data'
  properties: {
    publicAccess: 'None'
  }
}

// Global Application Insights for cross-region monitoring
resource globalAppInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${abbrs.insightsComponents}global-${resourceToken}'
  location: primaryLocation
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: primaryLogAnalyticsWorkspaceId
  }
}

// Action Group for global alerts
resource globalActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${abbrs.insightsActionGroups}global-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'GlobalAlert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: [
      {
        name: 'Monitoring Contributor'
        roleId: '749f88d5-cbae-40b8-bcfc-e573ddc772fa' // Monitoring Contributor role
        useCommonAlertSchema: true
      }
    ]
  }
}

// Front Door availability alert
resource frontDoorAvailabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'front-door-availability-alert-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Front Door availability drops below threshold'
    severity: 1
    enabled: true
    scopes: [
      frontDoorProfile.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'OriginHealthPercentage'
          metricName: 'OriginHealthPercentage'
          operator: 'LessThan'
          threshold: 90
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: globalActionGroup.id
      }
    ]
  }
}

// Outputs
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName
output frontDoorId string = frontDoorProfile.id
output globalStorageAccountName string = globalStorageAccount.name
output globalAppInsightsConnectionString string = globalAppInsights.properties.ConnectionString
output globalActionGroupId string = globalActionGroup.id
