<#
.SYNOPSIS
Runs Azure Developer CLI commands from this project's root.
.EXAMPLE
.\Invoke-Azd.ps1
.EXAMPLE
.\Invoke-Azd.ps1 -Command provision -EnvironmentName azdwork-stage
.EXAMPLE
.\Invoke-Azd.ps1 -Command deploy -EnvironmentName azdwork-stage
.EXAMPLE
.\Invoke-Azd.ps1 -Command up -EnvironmentName azdwork-stage
#>
[CmdletBinding()]
param(
    [ValidateSet('version', 'provision', 'deploy', 'up')]
    [string]$Command = 'version',

    [string]$EnvironmentName
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command azd -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'Azure Developer CLI (azd) was not found. Install it from https://aka.ms/azd.'
}

if ($Command -eq 'version' -and $EnvironmentName) {
    throw '-EnvironmentName applies only to provision, deploy, and up.'
}

$azdArguments = @($Command, '--cwd', $PSScriptRoot)
if ($EnvironmentName) {
    $azdArguments += @('--environment', $EnvironmentName)
}

$passwordWasPrompted = $false
try {
    if ($Command -in @('provision', 'up')) {
        if ([string]::IsNullOrEmpty($env:TF_VAR_jumpbox_admin_password)) {
            $securePassword = Read-Host 'Jumpbox password (12-72 characters; at least three character categories)' -AsSecureString
            try {
                $env:TF_VAR_jumpbox_admin_password = [System.Net.NetworkCredential]::new('', $securePassword).Password
                $passwordWasPrompted = $true
            }
            finally {
                if ($securePassword) {
                    $securePassword.Dispose()
                }
            }
        }

        & (Join-Path $PSScriptRoot 'scripts/preprovision.ps1')
    }

    & azd @azdArguments
    if ($LASTEXITCODE -ne 0) {
        throw "azd $Command failed with exit code $LASTEXITCODE."
    }
}
finally {
    if ($passwordWasPrompted) {
        Remove-Item Env:TF_VAR_jumpbox_admin_password -ErrorAction SilentlyContinue
    }
}
