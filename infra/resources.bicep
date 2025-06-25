@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Id of the user or app to assign application roles')
param principalId string

@description('Principal type of user or app')
param principalType string

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
    skuName: 'B2'
  }
}

var storageAccountName = '${abbrs.storageStorageAccounts}${resourceToken}'
module storageAccount 'br/public:avm/res/storage/storage-account:0.17.2' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    blobServices: {
      containers: [
        {
          name: 'files'
        }
      ]
    }
    location: location
    roleAssignments: concat(
      principalType == 'User' ? [
        {  
          principalId: principalId
          principalType: 'User'
          roleDefinitionIdOrName: 'Storage Blob Data Contributor'  
        }
      ] : [],
      [
        {
          principalId: appIdentity.outputs.principalId
          principalType: 'ServicePrincipal'
          roleDefinitionIdOrName: 'Storage Blob Data Contributor'
        }
      ]
    )
    networkAcls: {
      defaultAction: 'Allow'
    }
    tags: tags
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
}
output AZURE_RESOURCE_APP_ID string = app.outputs.resourceId
output AZURE_RESOURCE_STORAGE_ID string = storageAccount.outputs.resourceId
