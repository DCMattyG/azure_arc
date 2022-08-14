function Write-Header {
    param (
        [string]
        $title
    )

    Write-Host
    Write-Host ("#" * ($title.Length + 8))
    Write-Host "# - $title"
    Write-Host ("#" * ($title.Length + 8))
    Write-Host
}

function Load-Variables {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $AppConfigUri
    )

    Write-Host "Entering Load-Variables..."
    Write-Host "AppConfigUri: $AppConfigUri"

    if($PSBoundParameters.Debug.IsPresent) {
        Write-Host "Debug enabled..."
        $DebugPreference = "Continue"
    }

    Write-Host "Fetching values from App Config..."

    $data = $(az appconfig kv list --endpoint $AppConfigUri --auth-mode login --resolve-keyvault | ConvertFrom-Json)

    Write-Host "DATA:"
    Write-Host "*****************************"
    Write-Host $data
    Write-Host "*****************************"

    Write-Host "Setting process variables..."

    $data | ForEach-Object {
        Write-Host "Loaded { $($_.key): $($_.value) }"
        Write-Debug "Loaded { $($_.key): $($_.value) }"

        [Environment]::SetEnvironmentVariable($_.key, $_.value, [System.EnvironmentVariableTarget]::Process)
        # Set-Item -Path "env:$($_.key)" -Value $_.value
    }
}

function exec
{
    param
    (
        [ScriptBlock] $ScriptBlock,
        [string] $StderrPrefix = "",
        [int[]] $AllowedExitCodes = @(0)
    )
 
    $backupErrorActionPreference = $script:ErrorActionPreference
 
    $script:ErrorActionPreference = "Continue"
    try
    {
        & $ScriptBlock 2>&1 | ForEach-Object -Process `
            {
                if ($_ -is [System.Management.Automation.ErrorRecord])
                {
                    "$StderrPrefix$_"
                }
                else
                {
                    "$_"
                }
            }
        if ($AllowedExitCodes -notcontains $LASTEXITCODE)
        {
            throw "Execution failed with exit code $LASTEXITCODE"
        }
    }
    finally
    {
        $script:ErrorActionPreference = $backupErrorActionPreference
    }
}
