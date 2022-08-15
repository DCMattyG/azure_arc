// @description('AppConfig Name')
// param appConfigName string

@description('Deployment Location')
param location string = resourceGroup().location

@description('Managed Identity PrincipalId')
param principalId string

@description('The name of the Cluster API workload cluster to be connected as an Azure Arc-enabled Kubernetes cluster')
param capiArcDataClusterName string = 'ArcBox-CAPI-Data'

@description('Username for the Virtual Machine')
param windowsAdminUsername string = 'arcdemo'

// @description('Client id of the service principal')
// param spnClientId string

// @description('Tenant id of the service principal')
// param spnTenantId string

param spnAuthority string = environment().authentication.loginEndpoint

param azdataUsername string = 'arcdemo'

param acceptEula string = 'yes'

param registryUsername string = 'registryUser'

param arcDcName string = 'arcdatactrl'

param mssqlmiName string = 'arcsqlmidemo'

@description('Name of PostgreSQL server group')
param postgresName string = 'arcpg'

@description('Number of PostgreSQL worker nodes')
param postgresWorkerNodeCount int = 3

@description('Size of data volumes in MB')
param postgresDatasize int = 1024

@description('Choose how PostgreSQL service is accessed through Kubernetes networking interface')
param postgresServiceType string = 'LoadBalancer'

@description('Name for the staging storage account using to hold kubeconfig. This value is passed into the template as an output from mgmtStagingStorage.json')
param stagingStorageAccountName string

@description('Name for the environment Azure Log Analytics workspace')
param workspaceName string

@description('The base URL used for accessing artifacts and automation artifacts.')
param templateBaseUrl string

@description('The flavor of ArcBox you want to deploy. Valid values are: \'Full\', \'ITPro\'')
@allowed([
  'Full'
  'ITPro'
  'DevOps'
])
param flavor string = 'Full'

@description('User github account where they have forked https://github.com/microsoft/azure-arc-jumpstart-apps')
param githubUser string

@description('The name of the K3s cluster')
param k3sArcClusterName string = 'ArcBox-K3s'

@description('Role Assignment GUID')
param roleAssignmentName string = newGuid()

var appConfigDataReader = '516239f1-63e1-4d78-a4de-a74fb236a071'
var appConfigDataReaderId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', appConfigDataReader)

var namePrefix = 'ArcBox'
var appConfigName = '${namePrefix}-cfg-${uniqueString(resourceGroup().id)}'

var mySettings = {
  adminUsername:              windowsAdminUsername
  // spnClientId:                spnClientId
  // spnTenantId:                spnTenantId
  vmPrincipalId:              principalId
  spnAuthority:               spnAuthority
  subscriptionId:             subscription().subscriptionId
  resourceGroup:              resourceGroup().name
  azdataUsername:             azdataUsername
  acceptEula:                 acceptEula
  registryUsername:           registryUsername
  arcDcName:                  arcDcName
  azureLocation:              location
  mssqlmiName:                mssqlmiName
  POSTGRES_NAME:              postgresName
  POSTGRES_WORKER_NODE_COUNT: '${postgresWorkerNodeCount}'
  POSTGRES_DATASIZE:          '${postgresDatasize}'
  POSTGRES_SERVICE_TYPE:      postgresServiceType
  stagingStorageAccountName:  stagingStorageAccountName
  workspaceNameKey:           workspaceName
  templateBaseUrl:            templateBaseUrl
  flavor:                     flavor
  capiArcDataClusterName:     capiArcDataClusterName
  k3sArcClusterName:          k3sArcClusterName
  githubUser:                 githubUser
}

resource configStore 'Microsoft.AppConfiguration/configurationStores@2021-10-01-preview' = {
  name: appConfigName
  location: location
  sku: {
    name: 'standard'
  }
}

resource configStoreKeyValue 'Microsoft.AppConfiguration/configurationStores/keyValues@2021-10-01-preview' = [for item in items(mySettings):{
  parent: configStore
  name: item.key
  properties: {
    value: item.value
    // contentType: contentType
    // tags: tags
  }
}]

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: roleAssignmentName
  scope: configStore
  properties: {
    principalType: 'ServicePrincipal'
    roleDefinitionId: appConfigDataReaderId
    principalId: principalId
  }
}

output appConfigName string = configStore.name
output appConfigUri string = configStore.properties.endpoint
