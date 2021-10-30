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
$appDir = "C:\ArcBox\Apps"

Start-Transcript -Path "${logDir}\deploySQL.log"

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

# Deploying Azure Arc SQL Managed Instance
Write-Host "Deploying Azure Arc SQL Managed Instance"
Write-Host "`n"

$dataControllerId = $(Get-AzResource -Name $controllerName -ResourceGroupName $resourceGroup -ResourceType "Microsoft.AzureArcData/dataControllers").id
$customLocationId = $(az customlocation show --name "arcbox-cl" --resource-group $resourceGroup --query id -o tsv)

################################################
# Localize ARM template
################################################
$serviceType = "LoadBalancer"

# Resource Requests
$vCoresRequest = "2"
$memoryRequest = "4Gi"
$vCoresLimit =  "4"
$memoryLimit = "8Gi"

# Storage
$storageClassName = "managed-premium"
$dataStorageSize = "5"
$logsStorageSize = "5"
$dataLogsStorageSize = "5"
$backupsStorageSize = "5"

# High Availability
$replicas = 1 # Value can be either 1 or 3
################################################

$replaceParams = @{
    'resourceGroup'            = $resourceGroup
    'dataControllerId'         = $dataControllerId
    'customLocation'           = $customLocationId
    'subscriptionId'           = $subscriptionId
    'admin'                    = $azdataUsername
    'password'                 = $azdataPassword
    'serviceType'              = $serviceType
    'vCoresRequest'            = $vCoresRequest
    'memoryRequest'            = $memoryRequest
    'vCoresLimit'              = $vCoresLimit
    'memoryLimit'              = $memoryLimit
    'dataStorageSize'          = $dataStorageSize
    'dataStorageClassName'     = $storageClassName
    'logsStorageClassName'     = $storageClassName
    'dataLogsStorageClassName' = $storageClassName
    'backupsStorageClassName'  = $storageClassName
    'logsStorageSize'          = $logsStorageSize
    'dataLogsStorageSize'      = $dataLogsStorageSize
    'backupsStorageSize'       = $backupsStorageSize
    'replicas'                 = $replicas
}

Write-Host "Updating Data Controller ARM template parameters..."
$sqlMI = "${scriptDir}\sqlmi.json"
$sqlMIParams = "${scriptDir}\sqlmi.parameters.json"
$sqlMIParamsJson = $(Get-Content -Path $sqlMIParams -Raw) | ConvertFrom-Json

foreach ($param in $replaceParams.GetEnumerator()) {
    $sqlMIParamsJson.parameters.$($param.Name).value = $param.Value
}

$sqlMIParamsJson | Format-Json | Set-Content -Path $sqlMIParams

Write-Host "Deploying SQLMI ARM template..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroup -TemplateFile $sqlMI -TemplateParameterFile $sqlMIParams

Write-Host "`n"

do {
    Write-Host "Waiting for SQL Managed Instance. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 30
    $dcStatus = $(kubectl get sqlmanagedinstances -n arc | Select-String "Ready" -Quiet)
} while (-not $dcStatus)

Write-Host "Azure Arc SQL Managed Instance is ready!"
Write-Host "`n"

# Update Service Port from 1433 to Non-Standard
$payload = @{
    spec = @{
        ports = @(
            @{
                name       = "port-mssql-tds"
                port       = 11433
                targetPort = 1433
            }
        )
    }
}

kubectl patch svc jumpstart-sql-external-svc -n arc --type merge --patch $($payload | ConvertTo-Json -Depth 4 -Compress).Replace('"', '\"')
Start-Sleep -Seconds 5 # To allow the CRD to update

# Downloading demo database and restoring onto SQL MI
$podname = "jumpstart-sql-0"
Write-Host "Downloading AdventureWorks database for MS SQL... (1/2)"
kubectl exec $podname -n arc -c arc-sqlmi -- wget https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2019.bak -O /var/opt/mssql/data/AdventureWorks2019.bak 2>&1 | Out-Null
Write-Host "Restoring AdventureWorks database for MS SQL. (2/2)"
kubectl exec $podname -n arc -c arc-sqlmi -- /opt/mssql-tools/bin/sqlcmd -S localhost -U $azdataUsername -P $azdataPassword -Q "RESTORE DATABASE AdventureWorks2019 FROM  DISK = N'/var/opt/mssql/data/AdventureWorks2019.bak' WITH MOVE 'AdventureWorks2017' TO '/var/opt/mssql/data/AdventureWorks2019.mdf', MOVE 'AdventureWorks2017_Log' TO '/var/opt/mssql/data/AdventureWorks2019_Log.ldf'" 2>&1 $null

# Creating Azure Data Studio settings for SQL Managed Instance connection
Write-Host ""
Write-Host "Creating Azure Data Studio settings for SQL Managed Instance connection"

# Retrieving SQL MI connection endpoint
$sqlstring = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.primaryEndpoint}'

# Replace placeholder values in settingsTemplate.json
Write-Host "Updating Settings template..."
$settingsTemplate = "${scriptDir}\settingsTemplate.json"
$settingsJson = $(Get-Content -Path $settingsTemplate -Raw) | ConvertFrom-Json
$settingsJson.'datasource.connections'[0].options.server = $sqlstring
$settingsJson.'datasource.connections'[0].options.user = $azdataUsername
$settingsJson.'datasource.connections'[0].options.password = $azdataPassword
# (Get-Content -Path $settingsTemplate) -replace 'false','true' | Set-Content -Path $settingsTemplate
$settingsJson | Format-Json | Set-Content -Path $settingsTemplate

# Unzip SqlQueryStress
Expand-Archive -Path "${appDir}\SqlQueryStress.zip" -DestinationPath "${appDir}\SqlQueryStress"

# Create SQLQueryStress desktop shortcut
Write-Host "`n"
Write-Host "Creating SQLQueryStress Desktop shortcut"
Write-Host "`n"
$targetFile = "${appDir}\SqlQueryStress\SqlQueryStress.exe"
$shortcutFile = "C:\Users\${adminUsername}\Desktop\SqlQueryStress.lnk"
$wScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $wScriptShell.CreateShortcut($shortcutFile)
$shortcut.TargetPath = $targetFile
$shortcut.Save()

# Creating SQLMI Endpoints data
& $scriptDir\SQLMIEndpoints.ps1 -adminUsername $adminUsername -azdataUsername $azdataUsername -azdataPassword $azdataPassword
