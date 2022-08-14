@description('Deployment Location')
param location string = resourceGroup().location

@description('Managed Identity Name')
param managedIdentityName string

@description('Owner Role Assignment GUID')
param ownerAssignmentName string = newGuid()

// @description('Contributor Role Assignment GUID')
// param contributorAssignmentName string = newGuid()

// @description('Managed Identity Operator Role Assignment GUID')
// param managedIdentityOperatorAssignmentName string = newGuid()

var owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var ownerId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', owner)
// var contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
// var contributorId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributor)
// var managedIdentityOperator = 'f1a07417-d97a-45cb-824c-7a7467783830'
// var managedIdentityOperatorId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentityOperator)

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: managedIdentityName
  location: location
}

resource ownerAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: ownerAssignmentName
  properties: {
    principalType: 'ServicePrincipal'
    roleDefinitionId: ownerId
    principalId: managedIdentity.properties.principalId
  }
}

// resource contributorAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
//   name: contributorAssignmentName
//   properties: {
//     principalType: 'ServicePrincipal'
//     roleDefinitionId: contributorId
//     principalId: managedIdentity.properties.principalId
//   }
// }

// resource managedIdentityOperatorAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
//   name: managedIdentityOperatorAssignmentName
//   properties: {
//     principalType: 'ServicePrincipal'
//     roleDefinitionId: managedIdentityOperatorId
//     principalId: managedIdentity.properties.principalId
//   }
// }

output principalId string = managedIdentity.properties.principalId
output clientId string = managedIdentity.properties.clientId
output id string = managedIdentity.id
