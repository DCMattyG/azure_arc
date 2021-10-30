param (
    [string]$adminUsername,
    [string]$azdataUsername,
    [string]$azdataPassword
)

$ErrorActionPreference = 'SilentlyContinue'

Start-Transcript -Path C:\ArcBox\SQLMIEndpoints.log

$appDir = "C:\ArcBox\Apps"

# Creating SQLMI Endpoints file 
New-Item -Path $appDir -Name "SQLMIEndpoints.txt" -ItemType "file" 
$endpoints = "${appDir}\SQLMIEndpoints.txt"

# Retrieving SQL MI connection endpoints
Add-Content $endpoints "Primary SQL Managed Instance external endpoint:"
$primaryEndpoint = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.primaryEndpoint}'
if ($primaryEndpoint) {
    $primaryEndpoint = $primaryEndpoint.Substring(0, $primaryEndpoint.IndexOf(',')) | Add-Content $endpoints
}
Add-Content $endpoints ""

Add-Content $endpoints "Secondary SQL Managed Instance external endpoint:"
$secondaryEndpoint = kubectl get sqlmanagedinstances jumpstart-sql -n arc -o=jsonpath='{.status.secondaryEndpoint}'
if ($secondaryEndpoint) {
    $secondaryEndpoint = $secondaryEndpoint.Substring(0, $secondaryEndpoint.IndexOf(',')) | Add-Content $endpoints
}

# Retrieving SQL MI connection username and password
Add-Content $endpoints ""
Add-Content $endpoints "SQL Managed Instance username:"
$adminUsername | Add-Content $endpoints

Add-Content $endpoints ""
Add-Content $endpoints "SQL Managed Instance password:"
$azdataPassword | Add-Content $endpoints

Write-Host "`n"
Write-Host "Creating SQLMI Endpoints file Desktop shortcut..."
Write-Host "`n"
$targetFile = $endpoints
$shortcutFile = "C:\Users\${adminUsername}\Desktop\SQLMI Endpoints.lnk"
$wScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $wScriptShell.CreateShortcut($shortcutFile)
$shortcut.TargetPath = $targetFile
$shortcut.Save()
