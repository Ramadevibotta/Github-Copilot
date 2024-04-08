---------- Define PARAMETERS for Keyvault resource ----------
import { keyVaultAttributeType } from 'keyvault-types.bicep'

@maxLength(24)
param kvName string
param location string
param allowedIps string
param spnKvRoleDefinitionIds array
param groupKvRoleDefinitionIds array

param vnetRg string
param pleSubnetName string
param vnetName string

param rgSpnObjectId string
param adGroupObjectId string

param keyVaultAttributes keyVaultAttributeType
param keyVaultResourceTag object

var noDeleteLock = 'CanNotDelete'
var pleName = '${kvName}-ple'

// ---------- Define RESOURCES for Keyvault resource ----------
resource kvResource 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: kvName
  location: location
  properties: {
    tenantId: subscription().tenantId
    publicNetworkAccess: keyVaultAttributes.publicNetworkAccess
    enablePurgeProtection: keyVaultAttributes.enablePurgeProtection
    enableRbacAuthorization: keyVaultAttributes.enableRbacAuthorization
    enableSoftDelete: keyVaultAttributes.enableSoftDelete
    enabledForDeployment: keyVaultAttributes.enableVaultForDeployment
    enabledForDiskEncryption: keyVaultAttributes.enableVaultForDiskEncryption
    enabledForTemplateDeployment: keyVaultAttributes.enableVaultForTemplateDeployment
    softDeleteRetentionInDays: keyVaultAttributes.softDeleteRetentionInDays
    networkAcls: {
      bypass: keyVaultAttributes.bypassNetworkAcl
      defaultAction: 'Deny'

      ipRules: [for item in empty(allowedIps) ? [] : split(allowedIps, ','): {
        value: item
      }]

      virtualNetworkRules: [for subnet in empty(keyVaultAttributes.subnets) ? [] : split(keyVaultAttributes.subnets, ','): {
        id: resourceId(vnetRg, 'Microsoft.Network/virtualNetworks/subnets', vnetName, subnet)
        ignoreMissingVnetServiceEndpoint: false
      }]
    }

    sku: {
      name: keyVaultAttributes.skuType
      family: 'A'
    }
  }
  tags: keyVaultResourceTag
}

resource pleResource 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: pleName
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: pleName
        properties: {
          privateLinkServiceId: kvResource.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
    subnet: {
      id: resourceId(vnetRg, 'Microsoft.Network/virtualNetworks/subnets', vnetName, pleSubnetName)
    }
  }
  tags: keyVaultResourceTag
}

resource kvLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: '${kvResource.name}-lock'
  scope: kvResource
  properties: {
    level: noDeleteLock
    notes: 'Locking Key Vault with Cannot Delete Lock.'
  }
}

@description('Setup KV Role for RGSPN')
resource spnRoleAssignmentResources 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
for kvRoleDefinitionId in spnKvRoleDefinitionIds: {
  name: guid(resourceGroup().id, keyVaultAttributes.spnRoleName, kvRoleDefinitionId)
  scope: kvResource
  properties: {
    principalId: rgSpnObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', kvRoleDefinitionId)
  }
}]

@description('Setup KV Role for Group')
resource groupRoleAssignmentResources 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
for kvRoleDefinitionId in groupKvRoleDefinitionIds: {
  name: guid(resourceGroup().id, keyVaultAttributes.groupRoleName, kvRoleDefinitionId)
  scope: kvResource
  properties: {
    principalId: adGroupObjectId
    principalType: 'Group'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', kvRoleDefinitionId)
  }
}]

