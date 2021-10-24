param (
    [string]$adminUsername,
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,
    [string]$spnAuthority,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azdataUsername,
    [string]$azdataPassword,
    [string]$acceptEula,
    [string]$registryUsername,
    [string]$registryPassword,
    [string]$arcDcName,
    [string]$azureLocation,
    [string]$mssqlmiName,
    [string]$POSTGRES_NAME,   
    [string]$POSTGRES_WORKER_NODE_COUNT,
    [string]$POSTGRES_DATASIZE,
    [string]$POSTGRES_SERVICE_TYPE,
    [string]$stagingStorageAccountName,
    [string]$workspaceName,
    [string]$templateBaseUrl,
    [string]$flavor,
    [string]$automationTriggerAtLogon,
    [string]$githubRepo,
    [string]$githubBranch
)

try {
    $triggerBool = [System.Convert]::ToBoolean($automationTriggerAtLogon) 
} catch [FormatException] {
    $triggerBool = $false
}

$triggerSwitch = @(@{ AtStartup = $true },@{ AtLogon = $true })[$triggerBool]

# Create ArcBox folders
$tmpDir = "C:\Temp"
$scriptDir = "C:\ArcBox\Scripts"
$appDir = "C:\ArcBox\Apps"
$logDir = "C:\ArcBox\Logs"

Write-Output "Create ArcBox folders..."
New-Item -Path $tmpDir -ItemType directory -Force
New-Item -Path $scriptDir -ItemType directory -Force
New-Item -Path $appDir -ItemType directory -Force
New-Item -Path $logDir -ItemType directory -Force

Write-Output "Starting transcript..."
Start-Transcript "${logDir}\Bootstrap.log"

$ErrorActionPreference = 'SilentlyContinue'

# Extending C:\ partition to the maximum size
Write-Host "Extending C:\ partition to the maximum size"
if ($(Get-Partition -DriveLetter C).Size -lt $(Get-PartitionSupportedSize -DriveLetter C).SizeMax) {
    Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax
}

# Installing Posh-SSH PowerShell Module
Write-Output "Installing NuGet and Posh-SSH..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name Posh-SSH -Force

# Installing DHCP service 
Write-Output "Installing DHCP service..."
Install-WindowsFeature -Name "DHCP" -IncludeManagementTools

Write-Output "Checking for Chocolatey..."
if (Test-Path "C:\ProgramData\chocolatey\choco.exe") { 
    Write-Output "Chocolatey already installed, proceeding..."
} else {
    Write-Output "Chocolatey not detected, installing..."
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

Write-Output "Installing required applications via Chocolatey..."
$chocolateyAppsCore = @('azure-cli',
                        'az.powershell',
                        'kubernetes-cli',
                        'vcredist140',
                        'microsoft-edge',
                        'azcopy10',
                        'vscode',
                        'git',
                        '7zip',
                        'kubectx',
                        'terraform',
                        'putty.install',
                        'kubernetes-helm',
                        'dotnetcore-3.1-sdk')

Foreach($app in $chocolateyAppsCore) {
    Write-Host "Installing $app..."
    choco install $app /y | Write-Output
}

Write-Output "Refreshing environment variables..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Set-Location $tmpDir
Write-Output "Cloning Azure Arc Github repo..."
cmd /c "git clone --filter=blob:none --sparse https://github.com/${githubRepo}/azure_arc.git 2>&1"
Set-Location "${tmpDir}\azure_arc"
Write-Output "Checking out GitHub branch..."
cmd /c "git checkout ${githubBranch}"
Write-Output "Sparse checking out artifacts folder from repo..."
cmd /c "git sparse-checkout set azure_jumpstart_arcbox/artifacts 2>&1"
Write-Output "Moving scripts to ArcBox scripts folder..."
Move-Item -Path "${tmpDir}\azure_arc\azure_jumpstart_arcbox\artifacts\*" -Destination $scriptDir

# Creating scheduled task for MonitorWorkbookLogonScript.ps1
Write-Output "Creating schedule task for Azure Arc monitoring..."
$Trigger = New-ScheduledTaskTrigger @triggerSwitch
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File ${scriptDir}\MonitorWorkbookLogonScriptV2.ps1 -spnClientId ${spnClientId} -spnClientSecret ${spnClientSecret} -spnTenantId ${spnTenantId} -resourceGroup ${resourceGroup} -subscriptionId ${subscriptionId} -workspaceName ${workspaceName}"
Register-ScheduledTask -TaskName "MonitorWorkbookLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force

# Disabling Windows Server Manager Scheduled Task
Write-Output "Disabling Server Manager on login..."
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

if ($flavor -in 'Full','ITPro') {
    # Creating scheduled task for ArcServersLogonScript.ps1
    Write-Output "Creating schedule task for Azure Arc servers onboarding..."
    $Trigger = New-ScheduledTaskTrigger @triggerSwitch
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File ${scriptDir}\ArcServersLogonScriptV2.ps1 -spnClientId ${spnClientId} -spnClientSecret ${spnClientSecret} -spnTenantId ${spnTenantId} -azureLocation ${azureLocation} -resourceGroup ${resourceGroup} -subscriptionId ${subscriptionId} -workspaceName ${workspaceName}"
    Register-ScheduledTask -TaskName "ArcServersLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force
}

if ($flavor -in 'Full','Developer') {
    Write-Output "Downloading Azure Data Studio..."
    Invoke-WebRequest "https://azuredatastudio-update.azurewebsites.net/latest/win32-x64-archive/stable" -OutFile "${appDir}\azuredatastudio.zip"
    Write-Output "Downloading Azure Data CLI..."
    Invoke-WebRequest "https://aka.ms/azdata-msi" -OutFile "${appDir}\AZDataCLI.msi"
    Write-Output "Downloading SQL Query Stress Test..."
    Invoke-WebRequest "https://github.com/ErikEJ/SqlQueryStress/releases/download/102/SqlQueryStress.zip" -OutFile "${appDir}\SqlQueryStress.zip"    

    Write-Output "Setting Windows path aliases..."
    New-Item -path alias:kubectl -value 'C:\ProgramData\chocolatey\lib\kubernetes-cli\tools\kubernetes\client\bin\kubectl.exe'
    New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

    Write-Output "Expanding Azure Data Studio..."
    Expand-Archive ${appDir}\azuredatastudio.zip -DestinationPath 'C:\Program Files\Azure Data Studio'
    Write-Output "Installing Azure Data CLI..."
    Start-Process msiexec.exe -Wait -ArgumentList "/I ${appDir}\AZDataCLI.msi /quiet"

    # Creating scheduled task for DataServicesLogonScript.ps1
    Write-Output "Creating schedule task for Azure Arc data services onboarding..."
    $Trigger = New-ScheduledTaskTrigger @triggerSwitch
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "${scriptDir}\DataServicesLogonScript.ps1"
    Register-ScheduledTask -TaskName "DataServicesLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force
}

# $replaceFiles = @(
#     'installArcAgent.ps1'
#     'installArcAgentSQL.ps1'
#     'installArcAgentCentOS.sh'
#     'installArcAgentUbuntu.sh'
# )

# $replaceMap = @{
#     '$azureLocation'             = $azureLocation
#     '$myResourceGroup'           = $resourceGroup
#     '$subscriptionId'            = $subscriptionId
#     '$spnClientId'               = $spnClientId
#     '$spnClientSecret'           = $spnClientSecret
#     '$spnTenantId'               = $spnTenantId
#     '$logAnalyticsWorkspaceName' = $workspaceName
# }

# Write-Output "Replacing values within Arc Agent install scripts..."
# foreach ($file in $replaceFiles) {
#     $content = Get-Content "${scriptDir}\${file}"

#     foreach ($item in $replaceMap.GetEnumerator()) {
#         $content = $content.Replace($item.Name, $item.Value)
#     }

#     Set-Content -Path "${scriptDir}\${file}" -Value $content
# }

Write-Output "Cleaning up temporary directory..."
Remove-Item -Path "${tmpDir}\*" -Recurse -Force

# Install Hyper-V and reboot
Write-Host "Installing Hyper-V role and restarting..."
Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Restart
