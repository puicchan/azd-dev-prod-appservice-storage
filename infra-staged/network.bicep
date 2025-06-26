// Network infrastructure module for secure VNet integration and private networking
// This module creates:
// 1. Virtual Network with dedicated subnets for App Service integration and private endpoints
// 2. Private DNS Zone for blob storage resolution within the VNet
// 3. VNet link to enable DNS resolution for private endpoints
//
// Security Benefits:
// - Isolates network traffic to private network
// - Enables secure communication between services
// - Provides DNS resolution for private endpoints

@description('The location used for all deployed resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

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

// Outputs for use by other modules
@description('Virtual Network resource ID')
output virtualNetworkId string = virtualNetwork.id

@description('VNet integration subnet ID for App Service')
output vnetIntegrationSubnetId string = '${virtualNetwork.id}/subnets/vnet-integration-subnet'

@description('Private endpoint subnet ID')
output privateEndpointSubnetId string = '${virtualNetwork.id}/subnets/private-endpoint-subnet'

@description('Private DNS Zone ID for storage account')
output privateDnsZoneStorageId string = privateDnsZoneStorage.id

@description('Virtual Network name')
output virtualNetworkName string = virtualNetwork.name
