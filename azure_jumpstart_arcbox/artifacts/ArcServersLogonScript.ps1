param (
    [string]$spnClientId,
    [string]$spnClientSecret,
    [string]$spnTenantId,

    [string]$azureLocation,
    [string]$resourceGroup,
    [string]$subscriptionId,
    [string]$workspaceName,

    [string]$nestedWindowsUsername = "Administrator",
    [string]$nestedWindowsPassword = "ArcDemo123!!",
    [string]$nestedLinuxUsername = "arcdemo",
    [string]$nestedLinuxPassword = "ArcDemo123!!"
)

$ErrorActionPreference = 'SilentlyContinue'

# Set ArcBox paths
$scriptDir = "C:\ArcBox\Scripts"
$vmDir = "C:\ArcBox\Virtual Machines"
$logDir = "C:\ArcBox\Logs"

Start-Transcript "${logDir}\ArcServersLogonScript.log"

# Create ArcBox folders
Write-Output "Create ArcBox folders..."
New-Item -Path $vmDir -ItemType directory -Force

# Create Service Principal credential object
$secPassword = ConvertTo-SecureString $spnClientSecret -AsPlainText -Force
$credObject = New-Object System.Management.Automation.PSCredential($spnClientId, $secPassword)

# Azure PowerShell login with Serivce Principal
Write-Output "Logging into Azure PowerShell..."
Connect-AzAccount -ServicePrincipal -SubscriptionId $subscriptionId -TenantId $spnTenantId -Credential $credObject
Set-AzContext -Subscription $subscriptionId

# Register Azure providers
Write-Output "Registering required providers..."
Register-AzResourceProvider -ProviderNamespace Microsoft.HybridCompute
Register-AzResourceProvider -ProviderNamespace Microsoft.GuestConfiguration

# Install and configure DHCP service (used by Hyper-V nested VMs)
Write-Output "Configure DHCP service..."
$dnsClient = Get-DnsClient | Where-Object {$_.InterfaceAlias -eq "Ethernet" }
Add-DhcpServerv4Scope -Name "ArcBox" -StartRange 10.10.1.1 -EndRange 10.10.1.254 -SubnetMask 255.0.0.0 -State Active
Add-DhcpServerv4ExclusionRange -ScopeID 10.10.1.0 -StartRange 10.10.1.101 -EndRange 10.10.1.120
Set-DhcpServerv4OptionValue -DnsDomain $dnsClient.ConnectionSpecificSuffix -DnsServer 168.63.129.16
Set-DhcpServerv4OptionValue -OptionID 3 -Value 10.10.1.1 -ScopeID 10.10.1.0
Set-DhcpServerv4Scope -ScopeId 10.10.1.0 -LeaseDuration 1.00:00:00
Set-DhcpServerv4OptionValue -ComputerName localhost -ScopeId 10.10.10.0 -DnsServer 8.8.8.8
Restart-Service dhcpserver

# Create the NAT network
Write-Output "Create internal NAT..."
$natName = "InternalNat"
New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 10.10.0.0/16

# Create an internal switch with NAT
Write-Output "Create internal vSwitch.."
$switchName = 'InternalNATSwitch'
New-VMSwitch -Name $switchName -SwitchType Internal
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*"+$switchName+"*" }

# Create an internal network (gateway first)
Write-Output "Creating gateway..."
New-NetIPAddress -IPAddress 10.10.1.1 -PrefixLength 24 -InterfaceIndex $adapter.ifIndex

# Enable Enhanced Session Mode on Host
Write-Output "Enable Enhanced Session Mode..."
Set-VMHost -EnableEnhancedSessionMode $true

# Downloading nested VMs VHDX files
Write-Output "Downloading nested VM VHDX files. This can take some time, hold tight..."
$sourceFolder = 'https://jumpstart.blob.core.windows.net/temp'
$sas = "?sv=2020-08-04&ss=bfqt&srt=sco&sp=rltfx&se=2023-08-01T21:00:19Z&st=2021-08-03T13:00:19Z&spr=https&sig=rNETdxn1Zvm4IA7NT4bEY%2BDQwp0TQPX0GYTB5AECAgY%3D"
azcopy cp --check-md5 FailIfDifferentOrMissing $sourceFolder/*$sas $vmDir --recursive

# Create the nested VMs
Write-Output "Creating Hyper-V VMs..."
New-VM -Name ArcBox-Win2K19 -MemoryStartupBytes 12GB -BootDevice VHD -VHDPath "$vmdir\ArcBox-Win2K19.vhdx" -Path $vmdir -Generation 2 -Switch $switchName
Set-VMProcessor -VMName ArcBox-Win2K19 -Count 2

New-VM -Name ArcBox-Win2K22 -MemoryStartupBytes 12GB -BootDevice VHD -VHDPath "$vmdir\ArcBox-Win2K22.vhdx" -Path $vmdir -Generation 2 -Switch $switchName
Set-VMProcessor -VMName ArcBox-Win2K22 -Count 2

New-VM -Name ArcBox-SQL -MemoryStartupBytes 12GB -BootDevice VHD -VHDPath "$vmdir\ArcBox-SQL.vhdx" -Path $vmdir -Generation 2 -Switch $switchName
Set-VMProcessor -VMName ArcBox-SQL -Count 2

New-VM -Name ArcBox-Ubuntu -MemoryStartupBytes 8GB -BootDevice VHD -VHDPath "$vmdir\ArcBox-Ubuntu.vhdx" -Path $vmdir -Generation 2 -Switch $switchName
Set-VMFirmware -VMName ArcBox-Ubuntu -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
Set-VMProcessor -VMName ArcBox-Ubuntu -Count 1

New-VM -Name ArcBox-CentOS -MemoryStartupBytes 8GB -BootDevice VHD -VHDPath "$vmdir\ArcBox-CentOS.vhdx" -Path $vmdir -Generation 2 -Switch $switchName
Set-VMFirmware -VMName ArcBox-CentOS -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
Set-VMProcessor -VMName ArcBox-CentOS -Count 1

# We always want the VMs to start with the host and shut down cleanly with the host
Write-Output "Set VM auto start/stop..."
Set-VM -Name ArcBox-Win2K19 -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-Win2K22 -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-SQL -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-Ubuntu -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-CentOS -AutomaticStartAction Start -AutomaticStopAction ShutDown

Write-Output "Enabling Guest Integration Service..."
Get-VM | Get-VMIntegrationService | Where-Object {-not($_.Enabled)} | Enable-VMIntegrationService -Verbose

# Start all the VMs
Write-Output "Starting VMs..."
Start-VM -Name ArcBox-Win2K19
Start-VM -Name ArcBox-Win2K22
Start-VM -Name ArcBox-SQL
Start-VM -Name ArcBox-Ubuntu
Start-VM -Name ArcBox-CentOS

Write-Output "Waiting for VMs to start..."
Start-Sleep -Seconds 20

# Create Windows credential object
$secWindowsPassword = ConvertTo-SecureString $nestedWindowsPassword -AsPlainText -Force
$winCredObject = New-Object System.Management.Automation.PSCredential ($nestedWindowsUsername, $secWindowsPassword)

# Create Linux credential object
$secLinuxPassword = ConvertTo-SecureString $nestedLinuxPassword -AsPlainText -Force
$linCredObject = New-Object System.Management.Automation.PSCredential ($nestedLinuxUsername, $secLinuxPassword)

Write-Output "Restarting VM network adapters..."
Invoke-Command -VMName ArcBox-Win2K19 -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCredObject
Invoke-Command -VMName ArcBox-Win2K22 -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCredObject
Invoke-Command -VMName ArcBox-SQL -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCredObject

Write-Output "Waiting for operation to complete..."
Start-Sleep -Seconds 5

# Configure the ArcBox Hyper-V host to allow the nested VMs onboard as Azure Arc-enabled servers
Write-Output "Configure the ArcBox Hyper-V host to allow the nested VMs onboard as Azure Arc-enabled servers..."
Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
Stop-Service WindowsAzureGuestAgent -Force -Verbose
New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254

# Getting the Ubuntu nested VM IP address
Write-Output "Fetching Ubuntu VM IP address.."
$UbuntuVmIp = Get-VM -Name ArcBox-Ubuntu | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0

# Getting the CentOS nested VM IP address
Write-Output "Fetching CentOS VM IP address.."
$CentOSVmIp = Get-VM -Name ArcBox-CentOS | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0

$replaceFiles = @(
    'installArcAgent.ps1'
    'installArcAgentSQL.ps1'
    'installArcAgentCentOS.sh'
    'installArcAgentUbuntu.sh'
)

$replaceMap = @{
    '$azureLocation'             = $azureLocation
    '$myResourceGroup'           = $resourceGroup
    '$subscriptionId'            = $subscriptionId
    '$spnClientId'               = $spnClientId
    '$spnClientSecret'           = $spnClientSecret
    '$spnTenantId'               = $spnTenantId
    '$logAnalyticsWorkspaceName' = $workspaceName
}

Write-Output "Replacing values within Arc Agent install scripts..."
foreach ($file in $replaceFiles) {
    $content = Get-Content "${scriptDir}\${file}"

    foreach ($item in $replaceMap.GetEnumerator()) {
        $content = $content.Replace($item.Name, "'$($item.Value)'")
    }

    $content -join "`n" | Set-Content -Path "${scriptDir}\${file}" -NoNewline
}

# Copy installtion script to nested Windows VMs
Write-Output "Transferring installation script to nested Windows VMs..."
Copy-VMFile ArcBox-Win2K19 -SourcePath "$scriptDir\installArcAgent.ps1" -DestinationPath C:\Temp\installArcAgent.ps1 -CreateFullPath -FileSource Host
Copy-VMFile ArcBox-Win2K22 -SourcePath "$scriptDir\installArcAgent.ps1" -DestinationPath C:\Temp\installArcAgent.ps1 -CreateFullPath -FileSource Host
Copy-VMFile ArcBox-SQL -SourcePath "$scriptDir\installArcAgentSQL.ps1" -DestinationPath C:\Temp\installArcAgentSQL.ps1 -CreateFullPath -FileSource Host

# Copy installtion script to nested Linux VMs
Write-Output "Transferring installation script to nested Linux VMs..."
Set-SCPItem -ComputerName $UbuntuVmIp -Credential $linCredObject -Destination '/tmp/' -Path "${scriptDir}\installArcAgentUbuntu.sh" -Force
Set-SCPItem -ComputerName $CentOSVmIp -Credential $linCredObject -Destination '/tmp/' -Path "${scriptDir}\installArcAgentCentOS.sh" -Force

# Onboarding the nested VMs as Azure Arc-enabled servers
Write-Output "Onboarding the nested Windows VMs as Azure Arc-enabled servers..."
Invoke-Command -VMName ArcBox-Win2K19 -ScriptBlock { powershell -File C:\Temp\installArcAgent.ps1 } -Credential $winCredObject
Invoke-Command -VMName ArcBox-Win2K22 -ScriptBlock { powershell -File C:\Temp\installArcAgent.ps1 } -Credential $winCredObject
Invoke-Command -VMName ArcBox-SQL -ScriptBlock { powershell -File C:\Temp\installArcAgentSQL.ps1 } -Credential $winCredObject

Write-Output "Onboarding the nested Linux VMs as Azure Arc-enabled servers..."
# Onboarding nested Ubuntu server VM
$ubuntuSession = New-SSHSession -ComputerName $UbuntuVmIp -Credential $linCredObject -Force -WarningAction SilentlyContinue
$Command = "sudo sh /tmp/installArcAgentUbuntu.sh"
$(Invoke-SSHCommand -SSHSession $ubuntuSession -Command $Command -Timeout 60 -WarningAction SilentlyContinue).Output

# Onboarding nested CentOS server VM
$centosSession = New-SSHSession -ComputerName $CentOSVmIp -Credential $linCredObject -Force -WarningAction SilentlyContinue
$Command = "sudo sh /tmp/installArcAgentCentOS.sh"
$(Invoke-SSHCommand -SSHSession $centosSession -Command $Command -TimeOut 60 -WarningAction SilentlyContinue).Output

# Creating Hyper-V Manager desktop shortcut
Copy-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Hyper-V Manager.lnk" -Destination "C:\Users\All Users\Desktop" -Force

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Write-Output "Removing scheduled task..."
Unregister-ScheduledTask -TaskName "ArcServersLogonScript" -Confirm:$false
Start-Sleep -Seconds 5
