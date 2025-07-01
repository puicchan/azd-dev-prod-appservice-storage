// Regional deployment module for multi-region scale unit
// This module creates all regional resources for a single region
// It reuses the existing modular architecture but adds region-specific configurations
//
// Features:
// - Region-specific networking (prod vs dev)
// - Regional storage with geo-replication support
// - Regional monitoring with cross-region correlation
// - Health endpoints for Front Door probes
// - Automatic scaling and load balancing

@description('The location for regional resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Region suffix for naming (primary/secondary)')
param regionSuffix string

@description('Whether this is the primary region')
param isPrimary bool = true

// Note: Resource groups are created at the subscription level
// This regional deployment module assumes it's deployed within an existing resource group

// Deploy network infrastructure (only for production)
module regionalNetwork '../infra-staged/network.bicep' = if (envType == 'prod') {
  name: 'regional-network-${regionSuffix}'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
  }
}

// Regional monitoring
module regionalMonitoring '../infra-staged/monitoring.bicep' = {
  name: 'regional-monitoring-${regionSuffix}'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
  }
}

// Regional managed identity
module regionalAppIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'regional-app-identity-${regionSuffix}'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}app-${regionSuffix}-${resourceToken}'
    location: location
    tags: tags
  }
}

// Regional shared services (storage)
module regionalShared '../infra-staged/shared.bicep' = {
  name: 'regional-shared-${regionSuffix}'
  params: {
    location: location
    tags: union(tags, { 'region-role': regionSuffix })
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
    envType: envType
    privateEndpointSubnetId: envType == 'prod' ? regionalNetwork.outputs.privateEndpointSubnetId : ''
    privateDnsZoneStorageId: envType == 'prod' ? regionalNetwork.outputs.privateDnsZoneStorageId : ''
    appIdentityPrincipalId: regionalAppIdentity.outputs.principalId
  }
}

// Regional application hosting
module regionalApp '../infra-staged/app.bicep' = {
  name: 'regional-app-${regionSuffix}'
  params: {
    location: location
    tags: union(tags, { 'azd-service-name': 'app' })
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
    envType: envType
    vnetIntegrationSubnetId: envType == 'prod' ? regionalNetwork.outputs.vnetIntegrationSubnetId : ''
    applicationInsightsResourceId: regionalMonitoring.outputs.applicationInsightsResourceId
    appIdentityResourceId: regionalAppIdentity.outputs.resourceId
    appIdentityClientId: regionalAppIdentity.outputs.clientId
    storageAccountName: regionalShared.outputs.storageAccountName
    storageAccountBlobEndpoint: regionalShared.outputs.storageAccountBlobEndpoint
  }
}

// Regional autoscaling rules
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${abbrs.insightsAutoscalesettings}${regionSuffix}-${resourceToken}'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: regionalApp.outputs.appServicePlanResourceId
    profiles: [
      {
        name: 'Default'
        capacity: {
          minimum: '1'
          maximum: isPrimary ? '10' : '5' // Primary region gets higher capacity
          default: isPrimary ? '2' : '1'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: regionalApp.outputs.appServicePlanResourceId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: regionalApp.outputs.appServicePlanResourceId
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
    notifications: []
  }
}

// Regional alert rules for health monitoring
resource healthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${regionSuffix}-app-health-alert-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when app service is unhealthy in ${regionSuffix} region'
    severity: 1
    enabled: true
    scopes: [
      regionalApp.outputs.appServiceResourceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HealthCheckStatus'
          metricName: 'HealthCheckStatus'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    // Note: Action groups would need to be created separately or referenced from monitoring module
  }
}

// Outputs
output appServiceHostName string = regionalApp.outputs.appServiceDefaultHostname
output appServiceResourceId string = regionalApp.outputs.appServiceResourceId
output appServiceName string = regionalApp.outputs.appServiceName
output appServicePlanResourceId string = regionalApp.outputs.appServicePlanResourceId
output storageAccountName string = regionalShared.outputs.storageAccountName
output logAnalyticsWorkspaceResourceId string = regionalMonitoring.outputs.logAnalyticsWorkspaceResourceId
output applicationInsightsResourceId string = regionalMonitoring.outputs.applicationInsightsResourceId
