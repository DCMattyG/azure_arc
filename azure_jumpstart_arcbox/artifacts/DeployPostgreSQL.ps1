param (
    [string]$adminUsername,
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,
    [string]$resourceGroup,
    [string]$subscriptionId,
    [string]$azdataUsername,
    [string]$azdataPassword
)

$ErrorActionPreference = 'SilentlyContinue'

function Format-Json {
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [object]$jsonObject
    )

    $newtonJson = [Newtonsoft.Json.JsonConvert]::DeserializeObject($(ConvertTo-Json $jsonObject -Depth 8))
    $outputJson = [Newtonsoft.Json.JsonConvert]::SerializeObject($newtonJson, [Newtonsoft.Json.Formatting]::Indented)

    return $outputJson
}

# Set ArcBox paths
$scriptDir = "C:\ArcBox\Scripts"
$logDir = "C:\ArcBox\Logs"

Start-Transcript -Path "${logDir}\deployPostgreSQL.log"

# Deployment environment variables
$controllerName = "arcbox-dc" # This value needs to match the value of the data controller name as set by the ARM template deployment.

# Create Service Principal credential object
$secPassword = ConvertTo-SecureString $spnClientSecret -AsPlainText -Force
$credObject = New-Object System.Management.Automation.PSCredential($spnClientId, $secPassword)

# Azure PowerShell login with Serivce Principal
Write-Output "Logging into Azure PowerShell..."
Connect-AzAccount -ServicePrincipal -SubscriptionId $subscriptionId -TenantId $spnTenantId -Credential $credObject
Set-AzContext -Subscription $subscriptionId

# Required for CLI commands
Write-Output "Logging into Azure CLI..."
az login --service-principal --username $spnClientId --password $spnClientSecret --tenant $spnTenantId

# Deploying Azure Arc PostgreSQL Hyperscale
Write-Host "Deploying Azure Arc PostgreSQL Hyperscale"
Write-Host "`n"

$dataControllerId = $(az resource show --resource-group $resourceGroup --name $controllerName --resource-type "Microsoft.AzureArcData/dataControllers" --query id -o tsv)
$customLocationId = $(az customlocation show --name "arcbox-cl" --resource-group $resourceGroup --query id -o tsv)

################################################
# Localize ARM template
################################################
$ServiceType = "LoadBalancer"

# Resource Requests
$coordinatorCoresRequest = "2"
$coordinatorMemoryRequest = "4Gi"
$coordinatorCoresLimit = "4"
$coordinatorMemoryLimit = "8Gi"

# Storage
$storageClassName = "managed-premium"
$dataStorageSize = "5Gi"
$logsStorageSize = "5Gi"
$backupsStorageSize = "5Gi"

# Citus Scale out
$numWorkers = 1
################################################

$replaceParams = @{
    'resourceGroup'            = $resourceGroup
    'dataControllerId'         = $dataControllerId
    'customLocation'           = $customLocationId
    'subscriptionId'           = $subscriptionId
    'admin'                    = $azdataUsername
    'password'                 = $azdataPassword
    'serviceType'              = $serviceType
    'coordinatorCoresRequest'  = $coordinatorCoresRequest
    'coordinatorCoresLimit'    = $coordinatorCoresLimit
    'coordinatorMemoryRequest' = $coordinatorMemoryRequest
    'coordinatorMemoryLimit'   = $coordinatorMemoryLimit
    'dataStorageSize'          = $dataStorageSize
    'dataStorageClassName'     = $storageClassName
    'logsStorageSize'          = $logsStorageSize
    'logsStorageClassName'     = $storageClassName
    'backupsStorageSize'       = $backupsStorageSize
    'backupsStorageClassName'  = $storageClassName
    'numWorkers'               = $numWorkers
}

Write-Host "Updating Data Controller ARM template parameters..."
$pSQL = "${scriptDir}\postgreSQL.json"
$pSQLParams = "${scriptDir}\postgreSQL.parameters.json"
$pSQLParamsJson = $(Get-Content -Path $pSQLParams -Raw) | ConvertFrom-Json

foreach ($param in $replaceParams.GetEnumerator()) {
    $pSQLParamsJson.parameters.$($param.Name).value = $param.Value
}

$pSQLParamsJson | Format-Json | Set-Content -Path $pSQLParams

Write-Host "Deploying PostgreSQL ARM template..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroup -TemplateFile $pSQL -TemplateParameterFile $pSQLParams

# Ensures postgres container is initiated and ready to accept restores
$pgControllerPodName = "jumpstartpsc0-0"
$pgWorkerPodName = "jumpstartpsw0-0"

do {
    Write-Host "Waiting for PostgreSQL Hyperscale. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 30
    $buildService = $((kubectl get pods -n arc | Select-String $pgControllerPodName | Select-String "Running" -Quiet) -and (kubectl get pods -n arc | Select-String $pgWorkerPodName | Select-String "Running" -Quiet))
} while (-not $buildService)

Start-Sleep -Seconds 60

# Update Service Port from 5432 to Non-Standard
$payload = @{
    spec = @{
        ports = @(
            @{
                name       = "port-pgsql"
                port       = 15432
                targetPort = 5432
            }
        )
    }
}

kubectl patch svc jumpstartps-external-svc -n arc --type merge --patch $($payload | ConvertTo-Json -Depth 4 -Compress).Replace('"', '\"')
Start-Sleep -Seconds 5 # To allow the CRD to update

# Downloading demo database and restoring onto Postgres
Write-Host "Downloading AdventureWorks.sql template for Postgres... (1/3)"
kubectl exec $pgControllerPodName -n arc -c postgres -- /bin/bash -c "curl -o /tmp/AdventureWorks2019.sql 'https://jumpstart.blob.core.windows.net/jumpstartbaks/AdventureWorks2019.sql?sp=r&st=2021-09-08T21:04:16Z&se=2030-09-09T05:04:16Z&spr=https&sv=2020-08-04&sr=b&sig=MJHGMyjV5Dh5gqyvfuWRSsCb4IMNfjnkM%2B05F%2F3mBm8%3D'" 2>&1 | Out-Null
Write-Host "Creating AdventureWorks database on Postgres... (2/3)"
kubectl exec $pgControllerPodName -n arc -c postgres -- psql -U postgres -c 'CREATE DATABASE "adventureworks2019";' postgres 2>&1 | Out-Null
Write-Host "Restoring AdventureWorks database on Postgres. (3/3)"
kubectl exec $pgControllerPodName -n arc -c postgres -- psql -U postgres -d adventureworks2019 -f /tmp/AdventureWorks2019.sql 2>&1 | Out-Null

# Creating Azure Data Studio settings for PostgreSQL connection
Write-Host ""
Write-Host "Creating Azure Data Studio settings for PostgreSQL connection..."
$settingsTemplate = "${scriptDir}\settingsTemplate.json"
# Retrieving PostgreSQL connection endpoint
$pgsqlstring = kubectl get postgresql jumpstartps -n arc -o=jsonpath='{.status.primaryEndpoint}'

# Replace placeholder values in settingsTemplate.json
Write-Host "Updating Settings template..."
$settingsTemplate = "${scriptDir}\settingsTemplate.json"
$settingsJson = $(Get-Content -Path $settingsTemplate -Raw) | ConvertFrom-Json
$settingsJson.'datasource.connections'[1].options.hostaddr = $pgsqlstring.split(":")[0]
$settingsJson.'datasource.connections'[0].options.port = $pgsqlstring.split(":")[1]
$settingsJson.'datasource.connections'[0].options.password = $azdataPassword
# (Get-Content -Path $settingsTemplate) -replace 'false','true' | Set-Content -Path $settingsTemplate
$settingsJson | Format-Json | Set-Content -Path $settingsTemplate
