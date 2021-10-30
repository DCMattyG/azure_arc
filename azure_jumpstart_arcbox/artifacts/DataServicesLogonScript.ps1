param (
    [string]$adminUsername,
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,
    [string]$stagingStorageAccountName,
    [string]$azureLocation,
    [string]$resourceGroup,
    [string]$subscriptionId,
    [string]$workspaceName,
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

Start-Transcript -Path "${logDir}\DataServicesLogonScript.log"

Write-Output "Disabling Windows Firewall..."
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

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

# Install Azure Data Studio extensions
Write-Host "`n"
Write-Host "Installing Azure Data Studio Extensions"
Write-Host "`n"
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd --install-extension Microsoft.arc"
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd --install-extension Microsoft.azuredatastudio-postgresql"

# Create Azure Data Studio desktop shortcut
Write-Host "`n"
Write-Host "Creating Azure Data Studio Desktop shortcut..."
Write-Host "`n"
$targetFile = "C:\Program Files\Azure Data Studio\azuredatastudio.exe"
$shortcutFile = "C:\Users\${adminUsername}\Desktop\Azure Data Studio.lnk"
$wScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $wScriptShell.CreateShortcut($shortcutFile)
$shortcut.TargetPath = $targetFile
$shortcut.Save()

# Register Azure providers
Write-Output "Registering required providers..."
Register-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
Register-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
Register-AzResourceProvider -ProviderNamespace Microsoft.ExtendedLocation
Register-AzResourceProvider -ProviderNamespace Microsoft.AzureArcData

# Making extension install dynamic
az config set extension.use_dynamic_install=yes_without_prompt
Write-Host "`n"
az -v

# Downloading CAPI Kubernetes cluster kubeconfig file
Write-Host "Downloading CAPI Kubernetes cluster kubeconfig file..."
$sourceFile = "https://${stagingStorageAccountName}.blob.core.windows.net/staging-capi/config.arcbox-capi-data"
$context = (Get-AzStorageAccount -ResourceGroupName $resourceGroup).Context
$sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
$sourceFile = $sourceFile + $sas
azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile "C:\Users\${adminUsername}\.kube\config"
kubectl config rename-context "arcbox-capi-data-admin@arcbox-capi-data" "arcbox-capi"

# Creating Storage Class with azure-managed-disk for the CAPI cluster
Write-Host "`n"
Write-Host "Creating Storage Class with azure-managed-disk for the CAPI cluster"
kubectl apply -f "${scriptDir}\capiStorageClass.yaml"

kubectl label node --all failure-domain.beta.kubernetes.io/zone-
kubectl label node --all topology.kubernetes.io/zone-
kubectl label node --all failure-domain.beta.kubernetes.io/zone= --overwrite
kubectl label node --all topology.kubernetes.io/zone= --overwrite

Write-Host "Checking kubernetes nodes"
Write-Host "`n"
kubectl get nodes
azdata --version

# Onboarding the CAPI cluster as an Azure Arc-enabled Kubernetes cluster
Write-Host "Onboarding the cluster as an Azure Arc-enabled Kubernetes cluster"
Write-Host "`n"
$connectedClusterName="ArcBox-CAPI-Data"
az connectedk8s connect --name $connectedClusterName --resource-group $resourceGroup --location $azureLocation --tags 'Project=jumpstart_arcbox'
Start-Sleep -Seconds 10
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host }}
az k8s-extension create --name arc-data-services --extension-type microsoft.arcdataservices --cluster-type connectedClusters --cluster-name $connectedClusterName --resource-group $resourceGroup --auto-upgrade false --scope cluster --release-namespace arc --config Microsoft.CustomLocation.ServiceAccount=sa-bootstrapper

do {
    Write-Host "Waiting for bootstrapper pod, hold tight..."
    Start-Sleep -Seconds 30
    $podStatus = $(if(kubectl get pods -n arc | Select-String "bootstrapper" | Select-String "Running" -Quiet){"Ready!"}Else{"Nope"})
} while ($podStatus -eq "Nope")

$connectedClusterId = az connectedk8s show --name $connectedClusterName --resource-group $resourceGroup --query id -o tsv
$extensionId = az k8s-extension show --name arc-data-services --cluster-type connectedClusters --cluster-name $connectedClusterName --resource-group $resourceGroup --query id -o tsv
Start-Sleep -Seconds 20
az customlocation create --name 'arcbox-cl' --resource-group $resourceGroup --namespace arc --host-resource-id $connectedClusterId --cluster-extension-ids $extensionId --kubeconfig "C:\Users\${adminUsername}\.kube\config"

Write-Output "Getting Workspace ID..."
$workspaceResourceId = $(Get-AzOperationalInsightsWorkspace -Name $workspaceName -ResourceGroupName $resourceGroup).ResourceId

# Deploying Azure Monitor for containers Kubernetes extension instance
Write-Host "`n"
Write-Host "Create Azure Monitor for containers Kubernetes extension instance"
Write-Host "`n"
az k8s-extension create --name "azuremonitor-containers" --cluster-name $connectedClusterName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceResourceId

# Deploying Azure Defender Kubernetes extension instance
Write-Host "`n"
Write-Host "Create Azure Defender Kubernetes extension instance"
Write-Host "`n"
az k8s-extension create --name "azure-defender" --cluster-name $connectedClusterName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureDefender.Kubernetes --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceResourceId

# Deploying Azure Arc Data Controller
Write-Host "Deploying Azure Arc Data Controller"
Write-Host "`n"

$customLocationId = $(az customlocation show --name "arcbox-cl" --resource-group $resourceGroup --query id -o tsv)
$workspaceId = $(Get-AzOperationalInsightsWorkspace -Name $workspaceName -ResourceGroupName $resourceGroup).CustomerId.Guid
$workspaceKey = $(Get-AzOperationalInsightsWorkspaceSharedKey -Name $workspaceName -ResourceGroupName $resourceGroup).PrimarySharedKey

$replaceParams = @{
    'resourceGroup'           = $resourceGroup
    'azdataUsername'          = $azdataUsername
    'azdataPassword'          = $azdataPassword
    'customLocation'          = $customLocationId
    'subscriptionId'          = $subscriptionId
    'spnClientId'             = $spnClientId
    'spnClientSecret'         = $spnClientSecret
    'spnTenantId'             = $spnTenantId
    'logAnalyticsWorkspaceId' = $workspaceId
    'logAnalyticsPrimaryKey'  = $workspaceKey
}

Write-Host "Updating Data Controller ARM template parameters..."
$dataController = "${scriptDir}\dataController.json"
$dataControllerParams = "${scriptDir}\dataController.parameters.json"
$dataParamsJson = $(Get-Content -Path $dataControllerParams -Raw) | ConvertFrom-Json

foreach ($param in $replaceParams.GetEnumerator()) {
    $dataParamsJson.parameters.$($param.Name).value = $param.Value
}

$dataParamsJson | Format-Json | Set-Content -Path $dataControllerParams

Write-Host "Deploying Azure Monitor Workbook ARM template..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroup -TemplateFile $dataController -TemplateParameterFile $dataControllerParams

Write-Host "`n"

do {
    Write-Host "Waiting for data controller. Hold tight, this might take a few minutes..."
    Start-Sleep -Seconds 30
    $dcStatus = $(if(kubectl get datacontroller -n arc | Select-String "Ready" -Quiet) { "Ready!" } Else { "Nope" })
} while ($dcStatus -eq "Nope")

Write-Host "Azure Arc data controller is ready!"
Write-Host "`n"

# Deploy SQL MI and PostgreSQL data services
& $scriptDir\DeploySQLMI.ps1 -adminUsername $adminUsername -spnClientId $spnClientId -spnTenantId $spnTenantId -resourceGroup $resourceGroup -subscriptionId $subscriptionId -azdataUsername $azdataUsername -azdataPassword $azdataPassword
& $scriptDir\DeployPostgreSQL.ps1 -adminUsername $adminUsername -spnClientId $spnClientId -spnTenantId $spnTenantId -resourceGroup $resourceGroup -subscriptionId $subscriptionId -azdataUsername $azdataUsername -azdataPassword $azdataPassword

# Replacing Azure Data Studio settings template file
Write-Host "Replacing Azure Data Studio settings template file"
New-Item -Path "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\" -Name "User" -ItemType "directory" -Force
Copy-Item -Path "${scriptDir}\settingsTemplate.json" -Destination "C:\Users\$adminUsername\AppData\Roaming\azuredatastudio\User\settings.json"

# Downloading Rancher K3s kubeconfig file
Write-Host "Downloading Rancher K3s kubeconfig file"
$sourceFile = "https://$stagingStorageAccountName.blob.core.windows.net/staging-k3s/config"
$context = (Get-AzStorageAccount -ResourceGroupName $resourceGroup).Context
$sas = New-AzStorageAccountSASToken -Context $context -Service Blob -ResourceType Object -Permission racwdlup
$sourceFile = $sourceFile + $sas
azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFile  "C:\Users\${adminUsername}\.kube\config-k3s"

# Merging kubeconfig files from CAPI and Rancher K3s
Write-Host "Merging kubeconfig files from CAPI and Rancher K3s clusters"
Copy-Item -Path "C:\Users\${adminUsername}\.kube\config" -Destination "C:\Users\${adminUsername}\.kube\config.backup"
$env:KUBECONFIG="C:\Users\${adminUsername}\.kube\config;C:\Users\${adminUsername}\.kube\config-k3s"
kubectl config view --raw > C:\users\${adminUsername}\.kube\config_tmp
kubectl config get-clusters --kubeconfig=C:\users\${adminUsername}\.kube\config_tmp
Remove-Item -Path "C:\Users\${adminUsername}\.kube\config"
Remove-Item -Path "C:\Users\${adminUsername}\.kube\config-k3s"
Move-Item -Path "C:\Users\${adminUsername}\.kube\config_tmp" -Destination "C:\Users\${adminUsername}\.kube\config"
$env:KUBECONFIG="C:\Users\${adminUsername}\.kube\config"
kubectx

# Creating desktop url shortcuts for built-in Grafana and Kibana services 
$grafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$grafanaURL = "https://"+$grafanaURL+":3000"
$shell = New-Object -ComObject ("WScript.Shell")
$favorite = $shell.CreateShortcut("C:\Users\${adminUsername}\Desktop\Grafana.url")
$favorite.TargetPath = $grafanaURL;
$favorite.Save()

$kibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$kibanaURL = "https://"+$kibanaURL+":5601"
$shell = New-Object -ComObject ("WScript.Shell")
$favorite = $shell.CreateShortcut("C:\Users\${adminUsername}\Desktop\Kibana.url")
$favorite.TargetPath = $kibanaURL;
$favorite.Save()

# Changing to Jumpstart ArcBox wallpaper
$wallpaperPath = "${scriptDir}\wallpaper.png"

& $scriptDir\changeWallpaper.ps1 -Image $wallpaperPath

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5
