// Application infrastructure module for App Service hosting
// This module creates the application hosting infrastructure:
// 1. App Service Plan for hosting the application
// 2. App Service with VNet integration and security configurations
// 3. Managed identity integration for secure resource access
//
// Security Features:
// - VNet integration for secure backend communication
// - Managed identity for passwordless authentication
// - HTTPS-only configuration
// - Disabled FTP and SCM basic auth
// - Comprehensive logging and monitoring integration

@description('The location used for all deployed resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('VNet integration subnet ID for App Service (empty for non-prod environments)')
param vnetIntegrationSubnetId string

@description('Application Insights resource ID for monitoring')
param applicationInsightsResourceId string

@description('Managed identity resource ID for the application')
param appIdentityResourceId string

@description('Managed identity client ID for the application')
param appIdentityClientId string

@description('Storage account name for application configuration')
param storageAccountName string

@description('Storage account blob endpoint for application configuration')
param storageAccountBlobEndpoint string

// App Service Plan for hosting the application
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

// App Service with secure configuration
module appService 'br/public:avm/res/web/site:0.15.1' = {
  name: 'appServiceDeployment-app'
  params: {
    name: '${abbrs.webSitesAppService}app-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'app' })
    kind: 'app,linux'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    managedIdentities:{
      systemAssigned: false
      userAssignedResourceIds: [appIdentityResourceId]
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
      AZURE_CLIENT_ID: appIdentityClientId
      AZURE_STORAGE_ACCOUNT_NAME: storageAccountName
      AZURE_STORAGE_BLOB_ENDPOINT: storageAccountBlobEndpoint
      PORT: '80'
      ENABLE_ORYX_BUILD: 'true'
      PYTHON_ENABLE_GUNICORN_MULTIWORKERS: 'true'
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    }
    virtualNetworkSubnetId: envType == 'prod' && !empty(vnetIntegrationSubnetId) ? vnetIntegrationSubnetId : null
    appInsightResourceId: applicationInsightsResourceId
    keyVaultAccessIdentityResourceId: appIdentityResourceId
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
}

// Outputs for use by other modules
@description('App Service resource ID')
output appServiceResourceId string = appService.outputs.resourceId

@description('App Service Plan resource ID')
output appServicePlanResourceId string = appServicePlan.outputs.resourceId

@description('App Service default hostname')
output appServiceDefaultHostname string = appService.outputs.defaultHostname

@description('App Service name')
output appServiceName string = appService.outputs.name
