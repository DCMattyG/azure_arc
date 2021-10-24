param (
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,
    [string]$resourceGroup,
    [string]$subscriptionId,
    [string]$workspaceName
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

# Create ArcBox folders
$scriptDir = "C:\ArcBox\Scripts"
$logDir = "C:\ArcBox\Logs"

Write-Output "Create ArcBox folders..."
New-Item -Path $scriptDir -ItemType directory -Force
New-Item -Path $logDir -ItemType directory -Force

Start-Transcript -Path "${logDir}\MonitorWorkbookLogonScript.log"

# Create Service Principal credential object
$secPassword = ConvertTo-SecureString $spnClientSecret -AsPlainText -Force
$credObject = New-Object System.Management.Automation.PSCredential ($spnClientId, $secPassword)

# Azure PowerShell login with Serivce Principal
Write-Output "Logging into Azure PowerShell..."
Connect-AzAccount -ServicePrincipal -SubscriptionId $subscriptionId -TenantId $spnTenantId -Credential $credObject
Set-AzContext -Subscription $subscriptionId

# Update mgmtMonitorWorkbook.json template with subscription ID and resource group values
Write-Host "Updating Azure Monitor Workbook ARM template..."
$monitorWorkbook = "${scriptDir}\mgmtMonitorWorkbook.json"
$monitorJson = $(Get-Content -Path $monitorWorkbook -Raw) | ConvertFrom-Json
$monitorJson.resources[0].properties.serializedData -replace '<subscriptionId>', $subscriptionId
$monitorJson.resources[0].properties.serializedData -replace'<resourceGroup>', $resourceGroup
$monitorJson | Format-Json | Set-Content -Path $monitorWorkbook

# Update mgmtMonitorWorkbook.parameters.json template with workspace resource id
Write-Host "Updating Azure Monitor Workbook ARM template parameters..."
$monitorWorkbookParams = "${scriptDir}\mgmtMonitorWorkbook.parameters.json"
$monitorParamsJson = $(Get-Content -Path $monitorWorkbookParams -Raw) | ConvertFrom-Json
$monitorParamsJson.parameters.workbookResourceId.value = $workspaceResourceId
$monitorParamsJson | Format-Json | Set-Content -Path $monitorWorkbookParams

Write-Host "Deploying Azure Monitor Workbook ARM template..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroup -TemplateFile $monitorWorkbook -TemplateParameterFile $monitorWorkbookParams

# Removing the Scheduled Task
Write-Output "Removing scheduled task..."
Unregister-ScheduledTask -TaskName "MonitorWorkbookLogonScript" -Confirm:$false
