// Multi-Region Scale Unit Main Infrastructure
// This is the main entry point for deploying a multi-region scale unit
//
// Architecture:
// - Primary and secondary regions with App Services
// - Azure Front Door for global load balancing
// - Geo-replicated storage for data consistency
// - Cross-region monitoring and alerting
// - Environment-specific networking (VNet integration for prod)
//
// Usage:
// - Deploy with envType='dev' for simplified multi-region setup
// - Deploy with envType='prod' for full VNet integration and private endpoints

targetScope = 'subscription'

metadata name = 'Multi-Region Scale Unit'
metadata description = 'Deploys a highly available multi-region application with Azure Front Door'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for resources')
param primaryLocation string = 'East US'

@minLength(1)
@description('Secondary location for resources')
param secondaryLocation string = 'West US 2'

@description('Environment type - determines networking configuration (dev/test/prod)')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

// Tags that should be applied to all resources.
var tags = {
  'azd-env-name': environmentName
  'environment-type': envType
  'scale-unit': 'multi-region'
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, primaryLocation)

// Create resource groups for each region
resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}-primary'
  location: primaryLocation
  tags: union(tags, { 'region-role': 'primary' })
}

resource secondaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}-secondary'
  location: secondaryLocation
  tags: union(tags, { 'region-role': 'secondary' })
}

resource globalResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}-global'
  location: primaryLocation
  tags: union(tags, { 'region-role': 'global' })
}

// Deploy primary region infrastructure
module primaryRegion 'regional-deployment.bicep' = {
  name: 'primaryRegionDeployment'
  scope: primaryResourceGroup
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
  scope: secondaryResourceGroup
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

// Deploy global infrastructure (Front Door, global storage, etc.)
module globalInfrastructure 'global-infrastructure.bicep' = {
  name: 'globalInfrastructureDeployment'
  scope: globalResourceGroup
  params: {
    primaryLocation: primaryLocation
    secondaryLocation: secondaryLocation
    tags: tags
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    primaryAppServiceHostname: primaryRegion.outputs.appServiceHostName
    secondaryAppServiceHostname: secondaryRegion.outputs.appServiceHostName
    primaryLogAnalyticsWorkspaceId: primaryRegion.outputs.logAnalyticsWorkspaceResourceId
  }
}

// Outputs for the scale unit
@description('Front Door endpoint hostname for global access')
output frontDoorEndpoint string = globalInfrastructure.outputs.frontDoorEndpointHostname

@description('Primary region App Service hostname')
output primaryAppServiceHostname string = primaryRegion.outputs.appServiceHostName

@description('Secondary region App Service hostname')
output secondaryAppServiceHostname string = secondaryRegion.outputs.appServiceHostName

@description('Global storage account name')
output globalStorageAccountName string = globalInfrastructure.outputs.globalStorageAccountName

@description('Primary region resource group name')
output primaryResourceGroupName string = primaryResourceGroup.name

@description('Secondary region resource group name')
output secondaryResourceGroupName string = secondaryResourceGroup.name

@description('Global resource group name')
output globalResourceGroupName string = globalResourceGroup.name

@description('Environment type used for this deployment')
output environmentType string = envType
