// @description('KeyVault Name')
// param keyVaultName string

@description('Deployment Location')
param location string = resourceGroup().location

@description('Managed Identity PrincipalId')
param principalId string

// @description('Client secret of the service principal')
// @secure()
// param spnClientSecret string

@secure()
param azdataPassword string = 'ArcPassword123!!'

@secure()
param registryPassword string = 'registrySecret'

var namePrefix = 'ArcBox'
var keyVaultName = '${namePrefix}-key-${uniqueString(resourceGroup().id)}'

// KeyVault Secret Permissions Assigned to Managed Identity
var secretsPermissions = [
  'get'
]

resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    enableSoftDelete: false
    enablePurgeProtection: false
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        objectId: principalId
        tenantId: subscription().tenantId
        permissions: {
          secrets: secretsPermissions
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

var mySecrets = {
  // spnClientSecret:  spnClientSecret
  azdataPassword:   azdataPassword
  registryPassword: registryPassword
}

resource secretKeys 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = [for item in items(mySecrets):{
  parent: keyVault
  name: item.key
  properties: {
    value: item.value
  }
}]

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
